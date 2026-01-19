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
  // 개발용 로컬 주소 (Web에서는 localhost가 브라우저 자신을 가리키므로 주의 필요하지만,
  // Flutter Web debug에서는 localhost:8000 접근 가능. 단 CORS 설정 필수)
  // 실제 배포 시에는 blossomedu.com 등으로 변경
  static const String baseUrl = 'http://3.38.153.166';
  static const String apiVersion = '/api/v1';
}
