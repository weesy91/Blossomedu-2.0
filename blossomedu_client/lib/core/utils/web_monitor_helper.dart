// Conditional Export
// Exports web_monitor_helper_web.dart if dart.library.js_interop is available (Web)
// Otherwise exports web_monitor_helper_stub.dart

export 'web_monitor_helper_stub.dart'
    if (dart.library.js_interop) 'web_monitor_helper_web.dart';
