import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class StudentAssignmentHistoryScreen extends StatefulWidget {
  const StudentAssignmentHistoryScreen({super.key});

  @override
  State<StudentAssignmentHistoryScreen> createState() =>
      _StudentAssignmentHistoryScreenState();
}

class _StudentAssignmentHistoryScreenState
    extends State<StudentAssignmentHistoryScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = true;
  List<dynamic> _completed = [];
  List<dynamic> _incomplete = [];

  @override
  void initState() {
    super.initState();
    _fetchAssignments();
  }

  Future<void> _fetchAssignments() async {
    try {
      final data = await _academyService.getAssignments();
      setState(() {
        _completed = data.where((a) => a['is_completed'] == true).toList();
        _incomplete = data.where((a) => a['is_completed'] != true).toList();

        // Sort by due_date desc
        _completed.sort(
            (a, b) => (b['due_date'] ?? '').compareTo(a['due_date'] ?? ''));
        _incomplete.sort(
            (a, b) => (b['due_date'] ?? '').compareTo(a['due_date'] ?? ''));

        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('지난 과제 확인'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.grey.shade50,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    child: const TabBar(
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.indigo,
                      tabs: [
                        Tab(text: '완료됨'),
                        Tab(text: '미완료/진행중'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildList(_completed, isCompleted: true),
                        _buildList(_incomplete, isCompleted: false),
                      ],
                    ),
                  )
                ],
              ),
            ),
    );
  }

  Widget _buildList(List<dynamic> items, {required bool isCompleted}) {
    if (items.isEmpty) {
      return Center(
        child: Text(isCompleted ? '완료된 과제가 없습니다.' : '진행 중인 과제가 없습니다.',
            style: const TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final title = item['title'] ?? '과제';
        final type = item['assignment_type'] ?? 'MANUAL';
        final due = item['due_date'] ?? '';
        final id = item['id']?.toString() ?? '';
        final status = item['status'] ??
            'PENDING'; // PENDING, SUBMITTED, APPROVED, REJECTED

        Color statusColor = Colors.grey;
        String statusText = '미완료';

        if (isCompleted) {
          statusText = '완료됨';
          statusColor = Colors.green;
        } else {
          if (status == 'REJECTED') {
            statusText = '반려됨 (다시 제출)';
            statusColor = Colors.red;
          } else if (status == 'SUBMITTED') {
            statusText = '제출됨 (검사 대기)';
            statusColor = Colors.blue;
          } else {
            statusText = '미제출';
            statusColor = Colors.grey;
          }
        }

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isCompleted
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              child: Icon(
                  type == 'VOCAB_TEST' ? Icons.text_fields : Icons.camera_alt,
                  color: isCompleted ? Colors.green : Colors.grey,
                  size: 20),
            ),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('기한: ${due.split('T')[0]}'),
                const SizedBox(height: 4),
                Text(statusText,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              context.push('/assignment/$id');
            },
          ),
        );
      },
    );
  }
}
