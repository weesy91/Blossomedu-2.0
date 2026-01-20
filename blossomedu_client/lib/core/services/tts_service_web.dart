import 'dart:html' as html;

class TtsServiceImpl {
  final html.SpeechSynthesis? _synth = html.window.speechSynthesis;

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    final synth = _synth;
    if (synth == null) return;
    synth.cancel();
    final utterance = html.SpeechSynthesisUtterance(text);
    utterance.lang = 'en-US';
    utterance.rate = 0.9;
    utterance.pitch = 1.0;
    utterance.volume = 1.0;
    synth.speak(utterance);
  }

  Future<void> stop() async {
    _synth?.cancel();
  }
}
