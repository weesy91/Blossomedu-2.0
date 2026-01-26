// Stub implementation for non-web platforms (Windows, Android, iOS)
// This file is imported when not running on 'dart:html' supported platforms.

class WebMonitorHelper {
  static Future<bool> openProjectorWindow(String url,
      {String title = 'Projector', int width = 1200, int height = 800}) async {
    // On non-web, we can't open a "secondary monitor window" easily via these APIs.
    // Rely on Caller to handle fallback (e.g. url_launcher default).
    // Or return false to indicate "Not handled by JS".
    return false;
  }

  static void closeSelf() {
    // No-op on non-web
  }

  static void sendCloseSignal() {
    // No-op
  }

  static void listenForCloseSignal(void Function() onClose) {
    // No-op
  }

  // [NEW] Progress Sync Stub
  static void sendProgress(
      {required int current, required int total, String? word}) {
    // No-op
  }

  static void listenForProgress(
      void Function(int current, int total, String word) onProgress) {
    // No-op
  }
}
