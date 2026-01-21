import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF5D9CEC); // BlossomEdu Blue
  static const Color secondary = Color(0xFF48CFAD); // BlossomEdu Green
  static const Color background = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF333333);
  static const Color textGray = Color(0xFF888888);
  static const Color error = Color(0xFFE9573F);
}

class AppConfig {
  // 환경에 따른 자동 URL 설정
  // - Debug 모드 (flutter run): localhost:8000
  // - Release 모드 (flutter build): 프로덕션 서버
  static const String _devUrl = 'http://localhost:8000';
  static const String _prodUrl = 'https://b-edu.site';

  static String get baseUrl => kReleaseMode ? _prodUrl : _devUrl;
  static const String apiVersion = '/api/v1';
}
