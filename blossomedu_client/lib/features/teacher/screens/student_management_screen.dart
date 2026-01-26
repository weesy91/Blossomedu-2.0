import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart'; // [NEW]
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
  Map<String, dynamic>? _stats; // [NEW]
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
      final results = await Future.wait([
        _academyService.searchStudents(query: query),
        if (query.isEmpty)
          _academyService.getStudentStats()
        else
          Future.value(null),
      ]);

      final data = results[0] as List<dynamic>;
      final stats = results[1] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _students = data;
          if (stats != null) _stats = stats;
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

  Future<void> _uploadExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true, // Important for Web/Bytes access
      );

      if (result != null) {
        setState(() => _isLoading = true);

        final bytes = result.files.single.bytes;
        final name = result.files.single.name;

        if (bytes == null) {
          throw '파일 내용을 읽을 수 없습니다.';
        }

        final res = await _academyService.uploadStudentExcel(bytes, name);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? '업로드 완료')),
          );
          // Show errors if any
          if (res['errors'] != null && (res['errors'] as List).isNotEmpty) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('업로드 경고/에러'),
                content: SingleChildScrollView(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      (res['errors'] as List).map((e) => Text('- $e')).toList(),
                )),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('닫기'))
                ],
              ),
            );
          }
          _fetchStudents(); // Refresh
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 실패: $e')),
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
            icon: const Icon(Icons.upload_file),
            tooltip: '엑셀 일괄 등록',
            onPressed: _uploadExcel,
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
          _buildStatsHeader(), // [NEW]
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

  Widget _buildStatsHeader() {
    if (_stats == null) return const SizedBox.shrink();

    final total = _stats!['total'] ?? 0;
    final breakdown = _stats!['breakdown'] as List? ?? [];

    return Container(
      width: double.infinity,
      color: Colors.indigo.shade50,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('총 재원생 (활성 계정)',
              style: TextStyle(color: Colors.indigo.shade800, fontSize: 12)),
          const SizedBox(height: 4),
          Text('$total명',
              style: TextStyle(
                  color: Colors.indigo.shade900,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          if (breakdown.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: breakdown.map((b) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(b['branch'] ?? '-',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700)),
                      const SizedBox(width: 6),
                      Text('${b['count']}명',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade800)),
                    ],
                  ),
                );
              }).toList(),
            )
          ]
        ],
      ),
    );
  }
}
