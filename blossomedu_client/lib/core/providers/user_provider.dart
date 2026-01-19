import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class UserProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  User? _user;
  bool _isLoading = false;

  User? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isLoading => _isLoading;

  // 생성자에서 로그인 상태 확인
  UserProvider() {
    checkLoginStatus();
  }

  Future<void> checkLoginStatus() async {
    _isLoading = true;
    notifyListeners();
    try {
      final user = await _authService.checkAuth();
      if (user != null) {
        _user = user;
      }
    } catch (e) {
      print("Auto-login failed: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    final user = await _authService.login(username, password);

    _isLoading = false;
    if (user != null) {
      _user = user;
      notifyListeners();
      return true;
    } else {
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    notifyListeners();
  }

  // UI 테스트용 가짜 로그인 (수동 호출용)
  void setMockUser() {
    _user = User(
      id: 999,
      username: 'test_student',
      name: '체험학생',
      userType: 'STUDENT',
    );
    notifyListeners();
  }

  void setMockTeacher() {
    _user = User(
      id: 888,
      username: 'test_teacher',
      name: '나선생',
      userType: 'AM',
      isSuperuser: true, // Mock Admin
      position: 'PRINCIPAL', // Mock Principal
    );
    notifyListeners();
  }
}
