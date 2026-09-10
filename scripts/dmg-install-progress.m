#import <Cocoa/Cocoa.h>

static NSTextField *makeLabel(NSRect frame, NSString *text, CGFloat size, BOOL bold) {
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  [label setStringValue:text ?: @""];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setAlignment:NSTextAlignmentCenter];
  [label setFont:bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size]];
  return label;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *donePath = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
    NSString *version = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : @"";

    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSRect frame = NSMakeRect(0, 0, 380, 132);
    NSWindow *window = [[NSWindow alloc]
      initWithContentRect:frame
      styleMask:NSWindowStyleMaskTitled
      backing:NSBackingStoreBuffered
      defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setTitle:version.length > 0 ? [NSString stringWithFormat:@"AUTO Xray %@", version] : @"AUTO Xray"];

    NSTextField *title = makeLabel(NSMakeRect(30, 82, 320, 24), @"Установка AUTO Xray…", 14, YES);
    NSTextField *detail = makeLabel(NSMakeRect(30, 57, 320, 20), @"Пожалуйста, подождите. Окно закроется автоматически.", 11, NO);

    NSProgressIndicator *progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(45, 27, 290, 16)];
    [progress setIndeterminate:YES];
    [progress setStyle:NSProgressIndicatorStyleBar];
    [progress startAnimation:nil];

    [[window contentView] addSubview:title];
    [[window contentView] addSubview:detail];
    [[window contentView] addSubview:progress];

    [window center];
    [window makeKeyAndOrderFront:nil];
    [app activateIgnoringOtherApps:YES];

    NSFileManager *fm = [NSFileManager defaultManager];
    while (donePath.length > 0 && ![fm fileExistsAtPath:donePath]) {
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }

    [window orderOut:nil];
  }
  return 0;
}
