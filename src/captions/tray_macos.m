// System tray (NSStatusBar) implementation for macOS.
// Provides a C API for Nim to create and manage a menu bar status item.

#import <Cocoa/Cocoa.h>

typedef void (*TrayCallback)(void *userData);

@interface CaptionsTrayDelegate : NSObject
@property (nonatomic) TrayCallback toggleCallback;
@property (nonatomic) TrayCallback quitCallback;
@property (nonatomic) TrayCallback prefsCallback;
@property (nonatomic) void *userData;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenuItem *statusMenuItem;
@property (nonatomic, strong) NSMenuItem *toggleMenuItem;
@end

@implementation CaptionsTrayDelegate

- (void)toggleAction:(id)sender {
    if (self.toggleCallback) {
        self.toggleCallback(self.userData);
    }
}

- (void)prefsAction:(id)sender {
    if (self.prefsCallback) {
        self.prefsCallback(self.userData);
    }
}

- (void)quitAction:(id)sender {
    if (self.quitCallback) {
        self.quitCallback(self.userData);
    }
}

@end

// Create the tray status item with menu
void* tray_create(TrayCallback toggleCb, TrayCallback quitCb,
                  TrayCallback prefsCb, void *userData) {
    CaptionsTrayDelegate *delegate = [[CaptionsTrayDelegate alloc] init];
    delegate.toggleCallback = toggleCb;
    delegate.quitCallback = quitCb;
    delegate.prefsCallback = prefsCb;
    delegate.userData = userData;

    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    NSStatusItem *statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
    delegate.statusItem = statusItem;

    // Set icon — use SF Symbols on macOS 11+, fallback to text
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:@"mic"
                                   accessibilityDescription:@"Captions"];
        if (image) {
            [image setTemplate:YES];
            statusItem.button.image = image;
        } else {
            statusItem.button.title = @"CC";
        }
    } else {
        statusItem.button.title = @"CC";
    }

    // Build menu
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *toggleItem = [[NSMenuItem alloc] initWithTitle:@"Toggle Capture"
                                                        action:@selector(toggleAction:)
                                                 keyEquivalent:@""];
    toggleItem.target = delegate;
    delegate.toggleMenuItem = toggleItem;
    [menu addItem:toggleItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *statusItem2 = [[NSMenuItem alloc] initWithTitle:@"Status: Idle"
                                                         action:nil
                                                  keyEquivalent:@""];
    statusItem2.enabled = NO;
    delegate.statusMenuItem = statusItem2;
    [menu addItem:statusItem2];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *prefsItem = [[NSMenuItem alloc] initWithTitle:@"Preferences..."
                                                       action:@selector(prefsAction:)
                                                keyEquivalent:@","];
    prefsItem.target = delegate;
    [menu addItem:prefsItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                      action:@selector(quitAction:)
                                               keyEquivalent:@"q"];
    quitItem.target = delegate;
    [menu addItem:quitItem];

    statusItem.menu = menu;

    return (__bridge_retained void *)delegate;
}

// Update tray status display
void tray_set_status(void *handle, int isActive) {
    CaptionsTrayDelegate *delegate = (__bridge CaptionsTrayDelegate *)handle;

    if (isActive) {
        delegate.statusMenuItem.title = @"Status: Active";
        delegate.toggleMenuItem.title = @"Stop Capture";

        if (@available(macOS 11.0, *)) {
            NSImage *image = [NSImage imageWithSystemSymbolName:@"mic.fill"
                                       accessibilityDescription:@"Captions Active"];
            if (image) {
                [image setTemplate:YES];
                delegate.statusItem.button.image = image;
            }
        }
    } else {
        delegate.statusMenuItem.title = @"Status: Idle";
        delegate.toggleMenuItem.title = @"Toggle Capture";

        if (@available(macOS 11.0, *)) {
            NSImage *image = [NSImage imageWithSystemSymbolName:@"mic"
                                       accessibilityDescription:@"Captions"];
            if (image) {
                [image setTemplate:YES];
                delegate.statusItem.button.image = image;
            }
        }
    }
}

// Destroy the tray
void tray_destroy(void *handle) {
    if (handle) {
        CaptionsTrayDelegate *delegate = (__bridge_transfer CaptionsTrayDelegate *)handle;
        [[NSStatusBar systemStatusBar] removeStatusItem:delegate.statusItem];
        delegate.statusItem = nil;
        delegate = nil;
    }
}
