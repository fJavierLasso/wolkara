// Desktop output-device selection must work on RemoteIO in an ordinary launch,
// without --trace-audio-render. Run with tools/test_translation_sim.sh.
#import <AudioToolbox/AudioToolbox.h>
#import <AVFAudio/AVFAudio.h>
#include <assert.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <unistd.h>
#import "AKAudioPlayback.h"
static atomic_uint rendered;
static OSStatus render(void *context, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *buffers) {
    (void)context; (void)flags; (void)time; (void)bus; (void)frames;
    for(UInt32 b=0;buffers && b<buffers->mNumberBuffers;b++) if(buffers->mBuffers[b].mData) memset(buffers->mBuffers[b].mData,0,buffers->mBuffers[b].mDataByteSize);
    atomic_fetch_add(&rendered,1); return noErr;
}
static void waitForFrames(void) {
    unsigned before=atomic_load(&rendered);
    for(int i=0;i<100 && atomic_load(&rendered)==before;i++) usleep(10000);
    assert(atomic_load(&rendered)>before);
}
static BOOL running(AudioUnit unit) { UInt32 value=0,size=sizeof value; assert(!AudioUnitGetProperty(unit,kAudioOutputUnitProperty_IsRunning,kAudioUnitScope_Global,0,&value,&size)); return value!=0; }

BOOL TKWolkaraForeverRequestGamePlayback(void) {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    return [session setCategory:AVAudioSessionCategoryPlayback error:nil] &&
           [session setActive:YES error:nil];
}

int main(void) { @autoreleasepool {
    assert(![NSProcessInfo.processInfo.arguments containsObject:@"--trace-audio-render"]);
    AudioComponentDescription description = {kAudioUnitType_Output, 'ahal', kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    assert(component);
    AudioUnit unit = NULL;
    assert(!AudioComponentInstanceNew(component, &unit) && unit);

    // Select the same real default device the guest gets from CoreAudio.
    void *library = dlopen("/System/Library/Frameworks/CoreAudio.framework/CoreAudio", RTLD_NOW | RTLD_LOCAL);
    OSStatus (*get)(UInt32, UInt32 *, void *) = library ? dlsym(library, "AudioHardwareGetProperty") : NULL;
    assert(get);
    UInt32 device = 0, size = sizeof device;
    assert(!get('dOut', &size, &device) && device);
    const AudioUnitPropertyID currentDevice = 2000; // macOS kAudioOutputUnitProperty_CurrentDevice
    assert(!AudioUnitSetProperty(unit, currentDevice, kAudioUnitScope_Global, 0, &device, sizeof device));
    UInt32 selected = 0;
    size = sizeof selected;
    assert(!AudioUnitGetProperty(unit, currentDevice, kAudioUnitScope_Global, 0, &selected, &size));
    assert(selected == device && size == sizeof selected);

    // The compatibility path still rejects arbitrary devices and short buffers.
    UInt32 invalid = device ^ 0x80000000u;
    assert(AudioUnitSetProperty(unit, currentDevice, kAudioUnitScope_Global, 0, &invalid, sizeof invalid) == kAudioUnitErr_InvalidPropertyValue);
    assert(AudioUnitSetProperty(unit, currentDevice, kAudioUnitScope_Global, 0, NULL, sizeof device) == kAudioUnitErr_InvalidPropertyValue);
    size = sizeof selected - 1;
    assert(AudioUnitGetProperty(unit, currentDevice, kAudioUnitScope_Global, 0, &selected, &size) == kAudioUnitErr_InvalidPropertyValue);

    AudioStreamBasicDescription format = {0};
    size = sizeof format;
    assert(!AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, &size));
    assert(format.mSampleRate > 0 && format.mChannelsPerFrame > 0);
    assert(!AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof format));
    AURenderCallbackStruct callback={render,NULL};
    assert(!AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&callback,sizeof callback));
    assert(!AudioUnitInitialize(unit));
    assert(!AudioOutputUnitStart(unit)); waitForFrames();
    void *toolbox=dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",RTLD_NOW|RTLD_LOCAL);
    OSStatus (*systemStop)(AudioUnit)=dlsym(toolbox,"AudioOutputUnitStop"); assert(systemStop);
    assert(!systemStop(unit)); assert(!running(unit));
    // A system stop has not revoked the application's request to play.
    [NSNotificationCenter.defaultCenter postNotificationName:AKGameAudioRecovered object:nil];
    assert(running(unit)); waitForFrames();
    assert(!AudioOutputUnitStop(unit));
    [NSNotificationCenter.defaultCenter postNotificationName:AKGameAudioRecovered object:nil];
    assert(!running(unit));
    assert(!AudioOutputUnitStart(unit)); waitForFrames();
    assert(!systemStop(unit));
    assert(!AudioUnitUninitialize(unit)); assert(!AudioUnitInitialize(unit));
    [NSNotificationCenter.defaultCenter postNotificationName:AKGameAudioRecovered object:nil];
    assert(!running(unit));
    assert(!AudioUnitUninitialize(unit));
    assert(!AudioComponentInstanceDispose(unit));
    [NSNotificationCenter.defaultCenter postNotificationName:AKGameAudioRecovered object:nil];
    puts("audio output: desktop device selection, render recovery and stopped/disposed units without tracing: PASS");
} }
