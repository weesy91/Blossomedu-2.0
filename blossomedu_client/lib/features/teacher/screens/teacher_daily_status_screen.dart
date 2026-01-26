import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';

class TeacherDailyStatusScreen extends StatefulWidget {
  const TeacherDailyStatusScreen({super.key});

  @override
  State<TeacherDailyStatusScreen> createState() =>
      _TeacherDailyStatusScreenState();
}

class _TeacherDailyStatusScreenState extends State<TeacherDailyStatusScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _data;
  List<String> _teachers = [];
  String? _selectedTeacher;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token'); // [FIX] Correct Key
      if (token == null) throw Exception('로그인이 필요합니다.');

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final url = Uri.parse(
          '${AppConfig.baseUrl}/academy/api/v1/daily-status/?date=$dateStr');

      final response = await http.get(url, headers: {
        'Authorization': 'Token $token', // [FIX] Use 'Token' scheme
        'Content-Type': 'application/json',
      });

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        // Extract Unique Teachers
        final students = decoded['students'] as List? ?? [];
        final teacherSet = <String>{};
        for (var s in students) {
          if (s['teacher'] != null) teacherSet.add(s['teacher'].toString());
        }

        setState(() {
          _data = decoded;
          _teachers = teacherSet.toList()..sort();
          if (_selectedTeacher != null &&
              !_teachers.contains(_selectedTeacher)) {
            _selectedTeacher = null;
          }
          _isLoading = false;
        });
      } else {
        throw Exception('데이터 로드 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('일일 학생 현황',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildFilter(), // [NEW] Teacher Filter
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final dateDisplay =
        DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(_selectedDate);

    // Summary Data
    int total = 0, present = 0, logCompleted = 0;
    if (_data != null && _data!['summary'] != null) {
      total = _data!['summary']['total'] ?? 0;
      present = _data!['summary']['present'] ?? 0;
      logCompleted = _data!['summary']['log_completed'] ?? 0;
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(dateDisplay,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.arrow_drop_down)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard('관리 대상', '$total명', Colors.black87),
              const SizedBox(width: 12),
              _buildStatCard('출석', '$present명', Colors.blue),
              const SizedBox(width: 12),
              _buildStatCard('일지 완료', '$logCompleted명', Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  // [NEW] Teacher Filter Widget
  Widget _buildFilter() {
    if (_teachers.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('담당 강사: ', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _selectedTeacher,
            hint: const Text('전체 보기'),
            items: [
              const DropdownMenuItem(value: null, child: Text('전체 보기')),
              ..._teachers.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t),
                  ))
            ],
            onChanged: (val) {
              setState(() => _selectedTeacher = val);
            },
            underline: Container(), // Remove underline
            style: const TextStyle(color: Colors.black87, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Text('오류: $_errorMessage'));
    if (_data == null ||
        _data!['students'] == null ||
        (_data!['students'] as List).isEmpty) {
      return const Center(child: Text('해당 날짜에 등원 예정인 학생이 없습니다.'));
    }

    var students = _data!['students'] as List;

    // Filter by Teacher
    if (_selectedTeacher != null) {
      students =
          students.where((s) => s['teacher'] == _selectedTeacher).toList();
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final s = students[index];
        return _buildStudentCard(s);
      },
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> s) {
    final name = s['name'] ?? '-';
    final grade = s['grade'] ?? '-';
    final teacher = s['teacher'] ?? '-';
    final attendance = s['attendance'] ?? 'NONE';
    final hasLog = s['has_log'] == true;
    final absentInfo = s['absent_info'];
    final isCancelled = s['is_cancelled'] == true;

    Color statusColor = Colors.grey;
    String statusText = '미등원';

    if (attendance == 'PRESENT') {
      statusColor = Colors.green;
      statusText = '출석';
    } else if (attendance == 'LATE') {
      statusColor = Colors.orange;
      statusText = '지각';
    } else if (attendance == 'ABSENT') {
      statusColor = Colors.red;
      statusText = '결석';
    } else if (attendance == 'ABSENT_PLANNED') {
      statusColor = Colors.purple;
      statusText = '보강예정'; // or 결석(예정)
    }

    return GestureDetector(
      onTap: () {
        // [FIX] Navigate to Daily Class Log instead of Student Planner
        // Note: Default to SYNTAX subject as data doesn't provide specific subject yet.
        // If not own student, 'TeacherClassLogCreateScreen' basically shows View/Edit.
        // Ideally we should pass 'readonly=true' if we supported it, but user just said "View access".
        final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        context.push(Uri(path: '/teacher/class_log/create', queryParameters: {
          'studentId': s['id'].toString(),
          'studentName': name,
          'date': dateStr,
          'subject': 'SYNTAX',
        }).toString());
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
          border:
              isCancelled ? Border.all(color: Colors.orange.shade200) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Text(grade,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('담당: $teacher',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),

                // Status Chips
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(statusText,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                            hasLog
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 14,
                            color: hasLog ? Colors.blue : Colors.grey),
                        const SizedBox(width: 4),
                        Text(hasLog ? '일지완료' : '일지미작성',
                            style: TextStyle(
                                fontSize: 11,
                                color: hasLog ? Colors.blue : Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            if (absentInfo != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('🔔 $absentInfo',
                    style:
                        TextStyle(fontSize: 12, color: Colors.orange.shade800)),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
