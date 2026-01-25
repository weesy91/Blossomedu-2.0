// Web implementation
import 'dart:js_interop';

@JS('openWindowOnSecondaryScreen')
external JSPromise<JSBoolean> _openWindowOnSecondaryScreen(
    JSString url, JSString title, JSNumber width, JSNumber height);

class WebMonitorHelper {
  static Future<bool> openProjectorWindow(String url,
      {String title = 'Projector', int width = 1200, int height = 800}) async {
    try {
      final success = await _openWindowOnSecondaryScreen(
              url.toJS, title.toJS, width.toJS, height.toJS)
          .toDart;
      return success.toDart;
    } catch (e) {
      print('[WebMonitorHelper] Error calling JS: $e');
      return false;
    }
  }
}
