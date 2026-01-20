import 'tts_service_impl.dart'
    if (dart.library.html) 'tts_service_web.dart'
    if (dart.library.io) 'tts_service_io.dart';

class TtsService {
  final TtsServiceImpl _impl = TtsServiceImpl();

  Future<void> speak(String text) => _impl.speak(text);
  Future<void> stop() => _impl.stop();
}
