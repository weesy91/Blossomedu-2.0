import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts flutterTts = FlutterTts();
  Map<dynamic, dynamic>? _bestVoice;
  String _bestLocale = "en-US";

  TtsService() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await flutterTts.setLanguage(_bestLocale);

      // [Quality Fix] Attempt to pick a better voice (US/UK Priority)
      // [Robust Fix] Priority: Locale Match (en-US > en-GB) -> Name Match
      try {
        final voices = await flutterTts.getVoices;
        final List<dynamic> voiceList = voices as List<dynamic>;

        Map<dynamic, dynamic>? bestVoice;

        // 1. Try matching Locales explicitly
        // Chrome/Web often uses 'en-US', 'en_US', 'en-GB', 'en_GB'
        final targetLocales = ["en-US", "en_US", "en-GB", "en_GB"];

        for (var locale in targetLocales) {
          try {
            bestVoice = voiceList.firstWhere(
                (v) =>
                    v['locale'] != null &&
                    v['locale'].toString().contains(locale),
                orElse: () => null);
          } catch (_) {}
          if (bestVoice != null) break;
        }

        // 2. Fallback: Specific High-Quality Voice Names
        if (bestVoice == null) {
          final targetNames = [
            "Google US English",
            "Google UK English Female",
            "Microsoft Zira",
            "Samantha"
          ];
          for (var name in targetNames) {
            try {
              bestVoice = voiceList.firstWhere(
                  (v) => v['name'].toString().contains(name),
                  orElse: () => null);
            } catch (_) {}
            if (bestVoice != null) break;
          }
        }

        if (bestVoice != null) {
          _bestVoice = bestVoice;
          _bestLocale = (bestVoice["locale"] ?? "en-US").toString();
          await flutterTts.setVoice({
            "name": bestVoice["name"],
            "locale": _bestLocale
          });
          print(
              "TTS Configured: ${bestVoice['name']} [${bestVoice['locale']}]");
        } else {
          // Last Resort
          _bestLocale = "en-US";
          await flutterTts.setLanguage(_bestLocale);
        }
      } catch (e) {
        print("Voice selection warning: $e");
      }

      await flutterTts.setPitch(1.0);
      await flutterTts
          .setSpeechRate(0.8); // Slightly slower than 1.0 for clarity
    } catch (e) {
      print("TTS Error: $e");
    }
  }

  Future<void> _ensureEnglishVoice() async {
    try {
      await flutterTts.setLanguage(_bestLocale);
      if (_bestVoice != null) {
        await flutterTts.setVoice({
          "name": _bestVoice!["name"],
          "locale": _bestLocale,
        });
      }
    } catch (e) {
      print("TTS Ensure Voice Error: $e");
    }
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await _ensureEnglishVoice();
      await flutterTts.speak(text);
    }
  }

  Future<void> stop() async {
    await flutterTts.stop();
  }
}
