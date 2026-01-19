import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/services/academy_service.dart';
import '../../../core/services/vocab_service.dart'; // [NEW]
import '../../../core/services/announcement_service.dart';
import '../../../core/models/announcement.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AcademyService _academyService = AcademyService();
  final VocabService _vocabService = VocabService(); // [NEW]
  final AnnouncementService _announcementService = AnnouncementService();

  List<dynamic> _assignments = [];
  List<dynamic> _recentHistory = []; // [NEW] Recent submitted/completed
  List<Announcement> _announcements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      // 1. Fetch Assignments
      final assignData = await _academyService.getAssignments();
      final vocabData = await _vocabService.getStudentTestResults(); // [NEW]
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final todayTasks = assignData.where((a) {
        final dueStr = a['due_date']?.toString();
        if (dueStr == null || dueStr.isEmpty) return false;

        final match = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(dueStr);
        if (match == null) return false;
        final datePart = match.group(0)!;
        // 1. Due Today
        if (datePart == todayStr) return true;

        // 2. Overdue AND Incomplete
        // (If submitted, it's not "To-Do" anymore usually, unless rejected?
        // User asked for "Past submission deadline assignments" to be shown in 'Today's Task' section.
        // Assuming incomplete ones.)
        final isCompleted = a['is_completed'] == true;
        if (datePart.compareTo(todayStr) < 0 && !isCompleted) return true;

        return false;
      }).toList();

      // Sort by Due Date Ascending (Oldest/Overdue first)
      todayTasks
          .sort((a, b) => (a['due_date'] ?? '').compareTo(b['due_date'] ?? ''));

      // Filter Recent History (Completed/Submitted, excluding unsubmitted)
      // Logic: is_completed == true OR status == 'SUBMITTED' OR status == 'APPROVED' OR status == 'REJECTED'
      // Basically status != 'PENDING' if we had a status field, but currently we check is_completed and maybe manual check.
      // Let's assume if is_completed is true, it's done.
      // If it's manual assignment, it might be submitted but not approved yet.
      // Let's map 'status' from backend if available, or infer.
      // Looking at `StudentAssignmentHistoryScreen`, we used:
      // _completed = is_completed == true
      // _incomplete = is_completed != true
      // The user wants "Exclude Unsubmitted".
      // So we want: (is_completed == true) OR (status == 'SUBMITTED' || status == 'REJECTED')

      // [NEW] Filter Recent History (Assignments)
      final recentAssignments = assignData.where((a) {
        final isCompleted = a['is_completed'] == true;
        final status = a['status'] ?? 'PENDING';
        if (status == 'PENDING' && !isCompleted) return false;
        return true;
      }).map((a) {
        final submission = a['submission'];
        String sortDate = a['due_date'] ?? '';
        if (submission != null && submission['submitted_at'] != null) {
          sortDate = submission['submitted_at'];
        }
        return {
          ...a,
          'sort_date': sortDate,
          'is_self_study': false,
        };
      }).toList();

      // [NEW] Filter Self-Study Records
      final selfStudy = vocabData.where((r) {
        return r['assignment'] == null; // Only independent tests
      }).map((r) {
        return {
          'id': r['id'],
          'title': '${r['book_title']} - ${r['test_range']}',
          'assignment_type': 'VOCAB_TEST',
          'is_completed': true,
          'status': 'SELF_STUDY',
          'score': r['score'],
          'is_self_study': true,
          'sort_date': r['created_at'] ?? '',
        };
      }).toList();

      // Merge and Sort
      final combinedRecent = [...recentAssignments, ...selfStudy];
      combinedRecent.sort((a, b) {
        final da = a['sort_date']?.toString() ?? '';
        final db = b['sort_date']?.toString() ?? '';
        return db.compareTo(da); // Descending (Newest first)
      });

      final topRecent = combinedRecent.take(5).toList();

      // 2. Fetch Announcements
      final announceData = await _announcementService.getAnnouncements();
      final activeAnnounce = announceData.where((a) => a.isActive).toList();
      activeAnnounce.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final topAnnounce = activeAnnounce.take(5).toList();

      if (mounted) {
        setState(() {
          _assignments = todayTasks;
          _recentHistory = topRecent;
          _announcements = topAnnounce;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching home data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BlossomEdu'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<UserProvider>().logout();
              context.go('/login');
            },
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        onRefresh: _fetchData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Announcements Section
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '공지사항',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_announcements.isNotEmpty) ...[
                      SizedBox(
                        height: 200,
                        child: PageView.builder(
                          itemCount: _announcements.length,
                          itemBuilder: (context, index) {
                            return _buildAnnouncementCard(
                                _announcements[index]);
                          },
                        ),
                      ),
                      if (_announcements.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                                _announcements.length,
                                (index) => Container(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.grey.withOpacity(0.5),
                                      ),
                                    )),
                          ),
                        ),
                    ] else
                      Container(
                        height: 100,
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200)),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_off_outlined,
                                color: Colors.grey),
                            SizedBox(height: 8),
                            Text('등록된 공지사항이 없습니다.',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),

                    // 2. [NEW] Recent Activity (Past assignments)
                    // "지난 과제 확인하기를 버튼을 딱 놓는게 아니고 카드 형식으로 만들어 달라고"
                    _buildRecentHistorySection(),
                    const SizedBox(height: 24),

                    // 3. Today's Tasks
                    const Text(
                      '오늘의 과제 (To-Do)',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.2),
                              width: 1.5),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ]),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: _assignments.isEmpty
                            ? [
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: Column(
                                    children: [
                                      Icon(Icons.check_circle_outline,
                                          size: 48, color: Colors.grey),
                                      SizedBox(height: 12),
                                      Text('오늘 예정된 과제가 없습니다! 🎉',
                                          style: TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                )
                              ]
                            : _assignments
                                .map((a) => _buildTodoItem(a))
                                .toList(),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  // [NEW] Section for Recent History
  Widget _buildRecentHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '최근 학습 기록',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            // "카드 위쪽 우측 상단에 더보기 버튼을 추가"
            TextButton(
              onPressed: () => context.push('/student/assignments/history'),
              child: const Text('더보기 >', style: TextStyle(fontSize: 12)),
            )
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 140, // Horizontal List Height
          child: _recentHistory.isEmpty
              ? Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  alignment: Alignment.center,
                  child: const Text('최근 완료한 과제가 없습니다.',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _recentHistory.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = _recentHistory[index];
                    return _buildHistoryCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(dynamic item) {
    final title = item['title'] ?? '과제';
    final type = item['assignment_type'] ?? 'MANUAL';
    final isCompleted = item['is_completed'] == true;
    final status = item['status'] ?? 'PENDING';

    Color cardColor = Colors.white;
    Color iconColor = Colors.grey;
    String statusText = '';

    if (isCompleted) {
      statusText = '완료됨';
      iconColor = Colors.green;
    } else {
      if (status == 'REJECTED') {
        statusText = '반려됨';
        iconColor = Colors.red;
      } else if (status == 'SUBMITTED') {
        statusText = '검사 대기';
        iconColor = Colors.blue;
      }
    }

    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                type == 'VOCAB_TEST' ? Icons.text_fields : Icons.camera_alt,
                size: 16,
                color: iconColor,
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: iconColor),
              )
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: TextStyle(
                color: iconColor, fontSize: 11, fontWeight: FontWeight.bold),
          )
        ],
      ),
    );
  }

  Widget _buildAnnouncementCard(Announcement item) {
    if (item.image != null && item.image!.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey.shade200,
            image: DecorationImage(
              image: NetworkImage(item.image!),
              fit: BoxFit.cover,
            )),
      );
    }

    // Text Card
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primary.withRed(100)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4)),
            child: const Text('공지사항',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          Text(
            item.title,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            item.content,
            style:
                TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        ],
      ),
    );
  }

  Widget _buildTodoItem(dynamic a) {
    final bool isCompleted = a['is_completed'] == true;
    final String type = a['assignment_type'] ?? 'MANUAL';
    final String title = a['title'] ?? '과제';
    final String id = a['id']?.toString() ?? '';
    final String dueStr = a['due_date']?.toString() ?? '';

    // Check Overdue
    bool isOverdue = false;
    if (dueStr.isNotEmpty && !isCompleted) {
      final dueDate = DateTime.parse(dueStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (dueDay.isBefore(today)) isOverdue = true;
    }

    final typeIcon = type == 'VOCAB_TEST' ? '📝' : '📷';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: isOverdue ? Colors.red.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isOverdue ? Colors.red.shade200 : Colors.grey.shade200)),
      child: ListTile(
        leading: Icon(
          isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isCompleted
              ? Colors.green
              : (isOverdue ? Colors.red : Colors.grey),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text('$typeIcon $title',
                  style: TextStyle(
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      color: isCompleted
                          ? Colors.grey
                          : (isOverdue ? Colors.red.shade900 : Colors.black87),
                      fontWeight:
                          isOverdue ? FontWeight.bold : FontWeight.w500)),
            ),
            if (isOverdue)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: const Text('미제출',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              )
          ],
        ),
        subtitle: isOverdue
            ? Text('기한: ${dueStr.split('T')[0]}',
                style: const TextStyle(color: Colors.red, fontSize: 12))
            : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        onTap: isCompleted ? null : () => context.push('/assignment/$id'),
      ),
    );
  }
}
