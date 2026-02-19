/**
 * Standalone ScreenCaptureKit test — isolates the SCK flow from Nim entirely.
 * If this crashes, the problem is permissions/macOS config.
 * If this works, the problem is in the Nim↔ObjC boundary.
 *
 * Build:
 *   clang -fobjc-arc -framework Foundation -framework ScreenCaptureKit \
 *         -framework CoreMedia -framework AVFAudio -o test_sck tests/test_sck.m
 *
 * Run:
 *   ./test_sck
 */

#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

@interface TestCapture : NSObject <SCStreamOutput>
@property (nonatomic, strong) SCStream *stream;
@property (nonatomic, assign) int sampleCount;
@end

@implementation TestCapture

- (void)stream:(SCStream *)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
               ofType:(SCStreamOutputType)type {
    if (type == SCStreamOutputTypeAudio) {
        self.sampleCount++;
        if (self.sampleCount % 50 == 1) {
            NSLog(@"[test_sck] Got audio sample buffer #%d", self.sampleCount);
        }
    }
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSLog(@"[test_sck] Starting ScreenCaptureKit test...");

        // Step 1: Get shareable content
        NSLog(@"[test_sck] Requesting shareable content...");
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block SCShareableContent *content = nil;
        __block NSError *contentError = nil;

        [SCShareableContent getShareableContentExcludingDesktopWindows:YES
                                                    onScreenWindowsOnly:NO
                                                    completionHandler:^(SCShareableContent *sc, NSError *err) {
            content = sc;
            contentError = err;
            dispatch_semaphore_signal(sem);
        }];

        if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
            NSLog(@"[test_sck] FAIL: Timeout waiting for shareable content");
            return 1;
        }

        if (contentError != nil) {
            NSLog(@"[test_sck] FAIL: %@", contentError.localizedDescription);
            return 1;
        }

        NSLog(@"[test_sck] Got %lu displays, %lu windows",
              (unsigned long)content.displays.count,
              (unsigned long)content.windows.count);

        // Step 2: Get first display
        SCDisplay *display = content.displays.firstObject;
        if (display == nil) {
            NSLog(@"[test_sck] FAIL: No displays found");
            return 1;
        }
        NSLog(@"[test_sck] Using display: %u (%lux%lu)",
              display.displayID,
              (unsigned long)display.width,
              (unsigned long)display.height);

        // Step 3: Configure stream
        SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
        config.capturesAudio = YES;
        config.sampleRate = 16000;
        config.channelCount = 1;
        if (@available(macOS 14.0, *)) {
            config.excludesCurrentProcessAudio = YES;
        }

        // Minimum video config — pixelFormat is required on macOS 15+ or startCapture fails
        config.width = 2;
        config.height = 2;
        config.minimumFrameInterval = CMTimeMake(1, 1);
        config.pixelFormat = 'BGRA';  // kCVPixelFormatType_32BGRA
        if (@available(macOS 14.0, *)) {
            config.excludesCurrentProcessAudio = YES;
        }
        NSLog(@"[test_sck] Stream configured (16kHz mono, 2x2 video)");

        // Step 4: Create filter and stream
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display
                                                          excludingWindows:@[]];

        SCStream *stream = [[SCStream alloc] initWithFilter:filter
                                              configuration:config
                                                   delegate:nil];
        if (stream == nil) {
            NSLog(@"[test_sck] FAIL: SCStream alloc returned nil");
            return 1;
        }
        NSLog(@"[test_sck] SCStream created");

        // Step 5: Add output handler
        TestCapture *handler = [[TestCapture alloc] init];
        handler.stream = stream;

        NSError *addError = nil;
        [stream addStreamOutput:handler
                           type:SCStreamOutputTypeAudio
             sampleHandlerQueue:dispatch_queue_create("test.audio.queue", DISPATCH_QUEUE_SERIAL)
                          error:&addError];
        if (addError != nil) {
            NSLog(@"[test_sck] FAIL: addStreamOutput: %@", addError.localizedDescription);
            return 1;
        }
        NSLog(@"[test_sck] Stream output handler added");

        // Step 6: Start capture
        NSLog(@"[test_sck] Starting capture...");
        dispatch_semaphore_t startSem = dispatch_semaphore_create(0);
        __block NSError *startError = nil;

        [stream startCaptureWithCompletionHandler:^(NSError *error) {
            startError = error;
            dispatch_semaphore_signal(startSem);
        }];

        if (dispatch_semaphore_wait(startSem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) {
            NSLog(@"[test_sck] FAIL: Timeout starting capture");
            return 1;
        }

        if (startError != nil) {
            NSLog(@"[test_sck] FAIL: startCapture: %@", startError.localizedDescription);
            NSLog(@"[test_sck]   domain=%@ code=%ld", startError.domain, (long)startError.code);
            NSLog(@"[test_sck]   userInfo=%@", startError.userInfo);
            return 1;
        }
        NSLog(@"[test_sck] Capture started! Listening for 2 seconds...");

        // Step 7: Wait 2 seconds
        [NSThread sleepForTimeInterval:2.0];

        NSLog(@"[test_sck] Received %d audio sample buffers", handler.sampleCount);

        // Step 8: Stop capture
        NSLog(@"[test_sck] Stopping capture...");
        dispatch_semaphore_t stopSem = dispatch_semaphore_create(0);
        [stream stopCaptureWithCompletionHandler:^(NSError *error) {
            if (error != nil) {
                NSLog(@"[test_sck] Warning: stop error: %@", error.localizedDescription);
            }
            dispatch_semaphore_signal(stopSem);
        }];
        dispatch_semaphore_wait(stopSem, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));

        NSLog(@"[test_sck] PASS: Test completed successfully (got %d buffers)", handler.sampleCount);
        return 0;
    }
}
