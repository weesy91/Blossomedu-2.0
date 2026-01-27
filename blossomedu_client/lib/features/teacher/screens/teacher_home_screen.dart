import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/services/vocab_service.dart';
import '../../../core/services/academy_service.dart'; // [NEW]
import 'package:intl/intl.dart'; // [NEW]

class TeacherHomeScreen extends StatefulWidget {
  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  final AcademyService _academyService = AcademyService();
  final VocabService _vocabService = VocabService();

  bool _isLoading = false;
  int _wordReviewCount = 0;
  int _pendingAssignmentCount = 0;
  List<Map<String, dynamic>> _todayClasses = [];

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // 1. Fetch Existing Stats (Keep them for top cards)
      final requests = await _vocabService.getTeacherTestRequests(
        pendingOnly: true,
        includeDetails: false,
      );
      final wordCount = requests.length;

      final assignments = await _academyService.getTeacherAssignments();
      int assignmentCount = 0;
      for (var task in assignments) {
        final submission = task['submission'];
        if (submission is Map && submission['status'] == 'PENDING') {
          assignmentCount++;
        }
      }

      // 2. Fetch Dashboard Data (Removed)

      // 3. Fetch Today's Classes
      final now = DateTime.now();
      final dayCode = DateFormat('E').format(now);
      final students =
          await _academyService.getStudents(day: dayCode, scope: 'my');

      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final todayClasses = <Map<String, dynamic>>[];

      for (var s in students) {
        if (s['is_active'] == false) continue;
        final tempSchedules = s['temp_schedules'] as List<dynamic>? ?? [];

        // 1. Regular Classes
        if (s['class_times'] != null) {
          for (var t in s['class_times']) {
            if (t['day'] == dayCode) {
              bool isCancelled = false;
              for (var ts in tempSchedules) {
                if (ts['original_date'] == dateStr &&
                    ts['is_extra_class'] == false) {
                  isCancelled = true;
                  break;
                }
              }
              if (!isCancelled) {
                todayClasses.add({
                  'studentId': s['id'],
                  'name': s['name'],
                  'subject': t['subject'] ?? '수업',
                  'time': t['start_time'] ?? '',
                  'type': t['type'] ?? 'EXTRA'
                });
              }
            }
          }
        }

        // 2. Add Make-up/Moved Classes
        for (var ts in tempSchedules) {
          if (ts['new_date'] == dateStr) {
            String startTime = ts['new_start_time'] ?? '';
            if (startTime.length > 5) startTime = startTime.substring(0, 5);

            final subjectCode = ts['subject'] ?? 'EXTRA';
            final subjectLabel = _getSubjectLabel(subjectCode);
            final isExtra = ts['is_extra_class'] == true;

            todayClasses.add({
              'studentId': s['id'],
              'name': s['name'],
              'subject': '$subjectLabel ${isExtra ? "(보강)" : "(이동)"}',
              'time': startTime,
              'type': subjectCode
            });
          }
        }
      }

      todayClasses.sort((a, b) => (a['time'] as String).compareTo(b['time']));

      if (mounted) {
        setState(() {
          _wordReviewCount = wordCount;
          _pendingAssignmentCount = assignmentCount;
          _todayClasses = todayClasses;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Stats Load Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    final rawName = user?.name ?? '';
    final displayName =
        rawName.trim().isNotEmpty ? rawName : (user?.username ?? '선생님');

    return Scaffold(
      appBar: AppBar(
        title: const Text('BlossomEdu (선생님)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchStats,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<UserProvider>().logout();
              context.go('/login');
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Message
                  Text(
                    '$displayName님, 안녕하세요! 👨‍🏫',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),

                  // 1. Stats Row (Pending / Review)
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          title: '미승인 과제',
                          count: '$_pendingAssignmentCount',
                          color: Colors.redAccent,
                          icon: Icons.assignment_late_outlined,
                          onTap: () {
                            context
                                .push('/teacher/assignments/pending')
                                .then((_) {
                              _fetchStats();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          title: '단어 채점 대기',
                          count: '$_wordReviewCount',
                          color: Colors.orange,
                          icon: Icons.spellcheck,
                          onTap: () {
                            context
                                .push('/teacher/word/requests')
                                .then((_) => _fetchStats());
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // 2. Today's Classes
                  const Text('오늘의 수업',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 140,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        if (_todayClasses.isEmpty)
                          Container(
                            width: 200,
                            alignment: Alignment.center,
                            child: Text('오늘 예정된 수업이 없습니다.',
                                style: TextStyle(color: Colors.grey.shade500)),
                          )
                        else
                          ..._todayClasses.map((cls) {
                            Color color;
                            switch (cls['type']) {
                              case 'SYNTAX':
                                color = Colors.blue;
                                break;
                              case 'READING':
                                color = Colors.purple;
                                break;
                              default:
                                color = Colors.green;
                            }
                            return _buildClassCard(
                              name: cls['name'],
                              subject: cls['subject'],
                              time: cls['time'],
                              color: color,
                              onTap: () {
                                final studentId = cls['studentId'];
                                final subjectType = cls['type'] ?? 'SYNTAX';
                                final dateStr = DateFormat('yyyy-MM-dd')
                                    .format(DateTime.now());
                                context.push(
                                  '/teacher/class_log/create?studentId=$studentId&date=$dateStr&subject=$subjectType',
                                );
                              },
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 3. Action Required Boards (Moved to Student List)
                  // _buildDashboardSection(context),

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  String _getSubjectLabel(String code) {
    switch (code) {
      case 'SYNTAX':
        return '구문';
      case 'READING':
        return '독해';
      case 'GRAMMAR':
        return '어법';
      default:
        return code;
    }
  }

  Widget _buildStatCard(BuildContext context,
      {required String title,
      required String count,
      required Color color,
      required IconData icon,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 28),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(count,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildClassCard({
    required String name,
    required String subject,
    required String time,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: color.withOpacity(0.2),
                  child: Text(name[0],
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const Spacer(),
            Text(subject,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                Text(time,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
