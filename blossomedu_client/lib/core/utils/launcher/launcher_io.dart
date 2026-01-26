import 'package:url_launcher/url_launcher.dart';

Future<void> safeLaunch(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) {
    // [FIX] Skip canLaunchUrl check which fails on iOS if scheme not in Info.plist
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  } else {
    throw 'Invalid URL: $url';
  }
}
