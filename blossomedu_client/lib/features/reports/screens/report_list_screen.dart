import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';
import '../../../core/services/academy_service.dart';

class ReportListScreen extends StatefulWidget {
  const ReportListScreen({super.key});

  @override
  State<ReportListScreen> createState() => _ReportListScreenState();
}

class _ReportListScreenState extends State<ReportListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final AcademyService _academyService = AcademyService();

  bool _isLoading = false;
  List<dynamic> _students = [];
  List<dynamic> _filteredStudents = [];
  List<dynamic> _reports = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchStudents();
    _fetchReports();
  }

  Future<void> _fetchStudents() async {
    setState(() => _isLoading = true);
    try {
      final data = await _academyService.getStudents();
      setState(() {
        _students = data;
        _filteredStudents = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchReports() async {
    // Fetch recent reports
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final url = Uri.parse('${AppConfig.baseUrl}/academy/api/v1/reports/');
      final response = await http.get(url, headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      });

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));
        List<dynamic> data = [];

        if (decoded is List) {
          data = decoded;
        } else if (decoded is Map && decoded.containsKey('results')) {
          data = decoded['results'] ?? [];
        }

        if (mounted) {
          setState(() {
            _reports = data;
          });
        }
      }
    } catch (e) {
      print('Error fetching reports: $e');
    }
  }

  void _filterStudents(String query) {
    if (query.isEmpty) {
      setState(() => _filteredStudents = _students);
    } else {
      setState(() {
        _filteredStudents = _students.where((s) {
          final name = s['name'].toString().toLowerCase();
          final school = (s['school_name'] ?? '').toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              school.contains(query.toLowerCase());
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('성적표 발송 및 관리'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '학생 선택 (발송)'),
            Tab(text: '발송 이력'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStudentListTab(),
          _buildReportHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildStudentListTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: '학생 이름 또는 학교 검색',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: _filterStudents,
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _filteredStudents.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = _filteredStudents[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(s['name'][0]),
                      ),
                      title: Text(s['name']),
                      subtitle: Text(
                          '${s['school_name'] ?? '-'} | ${s['grade'] ?? '-'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        // Go to Create Screen
                        context.push('/teacher/report/create', extra: s);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReportHistoryTab() {
    if (_reports.isEmpty) {
      return const Center(child: Text('발송된 성적표가 없습니다.'));
    }
    return ListView.builder(
      itemCount: _reports.length,
      itemBuilder: (context, index) {
        final r = _reports[index];
        final studentName = r['student_name'] ?? '학생';
        final title = r['title'] ?? '성적표';
        final date = r['created_at'] != null
            ? DateFormat('yyyy.MM.dd').format(DateTime.parse(r['created_at']))
            : '-';

        return ListTile(
          title: Text('[$studentName] $title'),
          subtitle: Text('발행일: $date'),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () {
              // Open Web View
              context.push('/report/${r['uuid']}', extra: {'is_preview': true});
            },
          ),
          onTap: () {
            // Maybe edit? or view detail?
            // For now view
            context.push('/report/${r['uuid']}', extra: {'is_preview': true});
          },
        );
      },
    );
  }
}
