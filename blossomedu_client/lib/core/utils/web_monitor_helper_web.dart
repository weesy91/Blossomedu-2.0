// Web implementation
import 'dart:js_interop';
import 'dart:html' as html;

@JS('openWindowOnSecondaryScreen')
external JSPromise<JSBoolean> _openWindowOnSecondaryScreen(
    JSString url, JSString title, JSNumber width, JSNumber height);

// @JS('window.close')
// external void _windowClose();

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

  static void closeSelf() {
    try {
      html.window.close();
    } catch (e) {
      print('[WebMonitorHelper] Error closing window: $e');
    }
  }

  // [NEW] Remote Close Logic
  static void sendCloseSignal() {
    try {
      final channel = html.BroadcastChannel('blossom_projector_control');
      channel.postMessage('close');
      channel.close();
    } catch (e) {
      print('[WebMonitorHelper] Error sending close signal: $e');
    }
  }

  static void listenForCloseSignal(void Function() onClose) {
    try {
      final channel = html.BroadcastChannel('blossom_projector_control');
      channel.onMessage.listen((event) {
        if (event.data == 'close') {
          onClose();
        }
      });
    } catch (e) {
      print('[WebMonitorHelper] Error listening signal: $e');
    }
  }
}
