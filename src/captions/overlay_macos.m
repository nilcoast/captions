// Objective-C helpers for NSWindow and NSTextView management
// This file provides a clean C-compatible API for Nim to call

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

// Opaque handle types for Nim
typedef void* CaptionWindowHandle;
typedef void* TextViewHandle;

// Create a borderless, transparent, always-on-top overlay window
CaptionWindowHandle createCaptionWindow(CGFloat width, CGFloat height, CGFloat x, CGFloat y) {
    NSRect contentRect = NSMakeRect(x, y, width, height);

    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                    styleMask:NSWindowStyleMaskBorderless
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];

    // Transparent background
    [window setBackgroundColor:[NSColor clearColor]];
    [window setOpaque:NO];
    [window setHasShadow:NO];

    // Always on top
    [window setLevel:NSFloatingWindowLevel];

    // Behavior settings
    NSWindowCollectionBehavior behavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces |  // Visible on all spaces
        NSWindowCollectionBehaviorStationary |         // Doesn't switch spaces
        NSWindowCollectionBehaviorIgnoresCycle;        // Not in window cycle
    [window setCollectionBehavior:behavior];

    // Click-through
    [window setIgnoresMouseEvents:YES];

    // Enable layer for rounded corners
    [[window contentView] setWantsLayer:YES];

    return (__bridge_retained CaptionWindowHandle)window;
}

// Create a text view for displaying captions with a background box
TextViewHandle createTextView(CGFloat width, CGFloat height,
                               const char *fontName, CGFloat fontSize,
                               CGFloat textR, CGFloat textG, CGFloat textB, CGFloat textA,
                               CGFloat bgR, CGFloat bgG, CGFloat bgB, CGFloat bgA,
                               CGFloat cornerRadius, CGFloat padding) {
    NSRect frame = NSMakeRect(0, 0, width, height);
    NSTextView *textView = [[NSTextView alloc] initWithFrame:frame];

    // Text settings
    [textView setEditable:NO];
    [textView setSelectable:NO];
    [textView setAlignment:NSTextAlignmentCenter];
    [textView setTextColor:[NSColor colorWithRed:textR green:textG blue:textB alpha:textA]];

    // Font
    NSFont *font;
    if (fontName && strlen(fontName) > 0) {
        NSString *fontNameStr = [NSString stringWithUTF8String:fontName];
        font = [NSFont fontWithName:fontNameStr size:fontSize];
    }
    if (!font) {
        // Fallback to system font
        font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightBold];
    }
    [textView setFont:font];

    // Background box
    [textView setDrawsBackground:YES];
    [textView setBackgroundColor:[NSColor colorWithRed:bgR green:bgG blue:bgB alpha:bgA]];

    // Enable layer for rounded corners and padding
    [textView setWantsLayer:YES];
    textView.layer.cornerRadius = cornerRadius;
    textView.layer.masksToBounds = YES;

    // Text insets (padding)
    [textView setTextContainerInset:NSMakeSize(padding * 2, padding)];

    return (__bridge_retained TextViewHandle)textView;
}

// Show the window
void showWindow(CaptionWindowHandle handle) {
    NSWindow *window = (__bridge NSWindow *)handle;
    [window makeKeyAndOrderFront:nil];
}

// Hide the window
void hideWindow(CaptionWindowHandle handle) {
    NSWindow *window = (__bridge NSWindow *)handle;
    [window orderOut:nil];
}

// Set window position (bottom-center relative to screen)
void setWindowPosition(CaptionWindowHandle handle, CGFloat marginBottom) {
    NSWindow *window = (__bridge NSWindow *)handle;
    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenFrame = [screen visibleFrame];
    NSRect windowFrame = [window frame];

    CGFloat x = screenFrame.origin.x + (screenFrame.size.width - windowFrame.size.width) / 2.0;
    CGFloat y = screenFrame.origin.y + marginBottom;

    [window setFrameOrigin:NSMakePoint(x, y)];
}

// Add text view to window
void addTextViewToWindow(CaptionWindowHandle windowHandle, TextViewHandle textViewHandle,
                         CGFloat marginSide, CGFloat marginBottom) {
    NSWindow *window = (__bridge NSWindow *)windowHandle;
    NSTextView *textView = (__bridge NSTextView *)textViewHandle;
    NSView *contentView = [window contentView];

    // Calculate frame with margins
    NSRect contentFrame = [contentView bounds];
    CGFloat width = contentFrame.size.width - (marginSide * 2);
    CGFloat height = contentFrame.size.height - marginBottom;
    CGFloat x = marginSide;
    CGFloat y = marginBottom;

    [textView setFrame:NSMakeRect(x, y, width, height)];
    [textView setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];

    [contentView addSubview:textView];
}

// Update text in text view
void updateTextViewText(TextViewHandle handle, const char *text) {
    NSTextView *textView = (__bridge NSTextView *)handle;
    NSString *nsText = [NSString stringWithUTF8String:text];

    // Preserve formatting attributes
    NSFont *currentFont = [textView font];
    NSColor *currentColor = [textView textColor];

    [textView setString:nsText];

    // Reapply formatting to all text
    NSRange fullRange = NSMakeRange(0, [[textView string] length]);
    [textView setFont:currentFont range:fullRange];
    [textView setTextColor:currentColor range:fullRange];
}

// Release window handle
void releaseWindow(CaptionWindowHandle handle) {
    if (handle) {
        NSWindow *window = (__bridge_transfer NSWindow *)handle;
        [window close];
        window = nil;
    }
}

// Release text view handle
void releaseTextView(TextViewHandle handle) {
    if (handle) {
        NSTextView *textView = (__bridge_transfer NSTextView *)handle;
        [textView removeFromSuperview];
        textView = nil;
    }
}

// Run the NSApplication main loop (blocking)
void runNSApp(void) {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];  // No dock icon
    [app run];
}

// Stop the NSApplication
void stopNSApp(void) {
    NSApplication *app = [NSApplication sharedApplication];
    [app stop:nil];

    // Post a dummy event to wake up the run loop
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                         location:NSMakePoint(0, 0)
                                    modifierFlags:0
                                        timestamp:0
                                     windowNumber:0
                                          context:nil
                                          subtype:0
                                            data1:0
                                            data2:0];
    [app postEvent:event atStart:YES];
}

// Initialize NSApplication (must be called before creating windows)
void initNSApp(void) {
    [NSApplication sharedApplication];
}
