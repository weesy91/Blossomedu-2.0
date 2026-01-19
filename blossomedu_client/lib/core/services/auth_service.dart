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
        print('DEBUG: Login Response Data: $data'); // [DEBUG]

        final token = data['token']; // Check if strictly 'token' or 'key'
        print('DEBUG: Token: $token'); // [DEBUG]

        if (token != null) {
          try {
            await _api.setToken(token);
            print('DEBUG: Token saved successfully');
          } catch (e) {
            print('ERROR: Failed to save token: $e');
            // Continue login even if token save fails
          }
        }

        final userMap = data['user'];
        print('DEBUG: User Map: $userMap'); // [DEBUG]

        if (userMap == null) {
          print('DEBUG: User Map is NULL!');
          throw Exception('User data is missing in response');
        }

        return User.fromJson(userMap);
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
