import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class TeacherPendingAssignmentsScreen extends StatefulWidget {
  const TeacherPendingAssignmentsScreen({super.key});

  @override
  State<TeacherPendingAssignmentsScreen> createState() =>
      _TeacherPendingAssignmentsScreenState();
}

class _TeacherPendingAssignmentsScreenState
    extends State<TeacherPendingAssignmentsScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = true;
  List<dynamic> _pendingList = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final assignments = await _academyService.getTeacherAssignments();
      final pending = <dynamic>[];

      for (var task in assignments) {
        final submission = task['submission'];
        if (submission is Map && submission['status'] == 'PENDING') {
          pending.add(task);
        }
      }

      // Sort by submitted_at (oldest first? or newest?)
      // Usually user wants to see oldest pending first? Or newest.
      // Let's sort by submitted_at ascending (oldest first).
      pending.sort((a, b) {
        final t1Str = a['submission']['submitted_at']?.toString();
        final t2Str = b['submission']['submitted_at']?.toString();
        if (t1Str == null) return 1;
        if (t2Str == null) return -1;
        return t1Str.compareTo(t2Str);
      });

      if (mounted) {
        setState(() {
          _pendingList = pending;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로딩 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('미승인 과제 목록'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.green.shade200),
                      const SizedBox(height: 16),
                      Text('모든 과제가 처리되었습니다!',
                          style: TextStyle(
                              fontSize: 18, color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pendingList.length,
                  itemBuilder: (context, index) {
                    final item = _pendingList[index];
                    return _buildPendingCard(item);
                  },
                ),
    );
  }

  Widget _buildPendingCard(Map<String, dynamic> item) {
    final title = item['title'] ?? '과제';
    final studentName = item['student_name'] ?? '학생';
    final submission = item['submission'] as Map<String, dynamic>;
    final submittedAt = submission['submitted_at']?.toString() ?? '';

    // Calculate time elapsed
    String timeAgo = '';
    if (submittedAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(submittedAt);
        final diff = DateTime.now().difference(dt);
        if (diff.inDays > 0) {
          timeAgo = '${diff.inDays}일 전';
        } else if (diff.inHours > 0) {
          timeAgo = '${diff.inHours}시간 전';
        } else {
          timeAgo = '방금 전';
        }
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade100),
      ),
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade50,
          child: const Icon(Icons.assignment_late, color: Colors.orange),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(studentName,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black87)),
                ),
                const SizedBox(width: 8),
                if (timeAgo.isNotEmpty)
                  Text(timeAgo,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.redAccent)),
              ],
            ),
          ],
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            context
                .push('/teacher/assignment/review/${item['id']}')
                .then((_) => _fetchData());
          },
          child: const Text('검토'),
        ),
      ),
    );
  }
}
