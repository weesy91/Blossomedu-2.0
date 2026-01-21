import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late Dio _dio;
  // final FlutterSecureStorage _storage = const FlutterSecureStorage(); // Removed

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 3),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Interceptor: Inject Token
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Use SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');

        print('DEBUG Interceptor: Token from prefs = $token');
        print('DEBUG Interceptor: Request URL = ${options.uri}');

        if (token != null) {
          options.headers['Authorization'] = 'Token $token';
          print('DEBUG Interceptor: Authorization header added');
        } else {
          print('DEBUG Interceptor: No token found!');
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) {
        // Handle 401 Unauthorized (Logout?)
        print(
          'API Error: ${e.response?.statusCode} -> ${e.requestOptions.uri} -> ${e.message}',
        );
        return handler.next(e);
      },
    ));
  }

  Dio get client => _dio;

  Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }
}
