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
      final vocabData = await _vocabService.getStudentTestResults(
          includeDetails: true); // [NEW]
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
        // (If submitted, it's not "To-Do" anymore usually, unless rejected?)
        // [MODIFIED] Filter out "Makeup Tasks" (older than 7 days)
        final isCompleted = a['is_completed'] == true;
        if (datePart.compareTo(todayStr) < 0 && !isCompleted) {
          // Check if it's a makeup task (Day 8+)
          String? originDateStr =
              a['origin_log_date'] ?? a['start_date'] ?? a['due_date'];
          if (originDateStr != null) {
            try {
              final baseDate = DateTime.parse(originDateStr);
              final cutoff = baseDate.add(const Duration(days: 7));
              final cutoffDate =
                  DateTime(cutoff.year, cutoff.month, cutoff.day);

              // If today >= cutoffDate (Day 8+), it's a makeup task -> HIDE from Home
              if (today.isAfter(cutoffDate) ||
                  today.isAtSameMomentAs(cutoffDate)) {
                return false;
              }
            } catch (_) {}
          }
          return true; // Overdue but recent (Day 2~7)
        }

        return false;
      }).toList();

      // Sort by Due Date Ascending (Oldest/Overdue first)
      todayTasks
          .sort((a, b) => (a['due_date'] ?? '').compareTo(b['due_date'] ?? ''));

      // 2. Fetch Announcements
      final announceData = await _announcementService.getAnnouncements();
      final activeAnnounce = announceData.where((a) => a.isActive).toList();
      activeAnnounce.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final topAnnounce = activeAnnounce.take(5).toList();

      // [NEW] Process Vocab Tests (Source of Truth for Words)
      final vocabHistory = vocabData.map((r) {
        final score = r['score'] ?? 0;
        final details = r['details'] as List<dynamic>? ?? [];
        final pendingCount = details
            .where((d) =>
                d['is_correction_requested'] == true &&
                d['is_resolved'] == false)
            .length;

        bool hasPendingCorrection = pendingCount > 0;
        if (!hasPendingCorrection) {
          final pendingCountRaw = r['pending_count'] ?? r['pendingCount'];
          if (pendingCountRaw is num) {
            hasPendingCorrection = pendingCountRaw > 0;
          } else if (pendingCountRaw is String) {
            final parsed = int.tryParse(pendingCountRaw);
            if (parsed != null) hasPendingCorrection = parsed > 0;
          }
        }
        if (!hasPendingCorrection) {
          final pendingRaw = r['pending'] ?? r['is_pending'];
          if (pendingRaw == true ||
              pendingRaw?.toString().toLowerCase() == 'true') {
            hasPendingCorrection = true;
          }
        }
        if (!hasPendingCorrection) {
          final statusRaw = r['status']?.toString().toUpperCase();
          if (statusRaw == 'PENDING' || statusRaw == 'REVIEWING') {
            hasPendingCorrection = true;
          }
        }

        // Check status
        final wrongCount = r['wrong_count'] ?? 0;
        final totalCount = score + wrongCount;
        final threshold = totalCount > 0 ? totalCount * 0.9 : 0;

        // Status Logic
        String status = 'COMPLETED'; // Default
        if (hasPendingCorrection) {
          status = 'REVIEWING';
        } else if (score < threshold) {
          status = 'FAIL';
        } else {
          status = 'PASS';
        }

        return {
          'id': r['id'],
          'title': '${r['book_title']} - ${r['test_range']}',
          'assignment_type': 'VOCAB_TEST',
          'is_completed': status == 'PASS', // For UI check
          'status': status,
          'score': score,
          'total': totalCount, // [NEW] Total Questions
          'is_self_study': r['assignment'] == null,
          'sort_date': r['created_at'] ?? '',
          // [NEW] Details for Result Screen
          'test_id': r['test_id'] ?? r['id'], // Ensure testId is passed
          'answers': details.map((d) {
            return {
              'question': d['word']?.toString() ?? '',
              'user_input': d['user_input']?.toString() ?? '',
              'answer': d['answer']?.toString() ?? '',
              'is_correct': d['is_correct']?.toString() ?? 'false',
            };
          }).toList(),
          'wrongWords': details
              .where((d) => d['is_correct'] != true)
              .map((d) => {
                    'id': d['word_id'] ?? 0,
                    'word': d['word'] ?? '',
                    'meaning': d['answer'] ?? '',
                  })
              .toList(),
        };
      }).toList();

      // [NEW] Process Assignments (Excluding Vocab Tests)
      final assignmentHistory = assignData.where((a) {
        final type = a['assignment_type'];
        if (type == 'VOCAB_TEST') return false; // Handled by vocabData

        final isCompleted = a['is_completed'] == true;
        final submission = a['submission'];

        if (isCompleted) return true;
        if (submission != null) return true; // Submitted (Pending/Rejected)
        return false;
      }).map((a) {
        final submission = a['submission'];
        String sortDate = a['due_date'] ?? '';
        if (submission is Map && submission['submitted_at'] != null) {
          sortDate = submission['submitted_at'];
        }
        final submissionStatus = submission is Map
            ? (submission['status'] ?? a['status'])
            : a['status'];
        return {
          ...a,
          'sort_date': sortDate,
          'status': 'ASSIGNMENT', // Marker
          'submission_status': submissionStatus,
        };
      }).toList();

      // Merge and Sort
      final combinedRecent = [...vocabHistory, ...assignmentHistory];
      combinedRecent.sort((a, b) {
        final da = a['sort_date']?.toString() ?? '';
        final db = b['sort_date']?.toString() ?? '';
        return db.compareTo(da);
      });

      final topRecent = combinedRecent.take(5).toList();

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
        SizedBox(
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
    final submissionStatus = item['submission_status'];
    final normalizedSubmissionStatus =
        submissionStatus?.toString().toUpperCase();
    final status = item['status']; // [NEW]

    Color cardColor = Colors.white;
    Color iconColor = Colors.grey;
    String statusText = '';

    // [NEW] Explicit Status Logic from _fetchData
    if (status == 'PASS') {
      statusText = '완료';
      iconColor = Colors.green;
    } else if (status == 'FAIL') {
      statusText = '불통';
      iconColor = Colors.red;
    } else if (status == 'REVIEWING') {
      statusText = '검토중';
      iconColor = Colors
          .orange; // Changed from Blue to Orange as per user preference (or consistent with Review)
    } else if (status == 'SELF_STUDY') {
      // Should be covered by PASS/FAIL if we processed it in _fetchData,
      // but if we look at _fetchData, vocabHistory covers self-study too and sets PASS/FAIL/REVIEWING.
      // So this might be redundant, but good fallback.
      statusText = '자율 학습';
      iconColor = Colors.blueGrey;
    } else {
      // Fallback for Assignments (Manual/Photo)
      if (isCompleted ||
          normalizedSubmissionStatus == 'APPROVED' ||
          normalizedSubmissionStatus == 'ACCEPTED') {
        statusText = '인증 완료';
        iconColor = Colors.green;
      } else if (normalizedSubmissionStatus == 'REJECTED') {
        statusText = '반려';
        iconColor = Colors.red;
      } else if (normalizedSubmissionStatus == 'PENDING' ||
          normalizedSubmissionStatus == 'SUBMITTED') {
        statusText = '검토중'; // Updated to '검토중' to be consistent
        iconColor = Colors.orange;
      } else {
        statusText = '미완료';
        iconColor = Colors.grey;
      }
    }

    return InkWell(
      onTap: () {
        if (type == 'VOCAB_TEST') {
          // [MODIFIED] Show Popup Dialog instead of Navigation
          showDialog(
            context: context,
            builder: (dialogContext) =>
                _buildVocabResultDialog(dialogContext, item),
          );
        } else {
          // Navigate to Assignment Detail
          context.push('/assignment/${item['id']}');
        }
      },
      child: Container(
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
      ),
    );
  }

  // [NEW] Vocab Result Popup
  Widget _buildVocabResultDialog(BuildContext context, dynamic item) {
    final int score = item['score'] ?? 0;
    final int total = item['total'] ?? 0;
    final String status = item['status'] ?? 'COMPLETED';
    final bool isPassed = status == 'PASS';
    final List<dynamic> answers = item['answers'] ?? [];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Icon(
              isPassed ? Icons.emoji_events : Icons.sentiment_dissatisfied,
              size: 48,
              color: isPassed ? Colors.amber : Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              isPassed ? 'Test Passed!' : 'Try Again...',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '$score / $total',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isPassed ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),

            // List
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: answers.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final a = answers[index];
                  final bool isCorrect =
                      a['is_correct'] == 'true' || a['is_correct'] == true;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      isCorrect ? Icons.check_circle : Icons.cancel,
                      color: isCorrect ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    title: Text(a['question'] ?? ''),
                    subtitle: Text(
                      '답: ${a['user_input']} / 정답: ${a['answer']}',
                      style: TextStyle(
                        color: isCorrect ? Colors.grey : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('닫기'),
              ),
            ),
          ],
        ),
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

    // [NEW] Check submission status
    final submission = a['submission'];
    String? submissionStatus;
    if (submission is Map) {
      submissionStatus = submission['status']?.toString().toUpperCase();
    }
    final bool isPending = submissionStatus == 'PENDING';
    final bool isRejected = submissionStatus == 'REJECTED';
    final bool isApproved = submissionStatus == 'APPROVED';

    // Check Overdue (only if no submission yet)
    bool isOverdue = false;
    if (dueStr.isNotEmpty && !isCompleted && !isPending && !isApproved) {
      final dueDate = DateTime.parse(dueStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (dueDay.isBefore(today)) isOverdue = true;
    }

    final typeIcon = type == 'VOCAB_TEST' ? '📝' : '📷';

    // Determine badge
    String? badgeText;
    Color badgeColor = Colors.red;
    if (isPending) {
      badgeText = '검토중';
      badgeColor = Colors.orange;
    } else if (isRejected) {
      badgeText = '반려';
      badgeColor = Colors.red;
    } else if (isOverdue) {
      badgeText = '미제출';
      badgeColor = Colors.red;
    }

    // Determine colors
    Color bgColor = Colors.grey.shade50;
    Color borderColor = Colors.grey.shade200;
    Color textColor = Colors.black87;
    Color iconColor = Colors.grey;

    if (isPending) {
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      textColor = Colors.orange.shade900;
      iconColor = Colors.orange;
    } else if (isRejected || isOverdue) {
      bgColor = Colors.red.shade50;
      borderColor = Colors.red.shade200;
      textColor = Colors.red.shade900;
      iconColor = Colors.red;
    } else if (isCompleted || isApproved) {
      iconColor = Colors.green;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor)),
      child: ListTile(
        leading: Icon(
          isCompleted || isApproved
              ? Icons.check_circle
              : (isPending
                  ? Icons.hourglass_top
                  : Icons.radio_button_unchecked),
          color: iconColor,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text('$typeIcon $title',
                  style: TextStyle(
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      color: isCompleted ? Colors.grey : textColor,
                      fontWeight: (isOverdue || isRejected)
                          ? FontWeight.bold
                          : FontWeight.w500)),
            ),
            if (badgeText != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: badgeColor, borderRadius: BorderRadius.circular(4)),
                child: Text(badgeText,
                    style: const TextStyle(
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
        onTap: isCompleted
            ? null
            : () async {
                await context.push('/assignment/$id');
                _fetchData();
              },
      ),
    );
  }
}
