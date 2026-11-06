// WolkaraForever: dictation, in full.

#import "Dictation.h"
#import "AudioSessionCoordinator.h"
#import "../App/WolkaraForeverLog.h"
#import "VoiceSettings.h"

#import <AVFAudio/AVFAudio.h>
#import <Speech/Speech.h>
#import <UIKit/UIKit.h>
#include <math.h>
#include <stdatomic.h>

// kVK_Return, and the character the game expects for it. Taken from the accessory row,
// which sends its Return exactly this way.
static unsigned short const AKReturnKeyCode = 36;
NSNotificationName const AKDictationStateDidChangeNotification = @"AKDictationStateDidChange";
@protocol AKDictationTextTarget <NSObject>
- (void)touchSpecialKey:(unsigned short)code characters:(NSString *)characters;
@end

// How long the recogniser gets to produce its last words after the audio ends.
//
// The capture records a file now and the recogniser reads the whole of it, so this is a whole-file pass
// rather than a streaming one, and it only starts once the audio has ended. This is the safety net for a
// stuck recogniser, not the expected wait - but a file request reports no partials, so a timeout that
// fired early would deliver nothing at all, which is the exact symptom that took days to separate from a
// silent microphone. Generous on purpose.
static NSTimeInterval const AKDefaultFinalizeTimeout = 8.0;

// Per capture, not per process: the loudest sample this capture has heard. Reset when a capture starts,
// so a second hold never reports the first hold's number.
static _Atomic(double) AKLoudestSoFar;

// The same peak as a level in dBFS, because the linear value cannot show the difference that matters:
// a silent input meters at -120 dBFS, which is 0.000001 linear and looks like "not zero" to any check
// written as `> 0`. A room is -50 to -70 dBFS. Kept in decibels so the check can be a threshold that
// silence cannot satisfy.
static _Atomic(double) AKLoudestDecibels = -160.0;

double AKVoiceLoudestDecibels(void) { return AKLoudestDecibels; }

double AKVoiceLoudestSample(void) { return AKLoudestSoFar; }

// The loudest sample a recording holds, as a level in dBFS, read from the recorder's own meter.
//
// The first version of this read the recorded file back with AVAudioFile and reported 0.00000 - which
// was the read failing with error -50, not the microphone being silent. A measurement that can fail and
// still look like the fault it is meant to detect is worse than no measurement, so the level comes from
// the recorder's meter, where silence is -160 dB and cannot be confused with a parse error.

#pragma mark - The real recogniser

// Owns the audio engine, the request and the task, because those three are one thing:
// the engine's tap is what feeds the request, and the request is what the task reads.
@interface AKSpeechSession : NSObject <AKDictationSpeech>
- (instancetype)initWithLocale:(NSLocale *)locale;
@property(nonatomic) BOOL streamsLive;
// Beyond the protocol: run the recognition half over a file that is already on disk. The
// self-test uses these so words can be proved to come back without a person speaking.
- (void)recogniseFile:(NSURL *)file;
- (void)recogniseFile:(NSURL *)file handler:(void (^)(NSString *text, BOOL isFinal, NSError *error))handler;
@end

@implementation AKSpeechSession {
    AVAudioRecorder *_recorder;
    AVAudioEngine *_liveEngine;
    BOOL _liveTapInstalled, _liveRetriedRecordOnly;
    NSUInteger _liveGeneration;
    atomic_uint_fast64_t _liveFrames;
    NSURL *_recording;
    BOOL _onDevice;
    NSArray<NSString *> *_words;
    SFSpeechRecognizer *_recognizer;
    SFSpeechRecognitionRequest *_request;
    SFSpeechRecognitionTask *_task;
    void (^_handler)(NSString *, BOOL, NSError *);
    BOOL _finished;
}

- (instancetype)init { return [self initWithLocale:NSLocale.currentLocale]; }
- (instancetype)initWithLocale:(NSLocale *)locale {
    if ((self = [super init])) _recognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
    return self;
}

- (BOOL)isAvailable { return _recognizer.isAvailable; }
- (BOOL)supportsOnDeviceRecognition { return _recognizer.supportsOnDeviceRecognition; }

- (void)requestAuthorization:(void (^)(BOOL granted))completion {
    // Check both permissions for this request. Cancelling while a system prompt
    // is open is handled by AKDictation's session token when the answer arrives.
    void (^microphone)(BOOL) = ^(BOOL speechGranted) {
        if (!speechGranted) { completion(NO); return; }
        AVAudioSessionRecordPermission permission = AVAudioSession.sharedInstance.recordPermission;
        if (permission != AVAudioSessionRecordPermissionUndetermined) {
            completion(permission == AVAudioSessionRecordPermissionGranted);
            return;
        }
        void (^answer)(BOOL) = ^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(granted); });
        };
        if (@available(iOS 17.0, *)) [AVAudioApplication requestRecordPermissionWithCompletionHandler:answer];
        else [AVAudioSession.sharedInstance requestRecordPermission:answer];
    };
    if (SFSpeechRecognizer.authorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized) {
        microphone(YES);
        return;
    }
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{ microphone(status == SFSpeechRecognizerAuthorizationStatusAuthorized); });
    }];
}

- (void)startOnDevice:(BOOL)onDevice
                words:(NSArray<NSString *> *)words
              handler:(void (^)(NSString *, BOOL, NSError *))handler {
    if (_streamsLive) { _liveRetriedRecordOnly = NO; [self startLiveOnDevice:onDevice words:words handler:handler]; return; }
    _handler = [handler copy];
    _finished = NO;

    _onDevice = onDevice;
    _words = [words copy];
    AKLoudestSoFar = 0;

    // Record to a file instead of tapping an AVAudioEngine.
    //
    // Measured on the device across four session configurations, the engine's tap fired at the right
    // rate with well-formed standard float32 buffers and every sample was exactly 0.0, while the
    // session was correct each time: permission granted, input available, routed to the built-in
    // microphone, and the category read during the capture was a recording one. An AVAudioRecorder is
    // a different implementation of the same session, which is the one thing that tells an engine
    // receiving nothing apart from a microphone delivering nothing - and it leaves the audio on disk,
    // so the peak reported at the end describes what the microphone delivered, not what a consumer of
    // the stream did with it.
    _recording = [NSURL fileURLWithPath:
                  [NSTemporaryDirectory() stringByAppendingPathComponent:@"wolkaraforever-dictation.wav"]];
    [[NSFileManager defaultManager] removeItemAtURL:_recording error:NULL];
    // 16-bit integer LPCM, not 32-bit float.
    //
    // The float settings were mine, and they are the reason every recording this app has made is 4 KB:
    // a header and no audio frames. `record` returns success and `currentTime` advances, so nothing
    // looked wrong, but AVAudioRecorder does not reliably write float LPCM to a file on iOS. 16-bit
    // integer is what every documented example uses, and a recorder that cannot write looks exactly
    // like a microphone that cannot hear.
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @(48000.0),
        AVNumberOfChannelsKey: @(1),
        AVLinearPCMBitDepthKey: @(16),
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsBigEndianKey: @NO,
    };
    NSError *error = nil;

    // Warm the capture before the real one starts, and find out whether it can hear.
    //
    // The one time dictation produced words, the microphone was still open from the press before, so the
    // capture began against a session that had already been running. Every attempt since has started
    // cold and delivered nothing at all - not quiet audio, but no audio: the recording left on the device
    // held zero audio bytes while this code reported "recorded 1.53s". So the microphone is opened and
    // closed once, for a fraction of a second, and only then is the capture the user is speaking into
    // started. That reproduces the only state this app has ever worked in.
    //
    // This probe also answers the question the audio session cannot: whether the microphone hears
    // anything while the session is PlayAndRecord. That category keeps the game audible, and it is the
    // one configuration measured delivering digital silence here, so the answer decides the category for
    // the rest of the hold rather than being assumed either way.
    NSURL *warmup = [NSURL fileURLWithPath:
                     [NSTemporaryDirectory() stringByAppendingPathComponent:@"wolkaraforever-warmup.wav"]];
    [[NSFileManager defaultManager] removeItemAtURL:warmup error:NULL];
    AVAudioRecorder *warmer = [[AVAudioRecorder alloc] initWithURL:warmup settings:settings error:NULL];
    BOOL heardSomething = NO;
    if ([warmer record]) {
        warmer.meteringEnabled = YES;
        [NSThread sleepForTimeInterval:0.15];
        [warmer updateMeters];
        float warmPeak = [warmer peakPowerForChannel:0];
        [warmer stop];
        heardSomething = warmPeak > -60.0f;
        WKLog("voice", @"dictation: warmed the capture for 150ms, peak %.1f dBFS under %@",
              warmPeak, AVAudioSession.sharedInstance.category);
    } else {
        WKLog("voice", @"dictation: the warm-up capture would not start");
    }
    warmer = nil;
    [[NSFileManager defaultManager] removeItemAtURL:warmup error:NULL];
    if (!heardSomething && [AVAudioSession.sharedInstance.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        NSError *demoteError = nil;
        if ([[AKAudioSessionCoordinator shared] useRecordOnlyForPushToTalk:&demoteError]) {
            WKLog("voice", @"dictation: recording with the game's audio paused for this hold, because the microphone was silent while it played");
        } else {
            WKLog("voice", @"dictation: could not drop to Record (%@); carrying on with PlayAndRecord",
                  demoteError.localizedDescription ?: @"no reason given");
        }
    }

    _recorder = [[AVAudioRecorder alloc] initWithURL:_recording settings:settings error:&error];
    if (!_recorder) {
        void (^failed)(NSString *, BOOL, NSError *) = _handler;
        [self cancel];
        if (failed) failed(@"", NO, error ?: [NSError errorWithDomain:@"wolkaraforever.dictation" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"The microphone could not be opened."}]);
        return;
    }
    // So that the peak of the whole capture can be read from the recorder itself when it stops, rather
    // than reconstructed from the file afterwards.
    _recorder.meteringEnabled = YES;
    if (![_recorder record]) {
        NSError *refused = [NSError errorWithDomain:@"wolkaraforever.dictation" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"The microphone did not start recording."}];
        void (^failed)(NSString *, BOOL, NSError *) = _handler;
        [self cancel];
        if (failed) failed(@"", NO, refused);
        return;
    }
    WKLog("voice", @"dictation: recorder started, %.0fHz %lu channel(s), %@; the session is %@; app %@",
          _recorder.format.sampleRate, (unsigned long)_recorder.format.channelCount,
          _recorder.format.isStandard ? @"standard float32" : @"NOT standard",
          AVAudioSession.sharedInstance.category,
          UIApplication.sharedApplication.applicationState == UIApplicationStateActive ? @"active"
              : (UIApplication.sharedApplication.applicationState == UIApplicationStateInactive ? @"inactive" : @"background"));
}

// The toolbar owns a visible draft. It receives partial results while the user
// speaks; none of these callbacks type into the guest. The legacy mapped-input
// path keeps its recorded-file implementation until it is migrated separately.
- (void)startLiveOnDevice:(BOOL)onDevice words:(NSArray<NSString *> *)words
                 handler:(void (^)(NSString *, BOOL, NSError *))handler {
    [self cancel];
    _handler = [handler copy]; _finished = NO;
    NSUInteger generation = ++_liveGeneration;
    atomic_store(&_liveFrames, 0);
    AKLoudestSoFar = 0; AKLoudestDecibels = -160;
    SFSpeechAudioBufferRecognitionRequest *request = [SFSpeechAudioBufferRecognitionRequest new];
    request.requiresOnDeviceRecognition = onDevice;
    request.shouldReportPartialResults = YES;
    // This is conversational text entry. Let Speech format complete sentences,
    // including names and acronyms, rather than rewriting the transcript's case.
    request.taskHint = SFSpeechRecognitionTaskHintDictation;
    request.addsPunctuation = YES;
    request.contextualStrings = words;
    _request = request;
    __weak AKSpeechSession *weakSelf = self;
    _task = [_recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        if (!result && !error) return;
        NSString *text = result.bestTranscription.formattedString ?: @"";
        BOOL final = result.isFinal;
        // Recognition callbacks have no main-thread guarantee. Only this queue
        // may update the draft or the session owner.
        dispatch_async(dispatch_get_main_queue(), ^{
            AKSpeechSession *self = weakSelf;
            if (!self || self->_finished || self->_liveGeneration != generation) return;
            if (final || error) { self->_finished = YES; [self stopLiveInput]; }
            if (self->_handler) self->_handler(text, final, error);
        });
    }];
    NSError *error = nil;
    _liveEngine = [AVAudioEngine new];
    AVAudioInputNode *input = _liveEngine.inputNode;
    AVAudioFormat *format = [input outputFormatForBus:0];
    if (format.sampleRate <= 0 || format.channelCount == 0) {
        [self failLive:@"No microphone input is available."]; return;
    }
    @try {
        [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *time) {
            (void)time;
            AKSpeechSession *self = weakSelf;
            if (!self) return;
            atomic_fetch_add(&self->_liveFrames, buffer.frameLength);
            double peak = 0;
            float *const *channels = buffer.floatChannelData;
            if (channels) for (AVAudioChannelCount c = 0; c < buffer.format.channelCount; c++)
                for (AVAudioFrameCount f = 0; f < buffer.frameLength; f++)
                    peak = MAX(peak, fabs(channels[buffer.format.isInterleaved ? 0 : c][f * buffer.stride + (buffer.format.isInterleaved ? c : 0)]));
            double previous = atomic_load(&AKLoudestSoFar);
            while (peak > previous && !atomic_compare_exchange_weak(&AKLoudestSoFar, &previous, peak)) {}
            double loudest = atomic_load(&AKLoudestSoFar);
            atomic_store(&AKLoudestDecibels, loudest > 0 ? 20 * log10(loudest) : -160);
            [request appendAudioPCMBuffer:buffer];
        }];
        _liveTapInstalled = YES;
        [_liveEngine prepare];
        if (![_liveEngine startAndReturnError:&error]) { [self failLive:error.localizedDescription ?: @"The microphone could not start."]; return; }
    } @catch (NSException *exception) {
        (void)exception;
        [self failLive:@"The microphone format is unavailable. Try recording again."]; return;
    }
    WKLog("voice", @"live dictation: capture started %.0fHz %luch (on-device=%d)", format.sampleRate, (unsigned long)format.channelCount, onDevice);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AKSpeechSession *self = weakSelf;
        if (!self || self->_liveGeneration != generation || self->_finished || !self->_liveEngine) return;
        if (atomic_load(&self->_liveFrames) == 0 || AKVoiceLoudestSample() == 0) {
            // A previous device delivered silence while game playback was mixed
            // with capture. Retry once through the existing audio owner, with
            // playback paused for this hold. Never retry after cancellation.
            [self stopLiveInput];
            NSError *error = nil;
            if (!self->_liveRetriedRecordOnly && [AKAudioSessionCoordinator shared].pushToTalkActive &&
                [[AKAudioSessionCoordinator shared] useRecordOnlyForPushToTalk:&error]) {
                self->_liveRetriedRecordOnly = YES;
                void (^handler)(NSString *, BOOL, NSError *) = self->_handler;
                WKLog("voice", @"live dictation: no captured audio; retrying once with game playback paused");
                [self startLiveOnDevice:onDevice words:words handler:handler];
            } else [self failLive:@"The microphone is not delivering audio. No text has been sent."];
        }
    });
}
- (void)stopLiveInput {
    if (!_liveEngine) return;
    [_liveEngine stop];
    if (_liveTapInstalled) { [_liveEngine.inputNode removeTapOnBus:0]; _liveTapInstalled = NO; }
    _liveEngine = nil;
    WKLog("voice", @"live dictation: capture stopped, %llu frames, peak %.1f dBFS",
        (unsigned long long)atomic_load(&_liveFrames), AKVoiceLoudestDecibels());
}
- (void)failLive:(NSString *)message {
    void (^handler)(NSString *, BOOL, NSError *) = _handler;
    [self cancel];
    if (handler) handler(@"", NO, [NSError errorWithDomain:@"wolkaraforever.dictation" code:4
        userInfo:@{NSLocalizedDescriptionKey:message}]);
}

- (void)finish {
    if (_streamsLive) {
        [self stopLiveInput];
        if ([_request isKindOfClass:SFSpeechAudioBufferRecognitionRequest.class])
            [(SFSpeechAudioBufferRecognitionRequest *)_request endAudio];
        return;
    }
    // Ending the capture is what produces the file the recogniser reads.
    [self stopRecordingAndMeasure];
    if (!_finished) [self recogniseRecording];
}

- (void)cancel {
    _liveGeneration++;
    [self stopLiveInput];
    // The measurement is taken even when the capture is abandoned. A diagnostic that only works on the
    // happy path cannot diagnose the unhappy one, and "cancel" is what a failed press does.
    [self stopRecordingAndMeasure];
    _finished = YES;
    _handler = nil;
    [_task cancel];
    _task = nil;
    _request = nil;
    if (_recording) [[NSFileManager defaultManager] removeItemAtURL:_recording error:NULL];
    _recording = nil;
}

// Stop the recorder and say what it captured. Called by both finish and cancel, so the number exists
// however the press ended.
//
// `updateMeters` refreshes the peak since the previous call, so one call at the end reports the loudest
// moment of the whole recording. Silence is -160 dBFS and is reported as such; anything above it is a
// real level, converted back to a linear peak so the rest of the app still has one number to look at.
- (void)stopRecordingAndMeasure {
    if (!_recorder) return;
    [_recorder updateMeters];
    float decibels = [_recorder peakPowerForChannel:0];
    NSTimeInterval seconds = _recorder.currentTime;
    [_recorder stop];
    _recorder = nil;
    AKLoudestDecibels = (double)decibels;
    AKLoudestSoFar = (decibels <= -160.0f) ? 0.0 : pow(10.0, (double)decibels / 20.0);
    // The file, as well as the microphone.
    //
    // These are different facts and only one of them was being measured: the meter reads what
    // the *input* delivered, so a recorder that writes a header and no frames still meters
    // real level - and then the recogniser is handed an empty file and answers "No speech
    // detected", which reads exactly like a microphone that could not hear. One dictation on
    // the device (2026-10-22) metered -24.8 dBFS and was refused by the recogniser 0.3s later;
    // the byte count and the frame count are what tell those two apart.
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:_recording.path error:NULL];
    unsigned long long bytes = [attributes[NSFileSize] unsignedLongLongValue];
    NSError *readError = nil;
    AVAudioFile *written = [[AVAudioFile alloc] initForReading:_recording error:&readError];
    WKLog("voice", @"dictation: recorded %.2fs, peak %.1f dBFS (%.5f linear), %llu bytes on disk, "
                    @"%lld frames readable%@, session %@, other audio playing %d, app %@",
          seconds, decibels, AKLoudestSoFar, bytes, written ? written.length : 0LL,
          written ? @"" : [NSString stringWithFormat:@" (unreadable: %@)", readError.localizedDescription ?: @"no reason"],
          AVAudioSession.sharedInstance.category,
          (int)AVAudioSession.sharedInstance.isOtherAudioPlaying,
          UIApplication.sharedApplication.applicationState == UIApplicationStateActive ? @"active"
              : (UIApplication.sharedApplication.applicationState == UIApplicationStateInactive ? @"inactive" : @"background"));
}

- (void)recogniseRecording {
    if (!_recording) return;
    [self recogniseFile:_recording];
}

/// The recognition half on its own, for one file. Also the entry point the device self-test uses.
- (void)recogniseFile:(NSURL *)file handler:(void (^)(NSString *text, BOOL isFinal, NSError *error))handler {
    _handler = [handler copy];
    _finished = NO;
    _onDevice = YES;
    [self recogniseFile:file];
}

- (void)recogniseFile:(NSURL *)file {
    if (!file) return;
    // The file is fed to the recogniser as buffers, not handed over as a URL.
    //
    // Both are documented; only one of them has ever produced words on this device. The URL
    // request answers "No speech detected" about a third of a second after a 1.86s hold that
    // metered -24.8 dBFS - too fast to have listened to anything - while the streaming request
    // is the one the build that transcribed 21 characters into the game used. Feeding the file
    // we just wrote through the streaming request keeps that path and keeps the recording, so
    // the same audio can be re-run instead of re-spoken.
    SFSpeechAudioBufferRecognitionRequest *streaming = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    NSError *openError = nil;
    AVAudioFile *captured = [[AVAudioFile alloc] initForReading:file error:&openError];
    if (!captured || captured.length == 0) {
        // Nothing readable to stream: the URL request is still the honest last word, and it
        // will say what it thinks of the file. Whatever it answers, the log already carries
        // the byte and frame counts above.
        WKLog("voice", @"dictation: the recording is not readable as audio (%@), asking the recogniser about the file instead",
              openError.localizedDescription ?: @"no frames");
        SFSpeechURLRecognitionRequest *whole = [[SFSpeechURLRecognitionRequest alloc] initWithURL:file];
        whole.requiresOnDeviceRecognition = _onDevice;
        // Partials are asked for even though nothing is delivered from them - see the note on the
        // streaming request below. With them switched off, the on-device recogniser is measurably
        // capable of never calling back at all.
        whole.shouldReportPartialResults = YES;
        if (_words.count) whole.contextualStrings = _words;
        _request = whole;
    } else {
        streaming.requiresOnDeviceRecognition = _onDevice;
        // Partials on, delivery still final-only.
        //
        // This is what the device said on 2026-10-22: with partial results switched off, the
        // on-device recogniser took all 135,725 frames of a known sentence, was sent endAudio,
        // and then called back *never* - no result and no error, for forty seconds. The app's
        // delivery rule is unchanged and stays where it belongs: `speechReported:` ignores every
        // non-final result, so a partial is a progress signal and nothing else.
        streaming.shouldReportPartialResults = YES;
        if (_words.count) streaming.contextualStrings = _words;
        _request = streaming;
    }

    __weak AKSpeechSession *weakSelf = self;
    _task = [_recognizer recognitionTaskWithRequest:_request
                                      resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
        AKSpeechSession *session = weakSelf;
        if (!session || session->_finished) return;
        NSString *text = result.bestTranscription.formattedString ?: @"";
        // `isFinal` is the recogniser saying it has nothing more for this session.
        // That, or an error, is the moment the caller has been waiting for.
        if (result.isFinal || error) session->_finished = YES;
        if (session->_handler) session->_handler(text, result.isFinal, error);
    }];

    if (_request != streaming) return;
    // Fed off the main queue: a long hold is a longer read, and this runs while the game is
    // drawing. A fresh buffer per chunk because the request is documented to copy the audio it
    // is given, and a buffer that is only copied *sometimes* is the kind of assumption that
    // ends up as an intermittent half-sentence.
    NSURL *fileURL = file;
    AVAudioFrameCount chunk = 4096;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SFSpeechAudioBufferRecognitionRequest *request = streaming;
        NSError *readError = nil;
        AVAudioFile *file = [[AVAudioFile alloc] initForReading:fileURL error:&readError];
        if (!file) {
            WKLog("voice", @"dictation: the recording could not be opened for streaming: %@",
                  readError.localizedDescription ?: @"no reason");
            [request endAudio];
            return;
        }
        AVAudioFormat *format = file.processingFormat;
        AVAudioFramePosition total = file.length, fed = 0;
        while (fed < total) {
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:chunk];
            if (!buffer) break;
            if (![file readIntoBuffer:buffer frameCount:chunk error:&readError]) break;
            if (buffer.frameLength == 0) break;
            [request appendAudioPCMBuffer:buffer];
            fed += (AVAudioFramePosition)buffer.frameLength;
        }
        [request endAudio];
        WKLog("voice", @"dictation: fed %lld of %lld frames (%.0fHz %luch%@) to the recogniser%@",
              fed, total, format.sampleRate, (unsigned long)format.channelCount,
              readError ? @"" : @"",
              readError ? [NSString stringWithFormat:@", read stopped: %@", readError.localizedDescription] : @"");
    });
}

@end

/// The recognition half, for a file somebody else recorded. See the declaration in Dictation.h for
/// why the app needs a way to test this without a person speaking.
void AKRecogniseDictationFile(NSURL *file, void (^completion)(NSString *_Nullable text, NSError *_Nullable error)) {
    if (!completion) return;
    AKSpeechSession *session = [AKSpeechSession new];
    if (!session.isAvailable) {
        completion(nil, [NSError errorWithDomain:@"wolkaraforever.dictation" code:2 userInfo:@{
            NSLocalizedDescriptionKey: @"Speech recognition is not available right now."}]);
        return;
    }
    if (!session.supportsOnDeviceRecognition) {
        completion(nil, [NSError errorWithDomain:@"wolkaraforever.dictation" code:3 userInfo:@{
            NSLocalizedDescriptionKey: @"This iPad cannot recognise speech on device."}]);
        return;
    }
    // Held until it answers. The recogniser task dies with the session that owns it, so a probe
    // whose session is a local - as the first version of this was - sends every frame, gets
    // endAudio, and is then deallocated before the recogniser can call back: no result, no error,
    // and forty seconds of a self-test waiting for a callback that can no longer arrive.
    static NSMutableArray<AKSpeechSession *> *probes;
    static NSLock *probesLock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ probes = [NSMutableArray array]; probesLock = [NSLock new]; });
    [probesLock lock]; [probes addObject:session]; [probesLock unlock];
    __block BOOL reported = NO;
    [session recogniseFile:file handler:^(NSString *text, BOOL isFinal, NSError *error) {
        // A partial result is not an answer, and an error is; whichever comes first ends this.
        if (!isFinal && !error) return;
        if (reported) return;
        reported = YES;
        [probesLock lock]; [probes removeObjectIdenticalTo:session]; [probesLock unlock];
        completion(error ? nil : text, error);
    }];
}

#pragma mark - The real audio session

// Takes the session and gives it back the way it was found. The old code set record
// mode and always left the app at playback, which is a change the game can hear.
@interface AKAudioSessionBridge : NSObject <AKDictationAudio>
@end

@implementation AKAudioSessionBridge

// The session is not this object's to take or to put back. The coordinator owns it, and this asks
// for a push-to-talk lease and hands it back. The answer is whether the session is in the state the
// policy says it should be in - not whether a call returned success, which is a different thing and
// is the one the old code reported while the microphone stayed held.
- (BOOL)beginRecording:(NSError **)error {
    return [[AKAudioSessionCoordinator shared] beginPushToTalk:error];
}

- (BOOL)restore:(NSError **)error {
    return [[AKAudioSessionCoordinator shared] endPushToTalk:error];
}

@end

#pragma mark - Dictation

@implementation AKDictation {
    AKSpeechSession *_realSpeech;
    AKAudioSessionBridge *_realAudio;
    NSMutableString *_transcript;
    BOOL _delivered;
    BOOL _abandoned;
    NSUInteger _session;
    AKDictationCompletion _sessionCompletion;
    void (^_sessionProgress)(NSString *);
    NSString *_sessionProblem;
}

+ (instancetype)shared {
    static AKDictation *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [AKDictation new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _transcript = [NSMutableString string];
        _finalizeTimeout = AKDefaultFinalizeTimeout;
        // The audio session is the coordinator's, and it says when push to talk was ended by an
        // interruption, a media reset or the route going. Dictation used to observe
        // AVAudioSessionInterruptionNotification itself, which is two owners of one session with two
        // ideas about it - what the review outcome's Phase 1 exists to remove.
        __weak AKDictation *weakSelf = self;
        [AKAudioSessionCoordinator shared].pushToTalkWasTaken = ^(NSString *why) {
            AKDictation *self2 = weakSelf;
            if (!self2) return;
            [self2 cancel];
            void (^problem)(NSString *) = self2.problemHandler;
            if (problem) problem([NSString stringWithFormat:@"Something else took the audio (%@), so nothing was typed.", why]);
        };
        // And leaving the app does too. This matters here more than in most apps: the
        // target declares `UIBackgroundModes: [audio]` so a running game keeps its sound,
        // which means iOS does NOT take the session away when the user goes to the Home
        // screen. Without this, a session left listening would hold the microphone and
        // Apple's recogniser open in the background - the user would see the orange
        // indicator with the game behind it, and nothing would ever type the words.
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appLeftTheForeground:)
                                                   name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}

- (void)appLeftTheForeground:(NSNotification *)note {
    (void)note;
    // Said before the state is changed, because the state is what a reader wants to know.
    WKLog("voice", @"dictation: the app went to the background (state=%ld, listening=%d)",
          (long)_state, (int)self.listening);
    if (_state == AKDictationStateIdle) return;
    [self cancel];
    void (^problem)(NSString *) = self.problemHandler;
    if (problem) problem(@"The app went to the background, so nothing was typed.");
}

- (BOOL)listening { return _state == AKDictationStateListening || _state == AKDictationStateFinalizing; }

#pragma mark - The registered target

static __weak UIView *AKGameTextTarget = nil;

+ (void)setGameTextTarget:(nullable UIView *)view { AKGameTextTarget = view; }
+ (nullable UIView *)gameTextTarget { return AKGameTextTarget; }

#pragma mark - Seams

- (id<AKDictationSpeech>)speech {
    if (_speech) return _speech;
    if (!_realSpeech) _realSpeech = [AKSpeechSession new];
    return _realSpeech;
}

- (id<AKDictationAudio>)audio {
    if (_audio) return _audio;
    if (!_realAudio) _realAudio = [AKAudioSessionBridge new];
    return _realAudio;
}

#pragma mark - The one entry point

- (void)toggle {
    if (self.listening) [self end];
    else [self begin];
}

- (BOOL)beginWithLocale:(NSString *)localeIdentifier progress:(void (^)(NSString *))progress completion:(AKDictationCompletion)completion {
    if (_state != AKDictationStateIdle || self.transcriptHandler || !completion) return NO;
    if (!_speech) {
        // The toolbar supplies its explicit, persisted speech language. Callers
        // without a selection retain the system locale fallback.
        NSLocale *locale = localeIdentifier.length && ![localeIdentifier isEqualToString:@"emoji"] ?
            [NSLocale localeWithLocaleIdentifier:localeIdentifier] : NSLocale.currentLocale;
        _realSpeech = [[AKSpeechSession alloc] initWithLocale:locale];
        _realSpeech.streamsLive = YES;
    }
    _sessionCompletion = [completion copy];
    _sessionProgress = [progress copy];
    [self begin];
    return YES;
}

- (void)completeSessionWithText:(NSString *)text problem:(NSString *)problem {
    AKDictationCompletion completion = _sessionCompletion;
    _sessionCompletion = nil;
    _sessionProgress = nil;
    NSString *reported = problem ?: _sessionProblem;
    _sessionProblem = nil;
    [self setState:AKDictationStateIdle];
    if (completion) completion(text, reported);
}

- (void)begin {
    switch (_state) {
    case AKDictationStateIdle: break;
    // Already busy: a second press while the microphone is opening is the same press.
    case AKDictationStateAuthorizing:
    case AKDictationStateListening:
    case AKDictationStateFinalizing: return;
    }
    _abandoned = NO;
    _delivered = NO;
    _sessionProblem = nil;
    [_transcript setString:@""];
    NSUInteger session = ++_session;
    [self setState:AKDictationStateAuthorizing];

    id<AKDictationSpeech> speech = self.speech;
    if (speech == _realSpeech) _realSpeech.streamsLive = _sessionProgress != nil;
    if (!speech.supportsOnDeviceRecognition) {
        [self fail:@"This iPad cannot recognise speech without sending it away, so the microphone stays off."];
        return;
    }
    __weak AKDictation *weakSelf = self;
    [speech requestAuthorization:^(BOOL granted) {
        AKDictation *self2 = weakSelf;
        if (!self2 || self2->_session != session) return;   // a later press replaced this
        if (!granted) { [self2 fail:@"Microphone or speech recognition permission was refused. Allow both in Settings."]; return; }
        [self2 startAudioForSession:session];
    }];
}

- (void)startAudioForSession:(NSUInteger)session {
    if (_session != session || _abandoned) return;
    // Refused before anything is opened, rather than started and failed: the audio
    // session is not ours to take if there is nothing to feed it to.
    if (!self.speech.isAvailable) {
        [self fail:@"Speech recognition is not available right now."];
        return;
    }

    NSError *error = nil;
    if (![self.audio beginRecording:&error]) {
        [self fail:[NSString stringWithFormat:@"The audio session would not start: %@", error.localizedDescription]];
        return;
    }
    __weak AKDictation *weakSelf = self;
    [self.speech startOnDevice:YES words:AKVoiceSettings.shared.customWords
                       handler:^(NSString *transcript, BOOL isFinal, NSError *error2) {
        [weakSelf speechReported:transcript isFinal:isFinal error:error2 session:session];
    }];
    // A recorder can fail synchronously during startOnDevice. Do not resurrect
    // that cancelled session as an apparently live microphone.
    if (_session != session || _abandoned) return;
    [self setState:AKDictationStateListening];
    WKLog("voice", @"dictation: listening (on-device=1)");
}

// Read once, so a recogniser that is unavailable right now is refused rather than
// started and failed.
- (void)end {
    switch (_state) {
    case AKDictationStateIdle:
    case AKDictationStateFinalizing: return;
    case AKDictationStateAuthorizing:
        // Nothing was started. Abandon it, in case the permission answer arrives late.
        _abandoned = YES;
        _session++;
        [self completeSessionWithText:nil problem:nil];
        return;
    case AKDictationStateListening:
        break;
    }
    [self setState:AKDictationStateFinalizing];
    NSUInteger session = _session;
    [self.speech finish];
    // The recogniser is asked for its last words and given a bounded wait. Whichever
    // happens first, delivery happens once.
    __weak AKDictation *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.finalizeTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AKDictation *self2 = weakSelf;
        if (!self2 || self2->_state != AKDictationStateFinalizing || self2->_session != session) return;
        [self2 abandonForTimeout];
    });
}

// The deadline passed. Nothing is delivered.
//
// What is in hand is a *partial* result, and the product's promise is a final transcript:
// putting half a sentence into the game's chat box - and, with auto-submit on, sending it
// - is worse than putting nothing there. The remediation review caught the first version
// doing exactly that and calling it a timeout. The user is told instead, and because a
// timeout is usually the recogniser being unavailable or the microphone being silent,
// saying so is more useful than a guess at what they said.
- (void)abandonForTimeout {
    if (_state != AKDictationStateFinalizing) return;
    WKLog("voice", @"dictation: no final result within %.1fs; nothing will be typed", self.finalizeTimeout);
    [self.speech cancel];
    [self giveTheSessionBack];
    _abandoned = YES;
    _delivered = YES;   // nothing may be delivered for this session
    _session++;
    void (^problem)(NSString *) = self.problemHandler;
    if (problem) problem(@"The recogniser did not finish in time, so nothing was typed.");
    [self completeSessionWithText:nil problem:@"The recogniser did not finish in time, so nothing was typed."];
}

- (void)cancel {
    _abandoned = YES;
    _delivered = YES;   // nothing may be delivered after a cancel
    _session++;
    [self.speech cancel];
    [self giveTheSessionBack];
    [_transcript setString:@""];
    [self completeSessionWithText:nil problem:nil];
}

#pragma mark - What the recogniser says

- (void)speechReported:(NSString *)transcript isFinal:(BOOL)isFinal error:(NSError *)error session:(NSUInteger)session {
    if (_session != session || _abandoned) return;
    if (transcript.length) [_transcript setString:transcript];
    if (error) {
        // An error is not a final result. In particular, a recogniser can report an error after
        // producing a partial transcript; delivering the cached partial here would violate the
        // final-only rule and could auto-submit an incomplete chat message.
        [self fail:[NSString stringWithFormat:@"Recognition stopped: %@", error.localizedDescription]];
        return;
    }
    // Toolbar progress belongs only to its visible draft. Legacy mapped input
    // still receives final-only text. A live recognizer may end after a pause.
    if (_sessionProgress) _sessionProgress(transcript ?: @"");
    if (isFinal && (_state == AKDictationStateFinalizing || _sessionCompletion)) [self finishWithTranscript:transcript];
}

// The one place a session ends well. Everything is put back *before* the words go
// anywhere, so the game's audio is already returning while its input is being typed.
- (void)finishWithTranscript:(nullable NSString *)transcript {
    if (_delivered || _abandoned) return;
    _delivered = YES;
    if (transcript.length) [_transcript setString:transcript];
    [self giveTheSessionBack];
    [self.speech cancel];
    // Detach the completion before observers can start another session.
    AKDictationCompletion completion = _sessionCompletion;
    _sessionCompletion = nil;
    _sessionProgress = nil;
    NSString *text = [_transcript stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *problem = _sessionProblem;
    _sessionProblem = nil;
    [self setState:AKDictationStateIdle];
    if (completion) completion(text, problem);
    else [self deliver];
}

// Handing the session back, once, and saying so when it did not work.
//
// No retries. The review outcome is explicit that a failed put-back leaves an explicit recoverable
// state and a user-visible message rather than an unbounded retry loop, and the retry this replaces
// is the clearest example of why: a retry from a failed put-back could fire after the next dictation
// had begun and take the session away from it, which the user saw as the microphone being broken.
- (void)giveTheSessionBack {
    NSError *error = nil;
    if ([self.audio restore:&error]) return;
    WKLog("voice", @"audio: the session could not be handed back: %@", error.localizedDescription ?: @"no reason given");
    NSString *problem = @"The microphone could not be handed back. If the microphone indicator is still on, close WolkaraForever and open it again.";
    if (_sessionCompletion) _sessionProblem = problem;
    if (self.problemHandler) self.problemHandler(problem);
}

- (void)fail:(NSString *)message {
    WKLog("voice", @"dictation: %@", message);
    [self giveTheSessionBack];
    [self.speech cancel];
    _abandoned = YES;
    _session++;
    void (^problem)(NSString *) = self.problemHandler;
    if (problem) problem(message);
    [self completeSessionWithText:nil problem:message];
}

#pragma mark - The words

- (void)deliver {
    NSString *text = [_transcript stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    void (^handler)(NSString *) = _transcriptHandler;
    if (handler) {
        // A test screen is up: the words are its business, not the game's. It is told
        // even when nothing was heard, so it can say so.
        WKLog("voice", @"dictation: heard %lu characters, for the test screen", (unsigned long)text.length);
        handler(text);
        return;
    }
    if (!text.length) { WKLog("voice", @"dictation: stopped, heard nothing"); return; }
    WKLog("voice", @"dictation: heard %lu characters", (unsigned long)text.length);
    if (AKVoiceSettings.shared.trailingSpace) text = [text stringByAppendingString:@" "];
    if ([self typeIntoGame:text]) {
        // Separately, and deliberately: the text goes in first, then Return - and only
        // when it was asked for, which is Handy's auto-submit.
        if (AKVoiceSettings.shared.autoSubmit) [self sendReturn];
    }
}

- (BOOL)typeIntoGame:(NSString *)text {
    UIView *target = AKDictation.gameTextTarget;
    if (!target) {
        WKLog("voice", @"dictation: the game has not registered a text target; nothing typed");
        return NO;
    }
    // Ask before sending, for the same reason the draft editor asks before inserting a
    // dictation placeholder: an object that does not answer the selector aborts the app,
    // and the target is announced by another module that this one cannot check at compile
    // time. It happened - AKKeyboardTextView was announced instead of the view that can
    // reach the guest, and the first spoken sentence killed the app on the device
    // (2026-10-21). A target that cannot take text loses the words; it never kills a
    // running game.
    SEL selector = NSSelectorFromString(@"touchInsertText:");
    if (![target respondsToSelector:selector]) {
        WKLog("voice", @"dictation: the registered text target (%@) does not take text; nothing typed",
              NSStringFromClass(target.class));
        return NO;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [target performSelector:selector withObject:text];
#pragma clang diagnostic pop
    return YES;
}

- (void)sendReturn {
    UIView *target = AKDictation.gameTextTarget;
    if (!target) return;
    SEL selector = NSSelectorFromString(@"touchSpecialKey:characters:");
    if (![target respondsToSelector:selector]) {
        WKLog("voice", @"dictation: the registered text target (%@) does not take keys; nothing sent",
              NSStringFromClass(target.class));
        return;
    }
    [(id<AKDictationTextTarget>)target touchSpecialKey:AKReturnKeyCode characters:@"\r"];
    WKLog("voice", @"dictation: sent Return");
}

#pragma mark - Telling whoever is watching

- (void)setState:(AKDictationState)state {
    AKDictationState previous = _state;
    _state = state;
    if (previous == state) return;
    WKLog("voice", @"dictation: %@ -> %@", [self nameForState:previous], [self nameForState:state]);
    void (^changed)(BOOL) = _listeningChanged;
    BOOL listening = self.listening;
    BOOL wasListening = previous == AKDictationStateListening || previous == AKDictationStateFinalizing;
    if (changed && listening != wasListening) changed(listening);
    void (^stateHandler)(AKDictationState) = _stateChanged;
    if (stateHandler) stateHandler(state);
    [NSNotificationCenter.defaultCenter postNotificationName:AKDictationStateDidChangeNotification object:self];
}

- (NSString *)nameForState:(AKDictationState)state {
    switch (state) {
    case AKDictationStateIdle: return @"idle";
    case AKDictationStateAuthorizing: return @"authorizing";
    case AKDictationStateListening: return @"listening";
    case AKDictationStateFinalizing: return @"finalizing";
    }
    return @"?";
}

@end
