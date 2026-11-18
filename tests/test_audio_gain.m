#import "OutputGain.h"
#include <assert.h>
int main(void) {
    AudioStreamBasicDescription format={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};
    assert(AKCanScaleOutput(format));
    format.mFormatFlags|=kAudioFormatFlagIsBigEndian; assert(!AKCanScaleOutput(format));
    format.mFormatFlags&=~kAudioFormatFlagIsBigEndian;
    float samples[]={1,-1,1,-1,1,-1,1,-1,123};
    AudioBufferList buffers={1,{{2,8*sizeof(float),samples}}};
    float gain=AKScaleOutput(&buffers,4,1,0.35,0.25);
    assert(fabsf(gain-0.35f)<0.00001 && samples[0]==0.75 && samples[1]==-0.75);
    assert(fabsf(samples[6]-0.35f)<0.00001 && samples[8]==123);
    float unchanged[9]; memcpy(unchanged,samples,sizeof samples);
    AKScaleOutput(&buffers,UINT32_MAX,1,0.35,0.1); assert(!memcmp(unchanged,samples,sizeof samples));
    buffers.mBuffers[0].mDataByteSize=1;
    AKScaleOutput(&buffers,4,1,0.35,0.1); assert(!memcmp(unchanged,samples,sizeof samples));
    struct { UInt32 count; AudioBuffer buffers[2]; } planar={2,{{1,4*sizeof(float),samples},{1,4*sizeof(float),samples+4}}};
    for(int i=0;i<8;i++)samples[i]=1;
    gain=AKScaleOutput((AudioBufferList *)&planar,4,0.35,1,0.25);
    assert(gain==1 && samples[0]==samples[4] && samples[3]==1 && samples[7]==1 && samples[8]==123);
    assert(AKScaleOutput(NULL,4,1,0.35,0.1)==1);
    puts("audio gain: float PCM, stereo/planar ramp, restore and malformed buffer bounds: PASS");
}
