#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <math.h>
#include <string.h>

// Only packed native-endian float PCM is scaled. Unrecognized formats pass
// through unchanged; the adapter never guesses how an application's samples
// are encoded. RemoteIO's normal client format is float32 (interleaved or not).
static inline BOOL AKCanScaleOutput(AudioStreamBasicDescription f) {
    UInt32 channels = (f.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : f.mChannelsPerFrame;
    return f.mFormatID == kAudioFormatLinearPCM &&
        (f.mFormatFlags & (kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked)) ==
            (kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked) &&
        !(f.mFormatFlags & (kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsAlignedHigh)) &&
        f.mBitsPerChannel == 32 && channels && channels <= UINT32_MAX / sizeof(float) &&
        f.mBytesPerFrame == channels * sizeof(float) && isfinite(f.mSampleRate) && f.mSampleRate > 0;
}

// Allocation/lock-free, with an 80 ms gain ramp shared by all channels. Bounds
// are checked before touching a buffer, including frame/channel overflow. The
// buffers are the documented render callback output, not inspected game memory.
static inline float AKScaleOutput(AudioBufferList *buffers, UInt32 frames,
                                  float current, float target, float step) {
    if (!buffers || !frames || (current == 1 && target == 1)) return current;
    float direction = target >= current ? 1 : -1;
    for (UInt32 b = 0; b < buffers->mNumberBuffers; ++b) {
        AudioBuffer *buffer = &buffers->mBuffers[b];
        UInt32 channels = buffer->mNumberChannels;
        uint64_t bytes = (uint64_t)frames * channels * sizeof(float);
        if (!buffer->mData || !channels || bytes > buffer->mDataByteSize) continue;
        uint8_t *samples = buffer->mData;
        for (UInt32 frame = 0; frame < frames; ++frame) {
            float gain = current + direction * fminf(fabsf(target - current), step * (frame + 1.0f));
            for (UInt32 channel = 0; channel < channels; ++channel) {
                size_t offset = ((size_t)frame * channels + channel) * sizeof(float);
                float sample;
                memcpy(&sample, samples + offset, sizeof sample);
                sample *= gain;
                memcpy(samples + offset, &sample, sizeof sample);
            }
        }
    }
    return current + direction * fminf(fabsf(target - current), step * frames);
}
