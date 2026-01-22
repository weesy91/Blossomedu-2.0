import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
// import '../models/assignment_model.dart'; // TODO: Create Model

import 'package:flutter/material.dart'; // [NEW] For ValueNotifier

class AcademyService {
  // [NEW] Global Data Refresh Trigger
  // Listen to this in TeacherPlannerScreen to refresh data when students/schedules change
  static final ValueNotifier<int> refreshTrigger = ValueNotifier(0);

  static void notifyDataChanged() {
    refreshTrigger.value++;
  }
  // Use SharedPreferences for token storage

  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Token $token', // Django DRF Token Auth
    };
  }

  // 주간 과제 조회
  Future<List<dynamic>> getAssignments({int? studentId}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/assignments/');
    final queryParams = <String, String>{};
    if (studentId != null) queryParams['student_id'] = studentId.toString();
    final url = uri.replace(queryParameters: queryParams);

    try {
      final response = await http.get(url, headers: await _getHeaders());

      if (response.statusCode == 200) {
        return jsonDecode(response.body); // List<dynamic>
      } else {
        throw Exception('Failed to load assignments: ${response.statusCode}');
      }
    } catch (e) {
      print('Assignments Error: $e');
      return [];
    }
  }

  Future<List<dynamic>> getTeacherAssignments() async {
    // 선생님은 모든 학생의 과제를 조회할 수 있어야 함 (쿼리 파라미터 없이 호출하면 됨)
    // AssignmentViewSet.get_queryset에서 student_id가 없으면 전체 반환하도록 되어 있어야 함
    return getAssignments();
  }

  // [NEW] 과제 생성 (Teacher)
  Future<void> createAssignment(Map<String, dynamic> data) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/assignments/');
    final headers = await _getHeaders();

    try {
      final response =
          await http.post(url, headers: headers, body: jsonEncode(data));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return;
      } else {
        throw Exception('Failed to create assignment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error creating assignment: $e');
    }
  }

  // [NEW] 과제 삭제
  Future<void> deleteAssignment(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/academy/api/v1/assignments/$id/');
    final headers = await _getHeaders();

    try {
      final response = await http.delete(url, headers: headers);
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Failed to delete assignment: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error deleting assignment: $e');
    }
  }

  // 주간 과제 상세 조회 (For Detail Screen)
  Future<Map<String, dynamic>> getAssignmentDetail(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/academy/api/v1/assignments/$id/');
    try {
      final response = await http.get(url, headers: await _getHeaders());
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load assignment detail');
      }
    } catch (e) {
      throw Exception('Error fetching assignment detail: $e');
    }
  }

  // 학생 목록 조회 (Teacher)
  Future<List<dynamic>> getStudents({String? day, String? scope}) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/students/');

    final queryParams = <String, String>{};
    if (day != null) queryParams['day'] = day;
    if (scope != null) queryParams['scope'] = scope;

    final uri = url.replace(queryParameters: queryParams);
    final headers = await _getHeaders();

    try {
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        // Map to expected format for UI
        return data
            .map((s) => {
                  'id': s['id'],
                  'name': s['name'] ?? '',
                  'school': s['school_name'] ?? '학교 미정',
                  'grade': s['grade_display'] ?? '',
                  'is_active': s['is_active'] ?? true, // [NEW]
                  'start_date': s['start_date'], // [NEW]
                  'branch': s['branch'],
                  'branch_name': s['branch_name'] ?? '',
                  'class_times': s['class_times'] ?? [],
                  'temp_schedules': s['temp_schedules'] ?? [], // [NEW]
                })
            .toList();
      } else {
        throw Exception('Failed to load students: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching students: $e');
    }
  }

  // Mock getBooks removed. Use getTextbooks.

  // Mock createClassLog removed.

  // 과제 제출 (이미지 업로드)
  Future<bool> submitAssignment(int taskId,
      {List<List<int>>? fileBytesList,
      List<String>? filenames,
      List<int>? fileBytes,
      String? filename}) async {
    final url = Uri.parse(
        '${AppConfig.baseUrl}/academy/api/v1/assignments/$taskId/submit/');
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    try {
      final request = http.MultipartRequest('POST', url);
      request.headers['Authorization'] = 'Token $token';

      final List<List<int>> files = fileBytesList ?? [];
      final List<String> names = filenames ?? [];
      if (files.isEmpty && fileBytes != null) {
        files.add(fileBytes);
        names.add(filename ?? 'image.jpg');
      }
      if (files.isEmpty) {
        return false;
      }

      for (int i = 0; i < files.length; i++) {
        final name = i < names.length ? names[i] : 'image_${i + 1}.jpg';
        request.files.add(
            http.MultipartFile.fromBytes('images', files[i], filename: name));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        print('Submit Failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Submit Error: $e');
      return false;
    }
  }

  Future<void> reviewAssignment(
    int taskId, {
    required bool isApproved,
    String? comment,
    DateTime? resubmissionDeadline,
  }) async {
    final url = Uri.parse(
        '${AppConfig.baseUrl}/academy/api/v1/assignments/$taskId/review/');
    final headers = await _getHeaders();
    final body = {
      'status': isApproved ? 'APPROVED' : 'REJECTED',
      'teacher_comment': comment ?? '',
      if (resubmissionDeadline != null)
        'resubmission_deadline':
            resubmissionDeadline.toIso8601String().substring(0, 10),
    };

    final response =
        await http.post(url, headers: headers, body: jsonEncode(body));
    if (response.statusCode != 200) {
      throw Exception('Failed to review assignment: ${response.body}');
    }
  }

  // [NEW] 학생 등록 메타데이터 조회
  Future<Map<String, dynamic>> getRegistrationMetadata() async {
    final url = Uri.parse(
        '${AppConfig.baseUrl}/core/api/v1/registration/student/metadata/');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load metadata: ${response.body}');
    }
  }

  // [NEW] 학생 등록
  Future<Map<String, dynamic>> registerStudent(
      Map<String, dynamic> data) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/registration/student/');
    final headers = await _getHeaders();

    final response =
        await http.post(url, headers: headers, body: jsonEncode(data));

    if (response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      dynamic errorBody;
      String errorMessage = 'Registration failed';
      try {
        errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        if (errorBody is Map && errorBody.containsKey('error')) {
          errorMessage = errorBody['error'];
        } else {
          errorMessage = errorBody.toString();
        }
      } catch (_) {
        errorMessage = utf8.decode(response.bodyBytes);
      }
      throw Exception(errorMessage);
    }
  }

  // [NEW] Staff Registration Metadata
  Future<Map<String, dynamic>> getStaffRegistrationMetadata() async {
    final url = Uri.parse(
        '${AppConfig.baseUrl}/core/api/v1/registration/staff/metadata/');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load metadata: ${response.body}');
    }
  }

  // [NEW] Staff Registration
  Future<Map<String, dynamic>> registerStaff(Map<String, dynamic> data) async {
    final url = Uri.parse(
        '${AppConfig.baseUrl}/core/api/v1/registration/staff/create_staff/');
    final headers = await _getHeaders();

    final response =
        await http.post(url, headers: headers, body: jsonEncode(data));

    if (response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      dynamic errorBody;
      try {
        errorBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        errorBody = response.body;
      }
      throw Exception(errorBody['error'] ?? 'Registration failed');
    }
  }

  // [NEW] Student Management Search
  Future<List<dynamic>> searchStudents({String query = ''}) async {
    final url = Uri.parse(
        '${AppConfig.baseUrl}/core/api/v1/management/students/?search=$query');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Student Search Failed: ${response.body}');
    }
  }

  // [NEW] Staff Management Search
  Future<List<dynamic>> searchStaff({String query = ''}) async {
    final url = Uri.parse(
        '${AppConfig.baseUrl}/core/api/v1/management/staff/?search=$query');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Staff Search Failed: ${response.body}');
    }
  }

  // [NEW] Get Student Detail
  Future<Map<String, dynamic>> getStudent(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/students/$id/');
    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load student: ${response.body}');
    }
  }

  // [NEW] Update Student
  Future<void> updateStudent(int id, Map<String, dynamic> data) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/students/$id/');
    final headers = await _getHeaders();
    final response =
        await http.patch(url, headers: headers, body: jsonEncode(data));
    if (response.statusCode != 200) {
      throw Exception('Failed to update student: ${response.body}');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to update student: ${response.body}');
    }
    notifyDataChanged(); // [NEW]
  }

  // [NEW] Delete Student
  Future<void> deleteStudent(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/students/$id/');
    final headers = await _getHeaders();
    final response = await http.delete(url, headers: headers);
    if (response.statusCode != 204) {
      throw Exception('Failed to delete student: ${response.body}');
    }
    notifyDataChanged(); // [NEW]
  }

  /// [NEW] 학생 비밀번호 재설정
  Future<void> resetStudentPassword(int studentId, String newPassword) async {
    final url = Uri.parse(
        '${AppConfig.baseUrl}/core/api/v1/management/students/$studentId/reset_password/');
    final headers = await _getHeaders();
    final response = await http.post(
      url,
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'password': newPassword}),
    );
    if (response.statusCode != 200) {
      throw Exception('비밀번호 재설정 실패: ${response.body}');
    }
  }

  // [NEW] Get Staff Detail
  Future<Map<String, dynamic>> getStaff(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/staff/$id/');
    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load staff: ${response.body}');
    }
  }

  // [NEW] Update Staff
  Future<void> updateStaff(int id, Map<String, dynamic> data) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/staff/$id/');
    final headers = await _getHeaders();
    final response =
        await http.patch(url, headers: headers, body: jsonEncode(data));
    if (response.statusCode != 200) {
      throw Exception('Failed to update staff: ${response.body}');
    }
    if (response.statusCode != 200) {
      throw Exception('Failed to update staff: ${response.body}');
    }
  }

  // [NEW] Delete Staff
  Future<void> deleteStaff(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/staff/$id/');
    final headers = await _getHeaders();
    final response = await http.delete(url, headers: headers);
    if (response.statusCode != 204) {
      throw Exception('Failed to delete staff: ${response.body}');
    }
  }

  // [NEW] Branch CRUD
  Future<List<dynamic>> getBranches() async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/branches/');
    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw Exception('Failed to load branches');
  }

  Future<void> createBranch(Map<String, dynamic> data) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/branches/');
    final headers = await _getHeaders();
    final response =
        await http.post(url, headers: headers, body: jsonEncode(data));
    if (response.statusCode != 201) {
      throw Exception(
          'Failed to create branch. Status: ${response.statusCode}, Body: ${utf8.decode(response.bodyBytes)}');
    }
  }

  Future<void> updateBranch(int id, Map<String, dynamic> data) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/branches/$id/');
    final headers = await _getHeaders();
    final response =
        await http.patch(url, headers: headers, body: jsonEncode(data));
    if (response.statusCode != 200) throw Exception('Failed to update branch');
  }

  Future<void> deleteBranch(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/branches/$id/');
    final headers = await _getHeaders();
    final response = await http.delete(url, headers: headers);
    if (response.statusCode != 204) throw Exception('Failed to delete branch');
  }

  // [NEW] School CRUD
  Future<List<dynamic>> getSchools() async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/schools/');
    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw Exception('Failed to load schools');
  }

  Future<void> createSchool(Map<String, dynamic> data) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/schools/');
    final headers = await _getHeaders();
    final response =
        await http.post(url, headers: headers, body: jsonEncode(data));
    if (response.statusCode != 201) throw Exception('Failed to create school');
  }

  Future<void> updateSchool(int id, Map<String, dynamic> data) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/schools/$id/');
    final headers = await _getHeaders();
    final response =
        await http.patch(url, headers: headers, body: jsonEncode(data));
    if (response.statusCode != 200) throw Exception('Failed to update school');
  }

  Future<void> deleteSchool(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/core/api/v1/management/schools/$id/');
    final headers = await _getHeaders();
    final response = await http.delete(url, headers: headers);
    if (response.statusCode != 204) throw Exception('Failed to delete school');
  }

  // [NEW] Textbook Management
  Future<List<Map<String, dynamic>>> getTextbooks({String? category}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/textbooks/');
    final queryParams = <String, String>{};
    if (category != null) queryParams['category'] = category;

    final url = uri.replace(queryParameters: queryParams);

    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load textbooks');
  }

  // [NEW] Vocab Book Management
  Future<List<Map<String, dynamic>>> getVocabBooks() async {
    final url = Uri.parse('${AppConfig.baseUrl}/vocab/api/v1/books/');
    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
      return data.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load vocab books');
  }

  Future<void> createTextbook(Map<String, dynamic> data) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/textbooks/');
    final headers = await _getHeaders();
    final response =
        await http.post(url, headers: headers, body: jsonEncode(data));

    if (response.statusCode != 201) {
      throw Exception('Failed to create textbook: ${response.body}');
    }
  }

  Future<void> updateTextbook(int id, Map<String, dynamic> data) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/textbooks/$id/');
    final headers = await _getHeaders();
    final response =
        await http.patch(url, headers: headers, body: jsonEncode(data));

    if (response.statusCode != 200) {
      throw Exception('Failed to update textbook: ${response.body}');
    }
  }

  Future<void> deleteTextbook(int id) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/textbooks/$id/');
    final headers = await _getHeaders();
    final response = await http.delete(url, headers: headers);

    if (response.statusCode != 204) {
      throw Exception('Failed to delete textbook');
    }
  }

  // [NEW] Class Log Management
  Future<void> createClassLog(Map<String, dynamic> data) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/class-logs/');
    final headers = await _getHeaders();

    final response =
        await http.post(url, headers: headers, body: jsonEncode(data));

    if (response.statusCode != 201) {
      throw Exception('Failed to create class log: ${response.body}');
    }
  }

  Future<void> updateClassLog(int id, Map<String, dynamic> data) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/academy/api/v1/class-logs/$id/');
    final headers = await _getHeaders();

    final response =
        await http.patch(url, headers: headers, body: jsonEncode(data));

    if (response.statusCode != 200) {
      throw Exception('Failed to update class log: ${response.body}');
    }
  }

  Future<void> deleteClassLog(int id) async {
    final url =
        Uri.parse('${AppConfig.baseUrl}/academy/api/v1/class-logs/$id/');
    final headers = await _getHeaders();

    final response = await http.delete(url, headers: headers);

    if (response.statusCode != 204) {
      throw Exception('Failed to delete class log: ${response.body}');
    }
  }

  // [NEW] Get Class Logs (Filtered)
  Future<List<dynamic>> getClassLogs(
      {int? studentId, String? subject, String? date}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/class-logs/');
    final queryParams = <String, String>{};
    if (studentId != null) queryParams['student_id'] = studentId.toString();
    if (subject != null) queryParams['subject'] = subject;
    if (date != null) queryParams['date'] = date; // [NEW]

    final url = uri.replace(queryParameters: queryParams);

    final headers = await _getHeaders();
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw Exception('Failed to load class logs');
  }

  // [NEW] Attendance Management
  Future<Map<String, dynamic>?> checkAttendance(
      int studentId, DateTime date) async {
    final dateStr = date.toIso8601String().substring(0, 10); // YYYY-MM-DD
    final url = Uri.parse(
        '${AppConfig.baseUrl}/academy/api/v1/attendances/?student_id=$studentId&date=$dateStr');
    final headers = await _getHeaders();

    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      final List results = jsonDecode(utf8.decode(response.bodyBytes));
      if (results.isNotEmpty) {
        return results.first; // Return first matching record
      }
      return null;
    }
    return null;
  }

  Future<void> createAttendance(
      int studentId, String status, DateTime date) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/attendances/');
    final headers = await _getHeaders();
    final body = {
      'student_id': studentId,
      'status': status,
      'date': date.toIso8601String().substring(0, 10), // YYYY-MM-DD
      'check_in_time':
          status != 'ABSENT' ? DateTime.now().toIso8601String() : null
    };

    final response =
        await http.post(url, headers: headers, body: jsonEncode(body));

    if (response.statusCode != 201) {
      throw Exception('Failed to create attendance: ${response.body}');
    }
  }

  Future<void> createTemporarySchedule(Map<String, dynamic> data) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/schedules/');
    final headers = await _getHeaders();
    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode(data),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to create schedule: ${response.body}');
    }
    notifyDataChanged(); // [NEW]
  }

  Future<void> updateTemporarySchedule(
      int id, Map<String, dynamic> data) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/schedules/$id/');
    final headers = await _getHeaders();
    final response = await http.patch(
      url,
      headers: headers,
      body: jsonEncode(data),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update schedule: ${response.body}');
    }
    notifyDataChanged(); // [NEW]
  }

  Future<void> deleteTemporarySchedule(int id) async {
    final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/schedules/$id/');
    final headers = await _getHeaders();
    final response = await http.delete(url, headers: headers);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete schedule: ${response.body}');
    }
    notifyDataChanged(); // [NEW]
  }

  // 출석 목록 조회 (날짜 필터)
  Future<List<dynamic>> getAttendances({String? date}) async {
    final uri = Uri.parse(
        '${AppConfig.baseUrl}/academy/api/v1/attendances/?date=$date');
    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load attendances');
    }
  }

  // ============ MESSAGING API ============

  /// 대화 목록 조회
  Future<List<dynamic>> getConversations() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/messaging/conversations/');
    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load conversations: ${response.statusCode}');
    }
  }

  /// 대화방 조회 또는 생성
  Future<Map<String, dynamic>> getOrCreateConversation(int otherUserId) async {
    final uri = Uri.parse(
        '${AppConfig.baseUrl}/messaging/conversations/get_or_create/');
    final headers = await _getHeaders();
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'other_user_id': otherUserId}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception(
          'Failed to get/create conversation: ${response.statusCode}');
    }
  }

  /// 메시지 목록 조회
  Future<List<dynamic>> getMessages(int conversationId) async {
    final uri = Uri.parse(
        '${AppConfig.baseUrl}/messaging/messages/?conversation=$conversationId');
    final headers = await _getHeaders();
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load messages: ${response.statusCode}');
    }
  }

  /// 메시지 전송
  Future<void> sendMessage(int conversationId, String content) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/messaging/messages/');
    final headers = await _getHeaders();
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'conversation': conversationId,
        'content': content,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  /// 메시지 읽음 처리
  Future<void> markMessagesAsRead(int conversationId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/messaging/messages/mark_read/');
    final headers = await _getHeaders();
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({'conversation': conversationId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark as read: ${response.statusCode}');
    }
  }

  /// 전체 안 읽은 메시지 수 조회 (배지용)
  Future<int> getUnreadMessageCount() async {
    final uri =
        Uri.parse('${AppConfig.baseUrl}/messaging/conversations/unread_total/');
    final headers = await _getHeaders();
    try {
      final response = await http.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['unread_total'] ?? 0;
      }
    } catch (e) {
      print('Error getting unread count: $e');
    }
    return 0;
  }
}
