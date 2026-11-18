#import <AudioToolbox/AudioToolbox.h>
#import <AVFAudio/AVFAudio.h>
#import "AKSupport.h"
#import "AKAudioPlayback.h"
#import "OutputGain.h"
#include <dlfcn.h>
#include <stdatomic.h>
static BOOL renderProbeEnabled(void) {
    static BOOL enabled; static dispatch_once_t once;
    dispatch_once(&once, ^{ enabled=[NSProcessInfo.processInfo.arguments containsObject:@"--trace-audio-render"]; });
    return enabled;
}
@interface AKAudioRenderProbe : NSObject {
@public
    AURenderCallbackStruct original;
    atomic_bool scale;
    _Atomic(float) step;
    float gain;
    BOOL trace;
    atomic_uint_fast64_t calls, frames, nonzeroBuffers, errors, silent;
}
@end
@implementation AKAudioRenderProbe @end
static NSMutableDictionary<NSValue *,NSMutableArray<AKAudioRenderProbe *> *> *renderProbes;
static NSMutableSet<NSValue *> *runningOutputs;
static _Atomic(float) outputGain = 1.0f;
static void *native(const char *name);

static void recoverOutputs(void) {
    OSStatus (*start)(AudioUnit) = native("AudioOutputUnitStart");
    if (!start) return;
    // Start/stop/uninitialize/dispose share this lock. A recovery cannot revive a
    // stopped unit or use a unit after disposal. The render callback takes no lock.
    @synchronized(runningOutputs) {
        for (NSValue *key in runningOutputs) {
            OSStatus status = start(key.pointerValue);
            AKLogC("audio resume output status=%d", (int)status);
        }
    }
}
static void prepareOutputs(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        renderProbes = [NSMutableDictionary new];
        runningOutputs = [NSMutableSet new];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:AKGameAudioRecovered object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) { (void)note; recoverOutputs(); }];
        [center addObserverForName:AKGameAudioGainChanged object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *note) {
                NSNumber *value = note.userInfo[@"gain"];
                if ([value isKindOfClass:NSNumber.class] && isfinite(value.floatValue))
                    atomic_store_explicit(&outputGain, fmaxf(0, fminf(1, value.floatValue)), memory_order_relaxed);
            }];
    });
}
static void updateRenderFormat(AudioUnit unit, AudioStreamBasicDescription format) {
    @synchronized(renderProbes) {
        for (AKAudioRenderProbe *probe in renderProbes[[NSValue valueWithPointer:unit]]) {
            atomic_store(&probe->step, AKCanScaleOutput(format) ? 1.0f / (float)(format.mSampleRate * 0.08) : 0);
            atomic_store(&probe->scale, AKCanScaleOutput(format));
        }
    }
}
static void prepareProbes(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        prepareOutputs();
        static dispatch_source_t timer;
        timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
        dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),5*NSEC_PER_SEC,NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer,^{
            NSMutableArray *groups=[NSMutableArray new];
            @synchronized(renderProbes) { for(NSArray *group in renderProbes.allValues)[groups addObject:[group copy]]; }
            for(NSArray *group in groups)for(AKAudioRenderProbe *probe in group) {
                AKLogC("audio render calls=%llu frames=%llu nonzero_buffers=%llu errors=%llu silence_flags=%llu",(unsigned long long)atomic_load(&probe->calls),(unsigned long long)atomic_load(&probe->frames),(unsigned long long)atomic_load(&probe->nonzeroBuffers),(unsigned long long)atomic_load(&probe->errors),(unsigned long long)atomic_load(&probe->silent));
            }
        });dispatch_resume(timer);
    });
}
static OSStatus observeRender(void *context,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *time,UInt32 bus,UInt32 frames,AudioBufferList *buffers) {
    AKAudioRenderProbe *probe=(__bridge AKAudioRenderProbe *)context;
    OSStatus status=probe->original.inputProc(probe->original.inputProcRefCon,flags,time,bus,frames,buffers);
    if (!status && atomic_load_explicit(&probe->scale, memory_order_relaxed)) {
        probe->gain = AKScaleOutput(buffers, frames, probe->gain,
            atomic_load_explicit(&outputGain, memory_order_relaxed),
            atomic_load_explicit(&probe->step, memory_order_relaxed));
    }
    if (!probe->trace) return status;
    atomic_fetch_add_explicit(&probe->calls,1,memory_order_relaxed);
    atomic_fetch_add_explicit(&probe->frames,frames,memory_order_relaxed);
    if(status)atomic_fetch_add_explicit(&probe->errors,1,memory_order_relaxed);
    if(flags && (*flags&kAudioUnitRenderAction_OutputIsSilence))atomic_fetch_add_explicit(&probe->silent,1,memory_order_relaxed);
    if(!status && buffers)for(UInt32 b=0;b<buffers->mNumberBuffers;b++) {
        const uint8_t *bytes=buffers->mBuffers[b].mData;UInt32 size=buffers->mBuffers[b].mDataByteSize;
        if(bytes)for(UInt32 i=0;i<size;i++)if(bytes[i]) { atomic_fetch_add_explicit(&probe->nonzeroBuffers,1,memory_order_relaxed);break; }
    }
    return status;
}
static void *native(const char *name) {
    static void *library; static dispatch_once_t once;
    dispatch_once(&once,^{library=dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",RTLD_NOW|RTLD_LOCAL);});
    return library?dlsym(library,name):NULL;
}
static BOOL remoteOutput(AudioUnit unit) {
    AudioComponentDescription description={0};
    AudioComponent component=AudioComponentInstanceGetComponent(unit);
    return component && !AudioComponentGetDescription(component,&description) && description.componentType==kAudioUnitType_Output && description.componentSubType==kAudioUnitSubType_RemoteIO;
}
static OSStatus defaultOutput(UInt32 *device) {
    static OSStatus (*get)(UInt32,UInt32 *,void *);static dispatch_once_t once;
    dispatch_once(&once,^{void *library=dlopen("/System/Library/Frameworks/CoreAudio.framework/CoreAudio",RTLD_NOW|RTLD_LOCAL);get=library?dlsym(library,"AudioHardwareGetProperty"):NULL;});
    if(!get || !AVAudioSession.sharedInstance.currentRoute.outputs.count)return kAudioUnitErr_InvalidPropertyValue;
    UInt32 size=sizeof *device;return get('dOut',&size,device);
}
AudioComponent AudioComponentFindNext(AudioComponent previous,const AudioComponentDescription *description) {
    AudioComponent (*f)(AudioComponent,const AudioComponentDescription *)=native(__func__);
    if(!f || !description)return NULL;
    prepareOutputs();
    AudioComponentDescription mapped=*description;
    if(mapped.componentType==kAudioUnitType_Output && (mapped.componentSubType=='ahal' || mapped.componentSubType=='def ')) {
        mapped.componentSubType=kAudioUnitSubType_RemoteIO;
        // The host owns the audio session, so this asks it for the game's playback lease and does
        // nothing else with the session. Taking Playback here is what pulled the session out from
        // under a dictation that was already recording: Playback is an output-only category, so the
        // input went to digital silence while the engine kept running and reported itself healthy.
        // This is the same request the CoreAudio adapter makes, found by dlsym because this adapter
        // is its own image and cannot link against the app's symbol.
        typedef BOOL (*TKWolkaraForeverPlaybackRequest)(void);
        static TKWolkaraForeverPlaybackRequest ask; static dispatch_once_t once;
        dispatch_once(&once,^{ ask=(TKWolkaraForeverPlaybackRequest)dlsym(RTLD_DEFAULT,"TKWolkaraForeverRequestGamePlayback"); });
        BOOL active=ask?ask():NO;
        AKLog(@"audio playback session active=%d",active);
    }
    AudioComponent component=f(previous,&mapped);
    AKLogC("audio component type=%#x subtype=%#x mapped=%#x found=%d",(unsigned)description->componentType,(unsigned)description->componentSubType,(unsigned)mapped.componentSubType,component!=NULL);
    return component;
}
OSStatus AudioComponentInstanceNew(AudioComponent component,AudioComponentInstance *instance) {
    OSStatus (*f)(AudioComponent,AudioComponentInstance *)=native(__func__);OSStatus s=f?f(component,instance):-4;
    AKLogC("audio instance new status=%d",(int)s);return s;
}
OSStatus AudioUnitSetProperty(AudioUnit unit,AudioUnitPropertyID property,AudioUnitScope scope,AudioUnitElement element,const void *data,UInt32 size) {
    OSStatus (*f)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,const void *,UInt32)=native(__func__);
    OSStatus s;
    // Desktop HAL chooses a device explicitly. RemoteIO uses the session's
    // route. Accept only that actual default device, never an arbitrary ID.
    // Device compatibility is required in ordinary launches too; only render
    // buffer observation below is controlled by --trace-audio-render.
    if(property==2000 && scope==kAudioUnitScope_Global && element==0 && remoteOutput(unit)) {
        UInt32 requested=0,current=0;
        if(!data || size!=sizeof requested)s=kAudioUnitErr_InvalidPropertyValue;
        else { memcpy(&requested,data,sizeof requested);s=defaultOutput(&current);if(!s && requested!=current)s=kAudioUnitErr_InvalidPropertyValue; }
    } else if(property==kAudioUnitProperty_SetRenderCallback && scope==kAudioUnitScope_Input && element==0 && data && size==sizeof(AURenderCallbackStruct) && remoteOutput(unit)) {
        prepareOutputs();
        if (renderProbeEnabled()) prepareProbes();
        AKAudioRenderProbe *probe=[AKAudioRenderProbe new];memcpy(&probe->original,data,size);
        probe->gain = atomic_load(&outputGain); probe->trace = renderProbeEnabled();
        AudioStreamBasicDescription format = {0}; UInt32 formatSize = sizeof format;
        OSStatus (*get)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,void *,UInt32 *) = native("AudioUnitGetProperty");
        if (get && !get(unit,kAudioUnitProperty_StreamFormat,kAudioUnitScope_Input,0,&format,&formatSize) && AKCanScaleOutput(format)) {
            atomic_store(&probe->scale, true);
            atomic_store(&probe->step, 1.0f / (float)(format.mSampleRate * 0.08));
        }
        if(probe->original.inputProc) {
            AURenderCallbackStruct observed={observeRender,(__bridge void *)probe};
            @synchronized(renderProbes) {
                NSValue *key=[NSValue valueWithPointer:unit];
                if(!renderProbes[key])renderProbes[key]=[NSMutableArray new];
                [renderProbes[key] addObject:probe];
            }
            s=f?f(unit,property,scope,element,&observed,sizeof observed):-4;
        } else s=f?f(unit,property,scope,element,data,size):-4;
    } else s=f?f(unit,property,scope,element,data,size):-4;
    if(property==kAudioUnitProperty_StreamFormat && data && size==sizeof(AudioStreamBasicDescription)) {
        AudioStreamBasicDescription format;memcpy(&format,data,sizeof format);
        if (!s && scope==kAudioUnitScope_Input && element==0) updateRenderFormat(unit, format);
        AKLogC("audio stream rate=%.0f format=%#x flags=%#x channels=%u bytes_per_frame=%u bits=%u",format.mSampleRate,(unsigned)format.mFormatID,(unsigned)format.mFormatFlags,(unsigned)format.mChannelsPerFrame,(unsigned)format.mBytesPerFrame,(unsigned)format.mBitsPerChannel);
    }
    AKLogC("audio set property=%u scope=%u element=%u size=%u status=%d",(unsigned)property,(unsigned)scope,(unsigned)element,(unsigned)size,(int)s);return s;
}
OSStatus AudioUnitGetProperty(AudioUnit unit,AudioUnitPropertyID property,AudioUnitScope scope,AudioUnitElement element,void *data,UInt32 *size) {
    OSStatus (*f)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,void *,UInt32 *)=native(__func__);
    OSStatus s;
    if(property==2000 && scope==kAudioUnitScope_Global && element==0 && remoteOutput(unit)) {
        UInt32 current=0;
        if(!data || !size || *size<sizeof current)s=kAudioUnitErr_InvalidPropertyValue;
        else { s=defaultOutput(&current);if(!s) { memcpy(data,&current,sizeof current);*size=sizeof current; } }
    } else s=f?f(unit,property,scope,element,data,size):-4;
    if(!s && property==kAudioUnitProperty_StreamFormat && data && size && *size==sizeof(AudioStreamBasicDescription) && remoteOutput(unit)) {
        AudioStreamBasicDescription format;memcpy(&format,data,sizeof format);
        // RemoteIO exposes an unspecified rate before initialization. A desktop
        // HAL client expects the selected hardware device's concrete format.
        if(format.mSampleRate==0 && AVAudioSession.sharedInstance.sampleRate>0) {
            format.mSampleRate=AVAudioSession.sharedInstance.sampleRate;memcpy(data,&format,sizeof format);
        }
        AKLogC("audio queried stream rate=%.0f channels=%u",format.mSampleRate,(unsigned)format.mChannelsPerFrame);
    }
    AKLogC("audio get property=%u scope=%u element=%u status=%d",(unsigned)property,(unsigned)scope,(unsigned)element,(int)s);return s;
}
OSStatus AudioUnitInitialize(AudioUnit unit) {
    OSStatus (*f)(AudioUnit)=native(__func__);OSStatus s=f?f(unit):-4;AKLogC("audio initialize status=%d",(int)s);return s;
}
OSStatus AudioOutputUnitStart(AudioUnit unit) {
    prepareOutputs();
    OSStatus (*f)(AudioUnit)=native(__func__); OSStatus s;
    @synchronized(runningOutputs) {
        s=f?f(unit):-4;
        if (!s && remoteOutput(unit)) [runningOutputs addObject:[NSValue valueWithPointer:unit]];
    }
    AKLogC("audio start status=%d",(int)s);
    AVAudioSession *session=AVAudioSession.sharedInstance;
    AKLog(@"audio route types=%@ volume=%.2f sample_rate=%.0f channels=%lu",[session.currentRoute.outputs valueForKey:@"portType"],session.outputVolume,session.sampleRate,(unsigned long)session.outputNumberOfChannels);
    return s;
}
OSStatus AudioOutputUnitStop(AudioUnit unit) {
    prepareOutputs();
    OSStatus (*f)(AudioUnit)=native(__func__);
    @synchronized(runningOutputs) {
        [runningOutputs removeObject:[NSValue valueWithPointer:unit]];
        return f?f(unit):-4;
    }
}
OSStatus AudioUnitUninitialize(AudioUnit unit) {
    prepareOutputs();
    OSStatus (*f)(AudioUnit)=native(__func__);
    @synchronized(runningOutputs) {
        [runningOutputs removeObject:[NSValue valueWithPointer:unit]];
        return f?f(unit):-4;
    }
}
OSStatus AudioComponentInstanceDispose(AudioComponentInstance instance) {
    prepareOutputs();
    OSStatus (*f)(AudioComponentInstance)=native(__func__); OSStatus s;
    @synchronized(runningOutputs) {
        [runningOutputs removeObject:[NSValue valueWithPointer:instance]];
        s=f?f(instance):-4;
    }
    if(!s) @synchronized(renderProbes) { [renderProbes removeObjectForKey:[NSValue valueWithPointer:instance]]; }
    return s;
}
