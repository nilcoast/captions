// Preferences window for macOS using Cocoa.
// Provides a tabbed NSWindow with Model, External API, and General settings.

#import <Cocoa/Cocoa.h>

typedef void (*PrefsCallback)(void *userData, const char *key, const char *value);
typedef void (*PrefsDownloadCallback)(void *userData, int tier);

@interface CaptionsPrefsController : NSWindowController <NSWindowDelegate>
@property (nonatomic, strong) NSTabView *tabView;
@property (nonatomic) PrefsCallback onChanged;
@property (nonatomic) PrefsDownloadCallback onDownload;
@property (nonatomic) void *userData;

// Model tab
@property (nonatomic, strong) NSTextField *hardwareLabel;
@property (nonatomic, strong) NSTextField *recommendLabel;
@property (nonatomic, strong) NSButton *radio7B;
@property (nonatomic, strong) NSButton *radio14B;
@property (nonatomic, strong) NSButton *radio32B;
@property (nonatomic, strong) NSButton *downloadBtn;
@property (nonatomic, strong) NSProgressIndicator *progressBar;
@property (nonatomic, strong) NSTextField *status7B;
@property (nonatomic, strong) NSTextField *status14B;
@property (nonatomic, strong) NSTextField *status32B;

// External API tab
@property (nonatomic, strong) NSButton *externalToggle;
@property (nonatomic, strong) NSTextField *apiUrlField;
@property (nonatomic, strong) NSSecureTextField *apiKeyField;
@property (nonatomic, strong) NSTextField *modelField;

// General tab
@property (nonatomic, strong) NSButton *trayToggle;
@property (nonatomic, strong) NSButton *shortcutToggle;
@property (nonatomic, strong) NSTextField *shortcutField;
@end

@implementation CaptionsPrefsController

- (instancetype)initWithCallback:(PrefsCallback)cb download:(PrefsDownloadCallback)dlCb
                        userData:(void *)ud {
    NSRect frame = NSMakeRect(0, 0, 520, 420);
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"Captions Preferences"];
    [window center];

    self = [super initWithWindow:window];
    if (self) {
        self.onChanged = cb;
        self.onDownload = dlCb;
        self.userData = ud;
        window.delegate = self;

        [self buildUI];
    }
    return self;
}

- (void)buildUI {
    NSTabView *tabView = [[NSTabView alloc] initWithFrame:
        NSMakeRect(10, 10, 500, 395)];
    self.tabView = tabView;

    [self buildModelTab:tabView];
    [self buildExternalTab:tabView];
    [self buildGeneralTab:tabView];

    [self.window.contentView addSubview:tabView];
}

- (void)buildModelTab:(NSTabView *)tabView {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"model"];
    [item setLabel:@"Model"];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 350)];

    CGFloat y = 310;

    // Hardware info
    self.hardwareLabel = [self addLabel:@"Detecting hardware..." to:view at:y];
    y -= 30;
    self.recommendLabel = [self addLabel:@"" to:view at:y];
    y -= 40;

    // Radio buttons for model tier
    self.radio7B = [self addRadio:@"7B — Qwen2.5 7B (Q4_K_M, ~4.4 GB)" to:view at:y tag:0];
    y -= 25;
    self.status7B = [self addStatusLabel:@"" to:view at:y];
    y -= 30;

    self.radio14B = [self addRadio:@"14B — Qwen2.5 14B (Q4_K_M, ~8.3 GB)" to:view at:y tag:1];
    y -= 25;
    self.status14B = [self addStatusLabel:@"" to:view at:y];
    y -= 30;

    self.radio32B = [self addRadio:@"32B — Qwen2.5 32B (Q4_K_M, ~18.9 GB)" to:view at:y tag:2];
    y -= 25;
    self.status32B = [self addStatusLabel:@"" to:view at:y];
    y -= 40;

    // Download button + progress
    self.downloadBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 140, 30)];
    [self.downloadBtn setTitle:@"Download Model"];
    [self.downloadBtn setBezelStyle:NSBezelStyleRounded];
    [self.downloadBtn setTarget:self];
    [self.downloadBtn setAction:@selector(downloadAction:)];
    [view addSubview:self.downloadBtn];

    self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(170, y + 5, 280, 20)];
    [self.progressBar setStyle:NSProgressIndicatorStyleBar];
    [self.progressBar setMinValue:0];
    [self.progressBar setMaxValue:100];
    [self.progressBar setHidden:YES];
    [view addSubview:self.progressBar];

    [item setView:view];
    [tabView addTabViewItem:item];
}

- (void)buildExternalTab:(NSTabView *)tabView {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"external"];
    [item setLabel:@"External API"];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 350)];

    CGFloat y = 310;

    // Toggle
    self.externalToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 440, 25)];
    [self.externalToggle setButtonType:NSButtonTypeSwitch];
    [self.externalToggle setTitle:@"Use external API instead of local model"];
    [self.externalToggle setTarget:self];
    [self.externalToggle setAction:@selector(externalToggleChanged:)];
    [view addSubview:self.externalToggle];
    y -= 40;

    // API URL
    [self addLabel:@"API URL:" to:view at:y width:80];
    self.apiUrlField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, y, 350, 24)];
    [self.apiUrlField setStringValue:@"https://api.openai.com/v1"];
    [self.apiUrlField setPlaceholderString:@"https://api.openai.com/v1"];
    [view addSubview:self.apiUrlField];
    y -= 35;

    // API Key
    [self addLabel:@"API Key:" to:view at:y width:80];
    self.apiKeyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(110, y, 350, 24)];
    [self.apiKeyField setPlaceholderString:@"sk-..."];
    [view addSubview:self.apiKeyField];
    y -= 35;

    // Model
    [self addLabel:@"Model:" to:view at:y width:80];
    self.modelField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, y, 350, 24)];
    [self.modelField setStringValue:@"gpt-4o-mini"];
    [self.modelField setPlaceholderString:@"gpt-4o-mini"];
    [view addSubview:self.modelField];

    [item setView:view];
    [tabView addTabViewItem:item];
}

- (void)buildGeneralTab:(NSTabView *)tabView {
    NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
    [item setLabel:@"General"];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 350)];

    CGFloat y = 310;

    // Tray toggle
    self.trayToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 440, 25)];
    [self.trayToggle setButtonType:NSButtonTypeSwitch];
    [self.trayToggle setTitle:@"Show menu bar icon"];
    [self.trayToggle setState:NSControlStateValueOn];
    [view addSubview:self.trayToggle];
    y -= 35;

    // Shortcut toggle
    self.shortcutToggle = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 200, 25)];
    [self.shortcutToggle setButtonType:NSButtonTypeSwitch];
    [self.shortcutToggle setTitle:@"Global keyboard shortcut"];
    [self.shortcutToggle setState:NSControlStateValueOn];
    [view addSubview:self.shortcutToggle];
    y -= 35;

    // Shortcut field
    [self addLabel:@"Shortcut:" to:view at:y width:80];
    self.shortcutField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, y, 200, 24)];
    [self.shortcutField setStringValue:@"Cmd+Shift+C"];
    [view addSubview:self.shortcutField];

    // Save button
    NSButton *saveBtn = [[NSButton alloc] initWithFrame:NSMakeRect(350, 20, 110, 32)];
    [saveBtn setTitle:@"Save"];
    [saveBtn setBezelStyle:NSBezelStyleRounded];
    [saveBtn setTarget:self];
    [saveBtn setAction:@selector(saveAction:)];
    [view addSubview:saveBtn];

    [item setView:view];
    [tabView addTabViewItem:item];
}

// Helper: add a label
- (NSTextField *)addLabel:(NSString *)text to:(NSView *)view at:(CGFloat)y {
    return [self addLabel:text to:view at:y width:440];
}

- (NSTextField *)addLabel:(NSString *)text to:(NSView *)view at:(CGFloat)y width:(CGFloat)w {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, w, 20)];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [view addSubview:label];
    return label;
}

- (NSTextField *)addStatusLabel:(NSString *)text to:(NSView *)view at:(CGFloat)y {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(40, y, 420, 18)];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:[NSFont systemFontOfSize:11]];
    [label setTextColor:[NSColor secondaryLabelColor]];
    [view addSubview:label];
    return label;
}

- (NSButton *)addRadio:(NSString *)title to:(NSView *)view at:(CGFloat)y tag:(NSInteger)tag {
    NSButton *radio = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 440, 22)];
    [radio setButtonType:NSButtonTypeRadio];
    [radio setTitle:title];
    [radio setTag:tag];
    [radio setTarget:self];
    [radio setAction:@selector(radioChanged:)];
    [view addSubview:radio];
    return radio;
}

- (void)radioChanged:(NSButton *)sender {
    // Deselect others
    self.radio7B.state = (sender.tag == 0) ? NSControlStateValueOn : NSControlStateValueOff;
    self.radio14B.state = (sender.tag == 1) ? NSControlStateValueOn : NSControlStateValueOff;
    self.radio32B.state = (sender.tag == 2) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)downloadAction:(id)sender {
    int tier = 0;
    if (self.radio14B.state == NSControlStateValueOn) tier = 1;
    else if (self.radio32B.state == NSControlStateValueOn) tier = 2;

    if (self.onDownload) {
        self.onDownload(self.userData, tier);
    }
}

- (void)externalToggleChanged:(id)sender {
    // Nothing needed here — state is read on save
}

- (void)saveAction:(id)sender {
    if (!self.onChanged) return;

    // Collect values and notify
    if (self.externalToggle.state == NSControlStateValueOn) {
        self.onChanged(self.userData, "summary.backend", "external");
    } else {
        self.onChanged(self.userData, "summary.backend", "local");
    }

    self.onChanged(self.userData, "summary.external.api_url",
                   self.apiUrlField.stringValue.UTF8String);
    self.onChanged(self.userData, "summary.external.api_key",
                   self.apiKeyField.stringValue.UTF8String);
    self.onChanged(self.userData, "summary.external.model",
                   self.modelField.stringValue.UTF8String);

    self.onChanged(self.userData, "tray.enabled",
                   self.trayToggle.state == NSControlStateValueOn ? "true" : "false");
    self.onChanged(self.userData, "shortcut.enabled",
                   self.shortcutToggle.state == NSControlStateValueOn ? "true" : "false");
    self.onChanged(self.userData, "shortcut.keybinding",
                   self.shortcutField.stringValue.UTF8String);

    // Select model tier
    int tier = 0;
    if (self.radio14B.state == NSControlStateValueOn) tier = 1;
    else if (self.radio32B.state == NSControlStateValueOn) tier = 2;
    const char *tiers[] = {"7b", "14b", "32b"};
    self.onChanged(self.userData, "summary.model_tier", tiers[tier]);

    self.onChanged(self.userData, "_save", "1");

    [self.window close];
}

- (void)windowWillClose:(NSNotification *)notification {
    // Allow window to be reopened
}

@end

// --- C API ---

void* prefs_create(void (*onChanged)(void*, const char*, const char*),
                   void (*onDownload)(void*, int),
                   void *userData) {
    CaptionsPrefsController *ctrl = [[CaptionsPrefsController alloc]
        initWithCallback:onChanged download:onDownload userData:userData];
    return (__bridge_retained void *)ctrl;
}

void prefs_show(void *handle) {
    CaptionsPrefsController *ctrl = (__bridge CaptionsPrefsController *)handle;
    [ctrl showWindow:nil];
    [ctrl.window makeKeyAndOrderFront:nil];
    // Bring app to front
    [NSApp activateIgnoringOtherApps:YES];
}

void prefs_set_hardware(void *handle, const char *gpu, int vram, int ram,
                        const char *tier) {
    CaptionsPrefsController *ctrl = (__bridge CaptionsPrefsController *)handle;

    NSString *gpuStr = gpu ? [NSString stringWithUTF8String:gpu] : @"Unknown";
    NSString *hwText = [NSString stringWithFormat:@"GPU: %@  |  VRAM: %d MB  |  RAM: %d MB",
                        gpuStr, vram, ram];
    [ctrl.hardwareLabel setStringValue:hwText];

    NSString *tierStr = tier ? [NSString stringWithUTF8String:tier] : @"7B";
    NSString *recText = [NSString stringWithFormat:@"Recommended tier: %@", tierStr];
    [ctrl.recommendLabel setStringValue:recText];

    // Pre-select recommended tier
    if ([tierStr isEqualToString:@"32B"]) {
        ctrl.radio32B.state = NSControlStateValueOn;
    } else if ([tierStr isEqualToString:@"14B"]) {
        ctrl.radio14B.state = NSControlStateValueOn;
    } else {
        ctrl.radio7B.state = NSControlStateValueOn;
    }
}

void prefs_set_model_status(void *handle, int tier, int downloaded,
                            const char *path) {
    CaptionsPrefsController *ctrl = (__bridge CaptionsPrefsController *)handle;
    NSString *status;
    if (downloaded) {
        NSString *pathStr = path ? [NSString stringWithUTF8String:path] : @"";
        status = [NSString stringWithFormat:@"✓ Downloaded: %@", pathStr];
    } else {
        status = @"Not downloaded";
    }

    switch (tier) {
        case 0: [ctrl.status7B setStringValue:status]; break;
        case 1: [ctrl.status14B setStringValue:status]; break;
        case 2: [ctrl.status32B setStringValue:status]; break;
    }
}

void prefs_set_external(void *handle, int enabled, const char *apiUrl,
                        const char *apiKey, const char *model) {
    CaptionsPrefsController *ctrl = (__bridge CaptionsPrefsController *)handle;
    ctrl.externalToggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    if (apiUrl) [ctrl.apiUrlField setStringValue:[NSString stringWithUTF8String:apiUrl]];
    if (apiKey) [ctrl.apiKeyField setStringValue:[NSString stringWithUTF8String:apiKey]];
    if (model) [ctrl.modelField setStringValue:[NSString stringWithUTF8String:model]];
}

void prefs_set_general(void *handle, int trayEnabled, int shortcutEnabled,
                       const char *keybinding) {
    CaptionsPrefsController *ctrl = (__bridge CaptionsPrefsController *)handle;
    ctrl.trayToggle.state = trayEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    ctrl.shortcutToggle.state = shortcutEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    if (keybinding) {
        [ctrl.shortcutField setStringValue:[NSString stringWithUTF8String:keybinding]];
    }
}

void prefs_set_download_progress(void *handle, double fraction) {
    CaptionsPrefsController *ctrl = (__bridge CaptionsPrefsController *)handle;
    if (fraction < 0) {
        [ctrl.progressBar setHidden:YES];
    } else {
        [ctrl.progressBar setHidden:NO];
        [ctrl.progressBar setDoubleValue:fraction * 100.0];
    }
}

void prefs_destroy(void *handle) {
    if (handle) {
        CaptionsPrefsController *ctrl = (__bridge_transfer CaptionsPrefsController *)handle;
        [ctrl.window close];
        ctrl = nil;
    }
}
