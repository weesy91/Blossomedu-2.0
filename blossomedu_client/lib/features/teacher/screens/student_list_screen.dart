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

  // Collapse State
  bool _isActionExpanded = true;
  bool _isOverdueExpanded = true;

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

  Widget _buildSectionHeader({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  '$title (Total: $count)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
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
                    // 1. Action Required (Log/Absence) - Moved to Top
                    _buildSectionHeader(
                      title: '확인 필요 (Log/Absence)',
                      count: _actionItems.length,
                      icon: Icons.notifications_active,
                      color: Colors.orange,
                      isExpanded: _isActionExpanded,
                      onToggle: () => setState(
                          () => _isActionExpanded = !_isActionExpanded),
                    ),
                    if (_isActionExpanded) ...[
                      const SizedBox(height: 12),
                      if (_actionItems.isNotEmpty)
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
                                    color:
                                        isError ? Colors.red : Colors.orange),
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
                                          'subject':
                                              item['subject'] ?? 'SYNTAX',
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
                        )
                      else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text('조치할 항목이 없습니다! 👍',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      const SizedBox(height: 32),
                    ],

                    // 2. Overdue Assignments
                    _buildSectionHeader(
                      title: '미제출 과제',
                      count: _overdueItems.length,
                      icon: Icons.warning_amber_rounded,
                      color: Colors.red,
                      isExpanded: _isOverdueExpanded,
                      onToggle: () => setState(
                          () => _isOverdueExpanded = !_isOverdueExpanded),
                    ),
                    if (_isOverdueExpanded) ...[
                      const SizedBox(height: 12),
                      if (_overdueItems.isNotEmpty)
                        ListView.separated(
                          shrinkWrap: true, // Allow it to perform inside Column
                          physics:
                              const NeverScrollableScrollPhysics(), // Scroll with whole page
                          itemCount: _overdueItems.length,
                          separatorBuilder: (c, i) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = _overdueItems[index];
                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                      color: Colors.redAccent, width: 1)),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                item['student_name'] ?? '학생',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  item['d_day_label'] ??
                                                      'Overdue',
                                                  style: TextStyle(
                                                      color:
                                                          Colors.red.shade700,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            item['task_title'] ?? '과제명 없음',
                                            style:
                                                const TextStyle(fontSize: 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '~ ${item['due_date']}',
                                            style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('과제 제출 인정'),
                                            content: const Text(
                                                '해당 과제를 선생님 권한으로\n[제출 완료] 처리하시겠습니까?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => context.pop(),
                                                child: const Text('취소'),
                                              ),
                                              TextButton(
                                                onPressed: () async {
                                                  context.pop(); // Close Dialog
                                                  try {
                                                    await _academyService
                                                        .completeAssignment(
                                                            item['id']);
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              const SnackBar(
                                                                  content: Text(
                                                                      '완료 처리되었습니다.')));
                                                    }
                                                    _fetchDashboardData();
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(SnackBar(
                                                              content: Text(
                                                                  '오류 발생: $e')));
                                                    }
                                                  }
                                                },
                                                child: const Text('확인'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.amber,
                                        foregroundColor: Colors.black87,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text('제출인정',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      else
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text('미제출된 과제가 없습니다! 🎉',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
