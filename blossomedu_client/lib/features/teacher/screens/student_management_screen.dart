import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';
import 'dart:async';

class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  final _academyService = AcademyService();
  final _searchController = TextEditingController();

  List<dynamic> _students = [];
  bool _isLoading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchStudents(query: _searchController.text);
    });
  }

  Future<void> _fetchStudents({String query = ''}) async {
    setState(() => _isLoading = true);
    try {
      final data = await _academyService.searchStudents(query: query);
      if (mounted) {
        setState(() {
          _students = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로딩 실패: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('학생 계정 관리'),
        actions: [
          IconButton(
            onPressed: () => context.push('/teacher/student/log-search'),
            icon: const Icon(Icons.manage_search),
            tooltip: '학생 로그 검색',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/teacher/student/register'); // Existing Registration
        },
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '이름, 아이디 검색...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _students.isEmpty
                    ? const Center(child: Text('검색 결과가 없습니다.'))
                    : ListView.separated(
                        itemCount: _students.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final student = _students[index];
                          final name = student['name'] ?? '이름 없음';
                          final firstChar = name.isNotEmpty ? name[0] : '?';
                          final isActive = student['is_active'] ?? true;

                          return ListTile(
                            tileColor: isActive
                                ? null
                                : Colors.grey[200], // [NEW] Gray background
                            leading: CircleAvatar(
                              backgroundColor: isActive
                                  ? null
                                  : Colors.grey, // [NEW] Gray avatar
                              child: Text(firstChar,
                                  style: TextStyle(
                                      color: isActive ? null : Colors.white)),
                            ),
                            title: Text(
                              '$name (${student['grade_display'] ?? '-'})',
                              style: TextStyle(
                                color: isActive
                                    ? Colors.black
                                    : Colors.grey, // [NEW] Gray text
                                decoration: isActive
                                    ? null
                                    : TextDecoration
                                        .lineThrough, // Optional: strikethrough
                              ),
                            ),
                            subtitle: Text(
                              '${student['school_name'] ?? '학교 미정'} | ${student['username']}',
                              style: TextStyle(
                                  color:
                                      isActive ? Colors.black54 : Colors.grey),
                            ),
                            trailing: Icon(Icons.chevron_right,
                                color: isActive ? null : Colors.grey),
                            onTap: () async {
                              await context.push(
                                  '/teacher/management/students/${student['id']}');
                              _fetchStudents(
                                  query: _searchController
                                      .text); // Refresh list on return
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
