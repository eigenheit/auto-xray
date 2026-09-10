ObjC.import('Cocoa');

function run(argv) {
  var donePath = argv.length > 0 ? argv[0] : '';
  var version = argv.length > 1 ? argv[1] : '';
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var frame = $.NSMakeRect(0, 0, 360, 118);
  var window = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
    frame,
    $.NSWindowStyleMaskTitled,
    $.NSBackingStoreBuffered,
    false
  );
  window.releasedWhenClosed = false;
  window.title = version.length > 0 ? 'AUTO Xray ' + version : 'AUTO Xray';

  var label = $.NSTextField.alloc.initWithFrame($.NSMakeRect(30, 66, 300, 24));
  label.stringValue = 'Установка AUTO Xray…';
  label.bezeled = false;
  label.drawsBackground = false;
  label.editable = false;
  label.selectable = false;
  label.alignment = $.NSTextAlignmentCenter;

  var detail = $.NSTextField.alloc.initWithFrame($.NSMakeRect(30, 45, 300, 18));
  detail.stringValue = 'Пожалуйста, подождите. Окно закроется автоматически.';
  detail.bezeled = false;
  detail.drawsBackground = false;
  detail.editable = false;
  detail.selectable = false;
  detail.alignment = $.NSTextAlignmentCenter;
  detail.font = $.NSFont.systemFontOfSize(11);

  var progress = $.NSProgressIndicator.alloc.initWithFrame($.NSMakeRect(40, 20, 280, 16));
  progress.indeterminate = true;
  progress.style = $.NSProgressIndicatorBarStyle;
  progress.startAnimation(null);

  window.contentView.addSubview(label);
  window.contentView.addSubview(detail);
  window.contentView.addSubview(progress);
  window.center();
  window.makeKeyAndOrderFront(null);
  app.activateIgnoringOtherApps(true);

  var manager = $.NSFileManager.defaultManager;
  while (donePath.length > 0 && !manager.fileExistsAtPath(donePath)) {
    $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.2));
  }

  window.orderOut(null);
  return '';
}
