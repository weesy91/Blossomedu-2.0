import '../models/user_model.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<User?> login(String username, String password) async {
    try {
      final response = await _api.client.post('/auth/login/', data: {
        'username': username,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        // Assume API returns { 'token': '...', 'user': { ... } }
        final token = data['token'];
        if (token != null) {
          await _api.setToken(token);
        }

        // Fetch full profile if not included in login response
        // Or assume user data is returned
        return User.fromJson(data['user']);
      }
    } catch (e) {
      print('Login Failed: $e');
    }
    return null;
  }

  Future<void> logout() async {
    await _api.clearToken();
  }
}
