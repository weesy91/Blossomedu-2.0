import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_tts/flutter_tts.dart';

class TtsServiceImpl {
  final FlutterTts flutterTts = FlutterTts();
  Map<dynamic, dynamic>? _bestVoice;
  String _bestLocale = "en-US";
  late final Future<void> _initFuture;

  TtsServiceImpl() {
    _initFuture = _initTts();
  }

  Future<void> _initTts() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await flutterTts.setIosAudioCategory(
            IosTextToSpeechAudioCategory.playback,
            [
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
              IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
              IosTextToSpeechAudioCategoryOptions.mixWithOthers,
              IosTextToSpeechAudioCategoryOptions.defaultToSpeaker
            ],
            IosTextToSpeechAudioMode.defaultMode);
      }

      await flutterTts.setLanguage(_bestLocale);

      try {
        final voices = await flutterTts.getVoices;
        final List<dynamic> voiceList = voices as List<dynamic>;

        Map<dynamic, dynamic>? bestVoice;

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
          await flutterTts
              .setVoice({"name": bestVoice["name"], "locale": _bestLocale});
          print(
              "TTS Configured: ${bestVoice['name']} [${bestVoice['locale']}]");
        } else {
          _bestLocale = "en-US";
          await flutterTts.setLanguage(_bestLocale);
        }
      } catch (e) {
        print("Voice selection warning: $e");
      }

      await flutterTts.setPitch(1.0);
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setVolume(1.0);
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
    if (text.isEmpty) return;
    await _initFuture;
    await _ensureEnglishVoice();
    try {
      await flutterTts.speak(text);
    } catch (e) {
      print("TTS Speak Error: $e");
    }
  }

  Future<void> stop() async {
    await flutterTts.stop();
  }
}
