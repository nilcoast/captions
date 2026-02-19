/**
 * CoreAudio Taps wrapper for Nim interop.
 * Uses ScreenCaptureKit audio taps to capture system audio on macOS 14.2+.
 *
 * Based on:
 * - AudioTee: https://github.com/makeusabrew/audiotee
 * - AudioCap: https://github.com/insidegui/AudioCap
 */

#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

typedef void (*CoreAudioSamplesCallback)(const float* data, int count, void* userdata);

@interface CoreAudioCapture : NSObject
@property (nonatomic, strong) SCStream *stream;
@property (nonatomic, strong) AVAudioConverter *converter;
@property (nonatomic, assign) CoreAudioSamplesCallback callback;
@property (nonatomic, assign) void* userdata;
@property (nonatomic, assign) int targetSampleRate;
@property (nonatomic, assign) int targetChannels;
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation CoreAudioCapture

- (instancetype)init {
    self = [super init];
    if (self) {
        self.isRunning = NO;
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (int)startWithSampleRate:(int)sampleRate
                  channels:(int)channels
                  callback:(CoreAudioSamplesCallback)cb
                  userdata:(void*)ud {
    if (@available(macOS 13.0, *)) {
        self.callback = cb;
        self.userdata = ud;
        self.targetSampleRate = sampleRate;
        self.targetChannels = channels;

        // Get shareable content (system audio)
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSError *contentError = nil;
        __block SCShareableContent *content = nil;

        [SCShareableContent getShareableContentExcludingDesktopWindows:YES
                                                        onScreenWindowsOnly:NO
                                                        completionHandler:^(SCShareableContent *shareableContent, NSError *error) {
            content = shareableContent;
            contentError = error;
            dispatch_semaphore_signal(sem);
        }];

        // Wait for content (5 second timeout)
        if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
            NSLog(@"CoreAudio: Timeout waiting for shareable content");
            return -1;
        }

        if (contentError != nil) {
            NSLog(@"CoreAudio: Failed to get shareable content: %@", contentError.localizedDescription);
            return -1;
        }

        // Configure stream for audio-only capture
        SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
        config.capturesAudio = YES;
        config.sampleRate = sampleRate;
        config.channelCount = channels;

        // Minimum required screen configuration (not capturing video, but required by API)
        config.width = 1;
        config.height = 1;
        config.minimumFrameInterval = CMTimeMake(1, 1);

        // Create content filter for display (audio capture requires a display even if we don't capture video)
        SCDisplay *display = content.displays.firstObject;
        if (display == nil) {
            NSLog(@"CoreAudio: No displays available");
            return -2;
        }

        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display
                                                           excludingWindows:@[]];

        // Create stream
        NSError *streamError = nil;
        self.stream = [[SCStream alloc] initWithFilter:filter
                                         configuration:config
                                              delegate:nil];

        if (streamError != nil) {
            NSLog(@"CoreAudio: Failed to create stream: %@", streamError.localizedDescription);
            return -3;
        }

        // Add audio output handler
        [self.stream addStreamOutput:self
                                type:SCStreamOutputTypeAudio
                  sampleHandlerQueue:dispatch_queue_create("audio.capture.queue", DISPATCH_QUEUE_SERIAL)
                               error:&streamError];

        if (streamError != nil) {
            NSLog(@"CoreAudio: Failed to add audio output: %@", streamError.localizedDescription);
            return -4;
        }

        // Start streaming
        dispatch_semaphore_t startSem = dispatch_semaphore_create(0);
        __block NSError *startError = nil;

        [self.stream startCaptureWithCompletionHandler:^(NSError *error) {
            startError = error;
            dispatch_semaphore_signal(startSem);
        }];

        if (dispatch_semaphore_wait(startSem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
            NSLog(@"CoreAudio: Timeout starting capture");
            return -5;
        }

        if (startError != nil) {
            NSLog(@"CoreAudio: Failed to start capture: %@", startError.localizedDescription);
            return -5;
        }

        self.isRunning = YES;
        NSLog(@"CoreAudio: Started capture at %d Hz, %d channels", sampleRate, channels);
        return 0;
    } else {
        NSLog(@"CoreAudio: Requires macOS 13.0 or later");
        return -6;
    }
}

- (void)stop {
    if (self.isRunning && self.stream != nil) {
        dispatch_semaphore_t stopSem = dispatch_semaphore_create(0);
        [self.stream stopCaptureWithCompletionHandler:^(NSError *error) {
            if (error != nil) {
                NSLog(@"CoreAudio: Error stopping capture: %@", error.localizedDescription);
            }
            dispatch_semaphore_signal(stopSem);
        }];
        dispatch_semaphore_wait(stopSem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        self.stream = nil;
        self.isRunning = NO;
    }
}

// SCStreamOutput protocol - audio callback
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeAudio || !self.isRunning) {
        return;
    }

    // Get audio buffer
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);

    if (asbd == NULL) {
        return;
    }

    // Get audio buffer list
    AudioBufferList audioBufferList;
    CMBlockBufferRef blockBuffer = NULL;
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer,
        NULL,
        &audioBufferList,
        sizeof(audioBufferList),
        NULL,
        NULL,
        kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
        &blockBuffer
    );

    if (blockBuffer == NULL) {
        return;
    }

    // Process each buffer
    for (UInt32 i = 0; i < audioBufferList.mNumberBuffers; i++) {
        AudioBuffer audioBuffer = audioBufferList.mBuffers[i];

        // Convert to float32 if needed
        if (asbd->mFormatFlags & kAudioFormatFlagIsFloat) {
            // Already float - send directly
            const float *samples = (const float *)audioBuffer.mData;
            int frameCount = audioBuffer.mDataByteSize / sizeof(float);

            if (self.callback != NULL) {
                self.callback(samples, frameCount, self.userdata);
            }
        } else {
            // Need to convert to float
            // Create converter if not exists
            if (self.converter == nil) {
                AVAudioFormat *sourceFormat = [[AVAudioFormat alloc] initWithStreamDescription:asbd];
                AVAudioFormat *targetFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:self.targetSampleRate
                                                                                             channels:self.targetChannels];
                self.converter = [[AVAudioConverter alloc] initFromFormat:sourceFormat toFormat:targetFormat];
            }

            // Convert samples
            AVAudioPCMBuffer *sourceBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self.converter.inputFormat
                                                                           frameCapacity:audioBuffer.mDataByteSize / asbd->mBytesPerFrame];
            memcpy(sourceBuffer.audioBufferList->mBuffers[0].mData, audioBuffer.mData, audioBuffer.mDataByteSize);
            sourceBuffer.frameLength = audioBuffer.mDataByteSize / asbd->mBytesPerFrame;

            AVAudioPCMBuffer *targetBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:self.converter.outputFormat
                                                                           frameCapacity:sourceBuffer.frameLength];

            NSError *error = nil;
            [self.converter convertToBuffer:targetBuffer
                                      error:&error
                     withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus * _Nonnull outStatus) {
                *outStatus = AVAudioConverterInputStatus_HaveData;
                return sourceBuffer;
            }];

            if (error == nil && targetBuffer.frameLength > 0) {
                const float *samples = targetBuffer.floatChannelData[0];
                if (self.callback != NULL) {
                    self.callback(samples, (int)targetBuffer.frameLength, self.userdata);
                }
            }
        }
    }

    CFRelease(blockBuffer);
}

@end

// C API for Nim interop

void* ca_capture_new(void) {
    CoreAudioCapture *capture = [[CoreAudioCapture alloc] init];
    return (__bridge_retained void*)capture;
}

void ca_capture_free(void* cap) {
    if (cap == NULL) return;
    CoreAudioCapture *capture = (__bridge_transfer CoreAudioCapture*)cap;
    [capture stop];
}

int ca_capture_start(void* cap, int sample_rate, int channels,
                     CoreAudioSamplesCallback callback, void* userdata) {
    if (cap == NULL) return -1;
    CoreAudioCapture *capture = (__bridge CoreAudioCapture*)cap;
    return [capture startWithSampleRate:sample_rate
                               channels:channels
                               callback:callback
                               userdata:userdata];
}

void ca_capture_stop(void* cap) {
    if (cap == NULL) return;
    CoreAudioCapture *capture = (__bridge CoreAudioCapture*)cap;
    [capture stop];
}
