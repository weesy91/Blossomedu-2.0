import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants.dart';
import '../models/announcement.dart';

class AnnouncementService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, String>> _getHeaders() async {
    final token = await _storage.read(key: 'auth_token');
    return {
      'Authorization': 'Token $token',
    };
  }

  // Get Announcements
  Future<List<Announcement>> getAnnouncements() async {
    final url = Uri.parse('${AppConfig.baseUrl}/core/api/v1/announcements/');
    final headers = await _getHeaders();
    headers['Content-Type'] = 'application/json';

    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.map((json) => Announcement.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load announcements');
    }
  }

  // Create Announcement (with optional image)
  Future<void> createAnnouncement({
    required String title,
    required String content,
    List<int>? imageBytes,
    String? imageName,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}/core/api/v1/announcements/');
    final token = await _storage.read(key: 'auth_token');

    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = 'Token $token';

    request.fields['title'] = title;
    request.fields['content'] = content;
    request.fields['is_active'] = 'true';

    if (imageBytes != null && imageName != null) {
      request.files.add(http.MultipartFile.fromBytes('image', imageBytes,
          filename: imageName));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 201) {
      throw Exception('Failed to create announcement: ${response.body}');
    }
  }

  // Delete Announcement
  Future<void> deleteAnnouncement(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/announcements/$id/');
    final headers = await _getHeaders();
    headers['Content-Type'] = 'application/json';

    final response = await http.delete(url, headers: headers);

    if (response.statusCode != 204) {
      throw Exception('Failed to delete announcement');
    }
  }
}
