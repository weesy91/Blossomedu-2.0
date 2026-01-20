import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/services/vocab_service.dart';
import '../../../core/services/academy_service.dart'; // [NEW]
import 'package:intl/intl.dart'; // [NEW]

class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  final AcademyService _academyService = AcademyService();
  final VocabService _vocabService = VocabService();
  int _wordReviewCount = 0;
  int _pendingAssignmentCount = 0; // [NEW] Status
  List<Map<String, dynamic>> _todayClasses = []; // [NEW] Status

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    try {
      // 1. Fetch Word Requests (Pending Corrections)
      final requests = await _vocabService.getTeacherTestRequests(
        pendingOnly: true,
        includeDetails: false,
      );
      final wordCount = requests.length;

      // 2. Fetch Pending Assignments
      // Definition: Assignments that are submitted but not yet Approved?
      // Or Assignments that are incomplete?
      // Let's assume 'Unapproved' means 'Submitted (Pending Review)'.
      // If 'submission' field is not available, we might need to check 'is_completed'.
      // For now, let's fetch all assignments and check logic.
      final assignments = await _academyService.getTeacherAssignments();
      // Filter for submissions with status 'PENDING' if available, otherwise incomplete tasks.
      // Based on typical Serializer, let's look for 'submission' object.
      int assignmentCount = 0;
      for (var task in assignments) {
        // [FIX] Only count submitted but pending review
        final submission = task['submission'];
        if (submission is Map && submission['status'] == 'PENDING') {
          assignmentCount++;
        }
      }
      // 3. Fetch Today's Classes
      final now = DateTime.now();
      final dayCode = DateFormat('E').format(now); // Mon, Tue...
      final students =
          await _academyService.getStudents(day: dayCode, scope: 'my');

      final todayClasses = <Map<String, dynamic>>[];
      for (var s in students) {
        if (s['is_active'] == false) continue; // [NEW] Filter inactive
        // s['class_times'] is a List of {day, start_time, subject...}
        if (s['class_times'] != null) {
          for (var t in s['class_times']) {
            if (t['day'] == dayCode) {
              todayClasses.add({
                'name': s['name'],
                'subject': t['subject'] ?? '수업',
                'time': t['start_time'] ?? '',
                'type': t['type'] ?? 'EXTRA'
              });
            }
          }
        }
      }

      // Sort by time
      todayClasses.sort((a, b) => (a['time'] as String).compareTo(b['time']));

      if (mounted) {
        setState(() {
          _wordReviewCount = wordCount;
          _pendingAssignmentCount = assignmentCount;
          _todayClasses = todayClasses;
        });
      }
    } catch (e) {
      print('Stats Load Error: $e');
      if (mounted) setState(() {});
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
            onPressed: () {
              _fetchStats();
            },
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Teacher Welcome
            Text(
              '$displayName님, 안녕하세요! 👨‍🏫',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // 1. Stats Row
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
                      context.push('/teacher/assignments/pending').then((_) {
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
                      // Navigate and refresh on return
                      context
                          .push('/teacher/word/requests')
                          .then((_) => _fetchStats());
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // 2. Today's Schedule (Horizontal List)
            const Text('오늘의 수업',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 140, // Height for the horizontal cards
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
                          cls['name'], cls['subject'], cls['time'], color);
                    }),
                  // Placeholder for 'add class' removed as it's auto-synced
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 3. Quick Actions
            const Text('빠른 실행',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildFeatureCard(
                  icon: Icons.people_alt,
                  title: '학생 목록',
                  subtitle: '플래너 관리 및 배정',
                  color: Colors.purple,
                  onTap: () => context.push('/teacher/students'),
                ),
                _buildFeatureCard(
                  icon: Icons.book,
                  title: '단어장 관리',
                  subtitle: '엑셀(CSV) 업로드',
                  color: Colors.teal,
                  onTap: () => context.push('/teacher/vocab'),
                ),
                _buildFeatureCard(
                  icon: Icons.analytics_outlined,
                  title: '리포트 전송',
                  subtitle: '월말 보고서 생성',
                  color: Colors.orange,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    ); // Scaffold - BottomNav now handled by TeacherMainScaffold
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

  Widget _buildClassCard(
      String name, String subject, String time, Color color) {
    return Container(
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
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const Spacer(),
          Text(subject,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey.shade700),
              const SizedBox(width: 4),
              Text(time,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
      {required IconData icon,
      required String title,
      required String subtitle,
      required Color color,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const Spacer(),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
