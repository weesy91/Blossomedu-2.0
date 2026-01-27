import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = false;

  // Dashboard Data
  List<Map<String, dynamic>> _actionItems = [];
  List<Map<String, dynamic>> _overdueItems = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _academyService.getTeacherDashboard();
      if (!mounted) return;
      setState(() {
        _actionItems = List<Map<String, dynamic>>.from(data['action_required']);
        _overdueItems =
            List<Map<String, dynamic>>.from(data['overdue_assignments']);
        _isLoading = false;
      });
    } catch (e) {
      print('Dashboard Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('관리 현황'),
        elevation: 0,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _fetchDashboardData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Overdue Assignments
                    if (_overdueItems.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            '미제출 과제 (Total: ${_overdueItems.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 140, // Height for cards
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _overdueItems.length,
                          separatorBuilder: (c, i) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final item = _overdueItems[index];
                            return SizedBox(
                              width: 280,
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(
                                        color: Colors.redAccent, width: 1)),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            item['student_name'] ?? '학생',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              item['d_day_label'] ?? 'Overdue',
                                              style: TextStyle(
                                                  color: Colors.red.shade700,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(
                                        item['task_title'] ?? '과제명 없음',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '~ ${item['due_date']}',
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                    ] else ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('미제출된 과제가 없습니다! 🎉',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // 2. Action Required (Log/Absence)
                    if (_actionItems.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.notifications_active,
                              color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            '확인 필요 (Log/Absence)',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _actionItems.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = _actionItems[index];
                          final isError = item['type'] == 'ERROR';
                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: isError
                                        ? Colors.red
                                        : Colors.orange.shade200)),
                            child: ListTile(
                              leading: Icon(
                                  isError
                                      ? Icons.error_outline
                                      : Icons.note_alt_outlined,
                                  color: isError ? Colors.red : Colors.orange),
                              title: Text(item['label'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(item['date'] ?? ''),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  if (isError) return;
                                  // Navigate to Log Create
                                  context.push(Uri(
                                      path: '/teacher/class_log/create',
                                      queryParameters: {
                                        'studentId':
                                            item['student_id'].toString(),
                                        'studentName': item['student_name'],
                                        'date': item['date'],
                                        'subject': item['subject'] ?? 'SYNTAX',
                                      }).toString());
                                },
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white),
                                child: const Text('작성하기'),
                              ),
                            ),
                          );
                        },
                      ),
                    ] else ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('조치할 항목이 없습니다! 👍',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
