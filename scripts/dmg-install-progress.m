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

static void applyProgressState(NSString *statePath, NSProgressIndicator *progress, NSTextField *detail) {
  if (statePath.length == 0) return;

  NSData *data = [NSData dataWithContentsOfFile:statePath];
  if (!data) return;

  NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!text) return;

  NSArray<NSString *> *parts = [text componentsSeparatedByString:@"\t"];
  if (parts.count > 0) {
    double value = [parts[0] doubleValue];
    if (value < 0.0) value = 0.0;
    if (value > 100.0) value = 100.0;
    [progress setDoubleValue:value];
  }

  if (parts.count > 1) {
    NSString *status = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"\t"];
    status = [status stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (status.length > 0) [detail setStringValue:status];
  }
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *donePath = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"";
    NSString *statePath = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : @"";
    NSString *readyPath = argc > 3 ? [NSString stringWithUTF8String:argv[3]] : @"";
    NSString *version = argc > 4 ? [NSString stringWithUTF8String:argv[4]] : @"";

    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [app finishLaunching];

    NSRect frame = NSMakeRect(0, 0, 380, 132);
    NSWindow *window = [[NSWindow alloc]
      initWithContentRect:frame
      styleMask:NSWindowStyleMaskTitled
      backing:NSBackingStoreBuffered
      defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setLevel:NSFloatingWindowLevel];
    [window setTitle:version.length > 0 ? [NSString stringWithFormat:@"AUTO Xray %@", version] : @"AUTO Xray"];

    NSTextField *title = makeLabel(NSMakeRect(30, 82, 320, 24), @"Установка AUTO Xray…", 14, YES);
    NSTextField *detail = makeLabel(NSMakeRect(30, 57, 320, 20), @"Подготовка…", 11, NO);

    NSProgressIndicator *progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(45, 27, 290, 16)];
    [progress setIndeterminate:NO];
    [progress setMinValue:0.0];
    [progress setMaxValue:100.0];
    [progress setDoubleValue:3.0];
    [progress setStyle:NSProgressIndicatorStyleBar];

    [[window contentView] addSubview:title];
    [[window contentView] addSubview:detail];
    [[window contentView] addSubview:progress];

    applyProgressState(statePath, progress, detail);
    [window center];
    [window makeKeyAndOrderFront:nil];
    [window orderFrontRegardless];
    [app activateIgnoringOtherApps:YES];
    [window displayIfNeeded];

    if (readyPath.length > 0) {
      [@"ready\n" writeToFile:readyPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    while (donePath.length > 0 && ![fm fileExistsAtPath:donePath]) {
      applyProgressState(statePath, progress, detail);
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }

    applyProgressState(statePath, progress, detail);
    [window orderOut:nil];
  }
  return 0;
}
