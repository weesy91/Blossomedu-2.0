import 'dart:js_interop';
import 'dart:html' as html;
import 'dart:convert';

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
  // [NEW] Remote Close Logic
  static void sendCloseSignal() {
    try {
      final channel = html.BroadcastChannel('blossom_projector_control');
      channel.postMessage('close');
      // Don't close immediately if we want to reuse channel, but here it's fine as it's fire-and-forget?
      // actually better to keep it open or just close.
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

  // [NEW] Progress Sync
  static void sendProgress(
      {required int current, required int total, String? word}) {
    try {
      final channel = html.BroadcastChannel('blossom_projector_sync');
      final payload = jsonEncode({
        'type': 'progress',
        'current': current,
        'total': total,
        'word': word ?? '',
      });
      channel.postMessage(payload);
      channel.close();
    } catch (e) {
      print('[WebMonitorHelper] Error sending progress: $e');
    }
  }

  static void listenForProgress(
      void Function(int current, int total, String word) onProgress) {
    try {
      final channel = html.BroadcastChannel('blossom_projector_sync');
      channel.onMessage.listen((event) {
        final data = event.data;
        if (data is String) {
          try {
            final decoded = jsonDecode(data);
            if (decoded is Map && decoded['type'] == 'progress') {
              onProgress(
                decoded['current'] as int,
                decoded['total'] as int,
                decoded['word'] as String,
              );
            }
          } catch (e) {
            print('[WebMonitorHelper] Decode error: $e');
          }
        }
      });
    } catch (e) {
      print('[WebMonitorHelper] Error listening progress: $e');
    }
  }
}
