import 'package:dio/dio.dart';
import 'api_service.dart';

class VocabService {
  final Dio _dio = ApiService().client;

  // Get all vocab books
  Future<List<dynamic>> getVocabBooks() async {
    try {
      final response = await _dio.get('/vocab/api/v1/books/');
      return response.data;
    } catch (e) {
      throw Exception('Failed to load vocab books: $e');
    }
  }

  // Upload a new vocab book (CSV)
  Future<void> uploadVocabBook({
    required String title,
    String? description,
    required List<int> fileBytes,
    required String filename,
    int? publisherId,
    int? targetBranchId,
    int? targetSchoolId,
    int? targetGrade,
  }) async {
    try {
      final map = {
        'title': title,
        'description': description ?? '',
        'csv_file': MultipartFile.fromBytes(
          fileBytes,
          filename: filename,
        ),
      };

      if (targetBranchId != null) map['target_branch'] = targetBranchId;
      if (targetSchoolId != null) map['target_school'] = targetSchoolId;
      if (targetGrade != null) map['target_grade'] = targetGrade;
      if (publisherId != null) map['publisher'] = publisherId;

      final formData = FormData.fromMap(map);

      await _dio.post(
        '/vocab/api/v1/books/',
        data: formData,
        options: Options(
          headers: {
            'Content-Type': 'multipart/form-data',
          },
        ),
      );
    } catch (e) {
      throw Exception('Failed to upload vocab book: $e');
    }
  }

  // Publisher metadata
  Future<List<dynamic>> getPublishers() async {
    try {
      final response = await _dio.get('/vocab/api/v1/publishers/');
      return response.data;
    } catch (e) {
      throw Exception('Failed to load publishers: $e');
    }
  }

  Future<Map<String, dynamic>> createPublisher(String name) async {
    try {
      final response = await _dio.post(
        '/vocab/api/v1/publishers/',
        data: {'name': name},
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to create publisher: $e');
    }
  }

  Future<void> updatePublisher(int id, String name) async {
    try {
      await _dio.patch(
        '/vocab/api/v1/publishers/$id/',
        data: {'name': name},
      );
    } catch (e) {
      throw Exception('Failed to update publisher: $e');
    }
  }

  Future<void> deletePublisher(int id) async {
    try {
      await _dio.delete('/vocab/api/v1/publishers/$id/');
    } catch (e) {
      throw Exception('Failed to delete publisher: $e');
    }
  }

  // Get schools list (filtered by branch)
  Future<List<dynamic>> getSchools({int? branchId}) async {
    try {
      final response = await _dio.get(
        '/core/api/v1/schools/',
        queryParameters: branchId != null ? {'branch_id': branchId} : null,
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to load schools: $e');
    }
  }

  // Delete a vocab book
  Future<void> deleteVocabBook(int id) async {
    try {
      await _dio.delete('/vocab/api/v1/books/$id/');
    } catch (e) {
      throw Exception('Failed to delete vocab book: $e');
    }
  }

  // [NEW] Update vocab book metadata
  Future<void> updateVocabBook(int id, Map<String, dynamic> data) async {
    try {
      await _dio.patch('/vocab/api/v1/books/$id/', data: data);
    } catch (e) {
      throw Exception('Failed to update vocab book: $e');
    }
  }

  // Update a word
  Future<Map<String, dynamic>> updateWord(
      int id, Map<String, dynamic> changes) async {
    try {
      final response = await _dio.patch(
        '/vocab/api/v1/words/$id/',
        data: changes,
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to update word: $e');
    }
  }

  // Get words for a specific book
  Future<List<dynamic>> getWords(
    int bookId, {
    String? dayRange,
    bool shuffle = false,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (dayRange != null && dayRange.isNotEmpty) {
        params['day_range'] = dayRange;
      }
      if (shuffle) params['shuffle'] = 'true';
      final response = await _dio.get(
        '/vocab/api/v1/books/$bookId/words/',
        queryParameters: params.isEmpty ? null : params,
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to load words: $e');
    }
  }

  // Get available books (library)
  Future<List<dynamic>> getAvailableBooks() async {
    try {
      final response = await _dio.get('/vocab/api/v1/books/available/');
      return response.data;
    } catch (e) {
      throw Exception('Failed to load available books: $e');
    }
  }

  // Subscribe to a book
  Future<void> subscribeToBook(int bookId) async {
    try {
      await _dio.post('/vocab/api/v1/books/$bookId/subscribe/');
    } catch (e) {
      throw Exception('Failed to subscribe to book: $e');
    }
  }

  // Get dashboard stats
  Future<Map<String, dynamic>> getStats() async {
    try {
      final response = await _dio.get('/vocab/api/v1/books/stats/');
      return response.data;
    } catch (e) {
      throw Exception('Failed to load stats: $e');
    }
  }

  // Search words (DB + external fallback)
  Future<List<dynamic>> searchWords(String query) async {
    try {
      final response = await _dio.get(
        '/vocab/api/v1/search/',
        queryParameters: {'q': query},
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to search words: $e');
    }
  }

  // Add word to personal wrong note
  Future<void> addPersonalWord({
    required String english,
    required String korean,
  }) async {
    try {
      await _dio.post(
        '/vocab/api/v1/search/add_personal/',
        data: {'english': english, 'korean': korean},
      );
    } catch (e) {
      throw Exception('Failed to add personal word: $e');
    }
  }

  // Generate test questions with range
  Future<List<dynamic>> generateTestQuestions({
    required int bookId,
    required String range,
    int count = 30,
  }) async {
    try {
      final response = await _dio.get(
        '/vocab/api/v1/tests/start_test/',
        queryParameters: {
          'book_id': bookId,
          'range': range,
          'count': count,
        },
      );
      return response.data['questions'];
    } catch (e) {
      throw Exception('Failed to generate test questions: $e');
    }
  }

  // Submit test result
  Future<Map<String, dynamic>> submitTestResult({
    required int bookId,
    required String range,
    required List<Map<String, dynamic>> details,
    String mode = 'practice',
    String? assignmentId,
  }) async {
    try {
      final response = await _dio.post(
        '/vocab/api/v1/tests/submit/',
        data: {
          'book_id': bookId,
          'range': range,
          'details': details,
          'mode': mode,
          if (assignmentId != null) 'assignment_id': assignmentId,
        },
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to submit test result: $e');
    }
  }

  // Request Test Correction
  Future<void> requestCorrection(int testId, String word) async {
    try {
      await _dio.post(
        '/vocab/api/v1/tests/$testId/request_correction/',
        data: {'word': word},
      );
    } catch (e) {
      throw Exception('Failed to request correction: $e');
    }
  }

  // [Teacher] Get all test requests
  Future<List<dynamic>> getTeacherTestRequests(
      {bool pendingOnly = false, bool includeDetails = true}) async {
    try {
      final params = <String, dynamic>{};
      if (pendingOnly) params['pending'] = 'true';
      if (!includeDetails) params['include_details'] = 'false';
      final response = await _dio.get(
        '/vocab/api/v1/tests/',
        queryParameters: params.isEmpty ? null : params,
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to load test requests: $e');
    }
  }

  // [Teacher] Get specific test result detail
  Future<Map<String, dynamic>> getTestResult(int id) async {
    try {
      final response = await _dio.get('/vocab/api/v1/tests/$id/');
      return response.data;
    } catch (e) {
      throw Exception('Failed to load test result: $e');
    }
  }

  // [Teacher] Review/Correct test result
  Future<Map<String, dynamic>> reviewTestResult(
      int id, List<Map<String, dynamic>> corrections) async {
    try {
      final response = await _dio.post(
        '/vocab/api/v1/tests/$id/review_result/',
        data: {'corrections': corrections},
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to review test result: $e');
    }
  }

  // Study dashboard (growth/heatmap/rankings)
  Future<Map<String, dynamic>> getStudyDashboard() async {
    try {
      final response = await _dio.get('/vocab/api/v1/tests/dashboard/');
      return response.data;
    } catch (e) {
      throw Exception('Failed to load study dashboard: $e');
    }
  }

  // Heatmap day history
  Future<Map<String, dynamic>> getDayHistory(String date) async {
    try {
      final response = await _dio.get(
        '/vocab/api/v1/tests/day_history/',
        queryParameters: {'date': date},
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to load day history: $e');
    }
  }

  // Ranking event management
  Future<List<dynamic>> getRankingEvents({bool activeOnly = false}) async {
    try {
      final response = await _dio.get(
        '/vocab/api/v1/events/',
        queryParameters: activeOnly ? {'active': 'true'} : null,
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to load ranking events: $e');
    }
  }

  Future<Map<String, dynamic>> createRankingEvent(
      Map<String, dynamic> data) async {
    try {
      final response = await _dio.post('/vocab/api/v1/events/', data: data);
      return response.data;
    } catch (e) {
      throw Exception('Failed to create ranking event: $e');
    }
  }

  Future<Map<String, dynamic>> updateRankingEvent(
      int id, Map<String, dynamic> data) async {
    try {
      final response = await _dio.patch(
        '/vocab/api/v1/events/$id/',
        data: data,
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to update ranking event: $e');
    }
  }

  Future<void> deleteRankingEvent(int id) async {
    try {
      await _dio.delete('/vocab/api/v1/events/$id/');
    } catch (e) {
      throw Exception('Failed to delete ranking event: $e');
    }
  }

  // [Student] Get own test results
  Future<List<dynamic>> getStudentTestResults(
      {bool includeDetails = true}) async {
    try {
      final params = <String, dynamic>{};
      if (includeDetails) {
        params['include_details'] = 'true';
      }
      final response = await _dio.get(
        '/vocab/api/v1/tests/',
        queryParameters: params.isEmpty ? null : params,
      );
      return response.data;
    } catch (e) {
      throw Exception('Failed to load test results: $e');
    }
  }

  // [Student] Get mock exam results
  Future<List<dynamic>> getMockExams() async {
    try {
      final response = await _dio.get('/mock/api/v1/results/');
      return response.data;
    } catch (e) {
      throw Exception('Failed to load mock exams: $e');
    }
  }
}
