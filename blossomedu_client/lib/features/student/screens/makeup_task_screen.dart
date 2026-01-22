import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/services/academy_service.dart';

class MakeupTaskScreen extends StatefulWidget {
  const MakeupTaskScreen({super.key});

  @override
  State<MakeupTaskScreen> createState() => _MakeupTaskScreenState();
}

class _MakeupTaskScreenState extends State<MakeupTaskScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = true;
  List<dynamic> _makeupTasks = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      // Fetch all assignments (current user inferred from token/service)
      // Note: In a real scenario, we might want a dedicated API endpoint for this
      // to avoid fetching ALL history. For now, we fetch recent assignments and filter.
      final allAssignments = await _academyService.getAssignments();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final filtered = allAssignments.where((a) {
        final isCompleted = a['is_completed'] == true ||
            (a['submission'] != null &&
                a['submission']['status'] == 'APPROVED');
        if (isCompleted) return false;

        // Check 7-day rule
        // origin_log_date is the primary source, fallback to start_date or due_date
        String? dateStr =
            a['origin_log_date'] ?? a['start_date'] ?? a['due_date'];
        if (dateStr == null) return false;

        DateTime? baseDate;
        try {
          baseDate = DateTime.parse(dateStr);
        } catch (_) {
          return false;
        }

        // Logic: today >= baseDate + 7 days
        // e.g. Class Jan 1 -> Week 2 starts Jan 8 (Day 8).
        // On Jan 8, it becomes a makeup task.
        final cutoff = baseDate.add(const Duration(days: 7));
        // We compare date parts only
        final cutoffDate = DateTime(cutoff.year, cutoff.month, cutoff.day);

        return today.isAfter(cutoffDate) || today.isAtSameMomentAs(cutoffDate);
      }).toList();

      // Sort by oldest first
      filtered.sort((a, b) {
        final d1 = a['due_date'] ?? '';
        final d2 = b['due_date'] ?? '';
        return d1.compareTo(d2);
      });

      if (mounted) {
        setState(() {
          _makeupTasks = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading makeup tasks: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('보충 학습'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      backgroundColor: Colors.grey.shade50,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _makeupTasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.green.shade200),
                      const SizedBox(height: 16),
                      const Text('밀린 과제가 없습니다!',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('훌륭해요. 이번 주 학습에 집중해보세요.',
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _makeupTasks.length,
                  itemBuilder: (context, index) {
                    return _buildTaskCard(_makeupTasks[index]);
                  },
                ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> item) {
    final title = item['title'] ?? '과제';
    final typeLabel = item['assignment_type'] == 'VOCAB_TEST' ? '단어' : '일반';
    final dueDateStr = item['due_date'];
    String dueDateLabel = '';
    if (dueDateStr != null) {
      try {
        final d = DateTime.parse(dueDateStr);
        dueDateLabel = DateFormat('M/d(E)', 'ko_KR').format(d);
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade100), // Alert color
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            shape: BoxShape.circle,
          ),
          child:
              Icon(Icons.priority_high, color: Colors.red.shade400, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text('$typeLabel · 마감 $dueDateLabel',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        trailing: ElevatedButton(
          onPressed: () async {
            await context.push('/assignment/${item['id']}');
            _fetchData(); // Refresh on return
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade400,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('바로가기'),
        ),
      ),
    );
  }
}
