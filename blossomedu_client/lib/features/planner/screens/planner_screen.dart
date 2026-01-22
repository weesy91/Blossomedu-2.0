import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart'; // [NEW]
import '../../../core/constants.dart';
import '../../../core/services/academy_service.dart';
import '../../../core/providers/user_provider.dart'; // [NEW]

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final AcademyService _academyService = AcademyService();
  final ScrollController _timelineScrollController = ScrollController();
  bool _isLoading = true;
  List<dynamic> _assignments = [];
  List<dynamic> _classTimes = []; // [NEW]
  List<dynamic> _tempSchedules = []; // [NEW]

  // Timeline State
  late DateTime _startDate;
  late List<DateTime> _weekDates;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _initializeDates();
    // Fetch data after build to access Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  @override
  void dispose() {
    _timelineScrollController.dispose();
    super.dispose();
  }

  void _initializeDates() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 7));
    _startDate = DateTime(start.year, start.month, start.day);
    _weekDates = List.generate(15, (i) => _startDate.add(Duration(days: i)));
    final today = DateTime(now.year, now.month, now.day);
    _selectedDate = today;
  }

  Future<void> _fetchData() async {
    try {
      final userProvider = context.read<UserProvider>();
      final user = userProvider.user;
      if (user == null) {
        if (userProvider.isLoading) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (mounted) {
            return _fetchData();
          }
          return;
        }
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final studentId = user.studentId ?? user.id;
      final assignmentList =
          await _academyService.getAssignments(studentId: studentId);
      Map<String, dynamic>? studentDetail;
      try {
        studentDetail = await _academyService.getStudent(studentId);
      } catch (e) {
        print('Error loading student detail: $e');
      }

      if (mounted) {
        final tempSchedules = studentDetail?['temp_schedules'];
        setState(() {
          _assignments = assignmentList;
          _classTimes = studentDetail?['class_times'] ?? [];
          _tempSchedules = tempSchedules is List ? tempSchedules : [];
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToToday();
        });
        _calculateMakeupCount(); // [NEW]
        // [DEBUG] Log class_times data
        print('=== PLANNER DEBUG ===');
        print('Fetched ${_classTimes.length} class times');
        if (_classTimes.isNotEmpty) {
          print('Sample class_time: ${_classTimes.first}');
        }
        print('====================');
      }
    } catch (e) {
      print('Error loading planner data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToToday() {
    if (!_timelineScrollController.hasClients) return;
    final now = DateTime.now();
    final todayIndex = _weekDates.indexWhere((d) => _isSameDay(d, now));
    if (todayIndex == -1) return;
    final offset = (todayIndex * 90.0);
    _timelineScrollController.jumpTo(offset);
  }

  // Helper to check same day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime? _parseDateOnly(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    DateTime? parsed;
    try {
      parsed = DateTime.parse(raw);
    } catch (_) {
      try {
        parsed = DateFormat('yyyy-MM-dd HH:mm:ss').parse(raw);
      } catch (_) {
        return null;
      }
    }
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    return DateTime(local.year, local.month, local.day);
  }

  String _formatTimeShort(dynamic value) {
    if (value == null) return '';
    final raw = value.toString();
    if (raw.isEmpty) return '';
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  String _extractTime(dynamic value) {
    if (value == null) return '';
    final raw = value.toString();
    if (raw.isEmpty) return '';
    final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(raw);
    return match?.group(1) ?? '';
  }

  // Helper to map weekday string/int to DateTime weekday
  bool _isClassDay(String dayStr, DateTime date) {
    // Backend formats: 'Mon', 'Tue' OR 'Monday', 'Tuesday' OR '월', '화'
    // DateTime.weekday: 1 (Mon) -> 7 (Sun)
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final fullDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final koreanDays = ['월', '화', '수', '목', '금', '토', '일'];

    int targetWeekday = -1;

    if (days.contains(dayStr)) {
      targetWeekday = days.indexOf(dayStr) + 1;
    } else if (fullDays.contains(dayStr)) {
      targetWeekday = fullDays.indexOf(dayStr) + 1;
    } else if (koreanDays.contains(dayStr)) {
      targetWeekday = koreanDays.indexOf(dayStr) + 1;
    }

    return date.weekday == targetWeekday;
  }

  String _subjectLabel(String? code) {
    switch ((code ?? '').toUpperCase()) {
      case 'SYNTAX':
        return '\uAD6C\uBB38';
      case 'READING':
        return '\uB3C5\uD574';
      case 'GRAMMAR':
        return '\uBB38\uBC95';
      default:
        return code ?? '';
    }
  }

  String _normalizeSubjectCode(String? raw) {
    if (raw == null) return '';
    final trimmed = raw.toString().trim();
    if (trimmed.isEmpty) return '';
    final upper = trimmed.toUpperCase();
    if (upper.contains('SYNTAX')) return 'SYNTAX';
    if (upper.contains('READING')) return 'READING';
    if (upper.contains('GRAMMAR')) return 'GRAMMAR';
    if (trimmed.contains('\uAD6C\uBB38')) return 'SYNTAX';
    if (trimmed.contains('\uB3C5\uD574')) return 'READING';
    if (trimmed.contains('\uBB38\uBC95')) return 'GRAMMAR';
    return upper;
  }

  String _extractTeacherName(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is Map) {
      final keys = [
        'name',
        'full_name',
        'display_name',
        'teacher_name',
        'username'
      ];
      for (final key in keys) {
        final candidate = value[key]?.toString().trim();
        if (candidate != null && candidate.isNotEmpty) return candidate;
      }
      return '';
    }
    if (value is num) return '';
    return value.toString().trim();
  }

  String _resolveTeacherNameForTempSchedule(Map<String, dynamic> ts) {
    final direct = _extractTeacherName(
        ts['teacher_name'] ?? ts['teacher_display'] ?? ts['teacher']);
    if (direct.isNotEmpty) return direct;
    final subjectCode = _normalizeSubjectCode(ts['subject']?.toString());
    if (subjectCode.isEmpty) return '';
    for (final ct in _classTimes) {
      final ctSubjectCode = _normalizeSubjectCode(ct['subject']?.toString());
      if (ctSubjectCode != subjectCode) continue;
      final teacher = _extractTeacherName(ct['teacher_name'] ?? ct['teacher']);
      if (teacher.isNotEmpty) return teacher;
    }
    return '';
  }

  List<dynamic> _getCombinedItemsForDate(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    // 1. Assignments
    final dailyAssignments = _assignments
        .where((a) {
          final dueDate = _parseDateOnly(a['due_date']);
          if (dueDate != null && _isSameDay(dueDate, date)) return true;
          final startDate = _parseDateOnly(a['start_date']);
          if (dueDate == null &&
              startDate != null &&
              _isSameDay(startDate, date)) {
            return true;
          }
          return false;
        })
        .map((a) => {...a, 'itemType': 'ASSIGNMENT'})
        .toList();

    final rescheduleTargets = _tempSchedules
        .where((ts) =>
            ts['original_date']?.toString() == dateStr &&
            ts['is_extra_class'] == false)
        .map((ts) => ts['new_date']?.toString() ?? '')
        .where((d) => d.isNotEmpty)
        .toList();
    final rescheduleNote = rescheduleTargets.isNotEmpty
        ? '${rescheduleTargets.join(', ')}\uB85C \uBCC0\uACBD\uB428'
        : '';

    // 2. Classes
    final dailyClasses = _classTimes
        .where((c) {
          final day = c['day']?.toString();
          if (day == null) return false;
          return _isClassDay(day, date);
        })
        .map((c) => {
              ...c,
              'itemType': 'CLASS',
              if (rescheduleNote.isNotEmpty) 'is_rescheduled': true,
              if (rescheduleNote.isNotEmpty) 'reschedule_note': rescheduleNote,
            })
        .toList();

    final tempClasses = _tempSchedules
        .where((ts) => ts['new_date']?.toString() == dateStr)
        .map((ts) {
      final isExtraClass = ts['is_extra_class'] == true;
      final label = isExtraClass ? '\uBCF4\uAC15' : '\uC774\uB3D9';
      final subjectBase = _subjectLabel(ts['subject']?.toString());
      final subject = subjectBase.isNotEmpty ? '$subjectBase ($label)' : label;
      final startTime = ts['new_start_time']?.toString() ?? '';
      final endTime = ts['new_end_time']?.toString() ?? '';
      return {
        'itemType': 'CLASS',
        'subject': subject,
        'start_time':
            startTime.length >= 5 ? startTime.substring(0, 5) : startTime,
        'end_time': endTime.length >= 5 ? endTime.substring(0, 5) : endTime,
        'teacher_name': _resolveTeacherNameForTempSchedule(ts),
        'is_makeup': isExtraClass,
        'temp_schedule': ts,
      };
    }).toList();

    // 3. Combine & Sort
    final combined = [...dailyClasses, ...tempClasses, ...dailyAssignments];

    // [DEBUG] Log filtering results
    if (dailyClasses.isNotEmpty) {
      print(
          'Found ${dailyClasses.length} classes for ${DateFormat('yyyy-MM-dd').format(date)}');
      print('Sample class: ${dailyClasses.first}');
    }

    combined.sort((a, b) {
      // Sort by time
      // Class: start_time (HH:mm)
      // Assignment: due_date (YYYY-MM-DDTHH:mm:ss)
      String timeA = '';
      String timeB = '';

      if (a['itemType'] == 'CLASS') {
        timeA = _formatTimeShort(a['start_time']);
        if (timeA.isEmpty) timeA = '00:00';
      } else {
        timeA = _extractTime(a['due_date']);
        if (timeA.isEmpty) timeA = '23:59';
      }

      if (b['itemType'] == 'CLASS') {
        timeB = _formatTimeShort(b['start_time']);
        if (timeB.isEmpty) timeB = '00:00';
      } else {
        timeB = _extractTime(b['due_date']);
        if (timeB.isEmpty) timeB = '23:59';
      }

      return timeA.compareTo(timeB);
    });

    return combined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('주간 플래너'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // [NEW] Makeup Task Banner
                if (_makeupTaskCount > 0)
                  InkWell(
                    onTap: () async {
                      await context.push('/student/makeup-tasks');
                      _fetchData(); // Refresh on return
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      color: Colors.red.shade50,
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '지난 주차 미완료 과제가 $_makeupTaskCount개 있습니다. (보충 학습)',
                              style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              color: Colors.red.shade300, size: 14),
                        ],
                      ),
                    ),
                  ),

                // Main Planner Content
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Left Sidebar
                      SizedBox(
                        width: 90,
                        child: ListView.builder(
                          controller: _timelineScrollController,
                          itemExtent: 90,
                          itemCount: _weekDates.length,
                          itemBuilder: (context, index) {
                            return _buildTimelineTile(_weekDates[index],
                                index == _weekDates.length - 1);
                          },
                        ),
                      ),
                      // Vertical Divider
                      Container(width: 1, color: Colors.grey.shade200),

                      // 2. Right Content
                      Expanded(
                        child: Container(
                          color: Colors.grey.shade50,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDateHeader(_selectedDate),
                              const SizedBox(height: 20),
                              Expanded(child: _buildAssignmentList()),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTimelineTile(DateTime date, bool isLast) {
    final isSelected = _isSameDay(date, _selectedDate);
    final isToday = _isSameDay(date, DateTime.now());

    return InkWell(
      onTap: () => setState(() => _selectedDate = date),
      child: SizedBox(
        height: 90,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Vertical Line
            if (!isLast)
              Positioned(
                top: 45,
                bottom: -45,
                child: Container(
                    width: 2, color: AppColors.primary.withOpacity(0.2)),
              ),
            Positioned(
              top: 0,
              bottom: 0,
              child: Container(
                  width: 2,
                  color: isLast
                      ? Colors.transparent
                      : AppColors.primary.withOpacity(0.1)),
            ),

            // Node + Text
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('MM.dd').format(date),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.primary : Colors.grey,
                  ),
                ),
                Text(
                  DateFormat('EEE', 'ko_KR').format(date),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isToday
                        ? Colors.red
                        : (isSelected ? AppColors.primary : Colors.black),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.primary.withOpacity(0.3),
                          width: 2)),
                ),
                if (_getCombinedItemsForDate(date).isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    return Row(
      children: [
        Text(
          DateFormat('M월 d일 EEEE', 'ko_KR').format(date),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        if (_isSameDay(date, DateTime.now()))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Today',
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 11)),
          )
      ],
    );
  }

  Widget _buildAssignmentList() {
    final items = _getCombinedItemsForDate(_selectedDate);

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('일정이 없습니다.', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final itemType = item['itemType'];

        if (itemType == 'CLASS') {
          return _buildClassCard(item);
        } else {
          return _buildAssignmentCard(item);
        }
      },
    );
  }

  // [NEW] Class Schedule Card
  Widget _buildClassCard(Map<String, dynamic> item) {
    // Expected fields: subject, start_time, end_time, teacher_name
    final subject = item['subject'] ?? '수업';
    final startTime = _formatTimeShort(item['start_time']);
    final endTime = _formatTimeShort(item['end_time']);
    final teacherRaw =
        _extractTeacherName(item['teacher_name'] ?? item['teacher']);
    const teacherSuffix = '\uC120\uC0DD\uB2D8';
    final teacherLabel = teacherRaw.isEmpty
        ? teacherSuffix
        : (teacherRaw.contains(teacherSuffix)
            ? teacherRaw
            : '$teacherRaw $teacherSuffix');
    final rescheduleNote = item['reschedule_note']?.toString() ?? '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.indigo.shade50, // Distinct color for classes
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.indigo.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Time Column
            Column(
              children: [
                Text(startTime,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.indigo)),
                const SizedBox(height: 4),
                Text(endTime,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 40, color: Colors.indigo.shade100),
            const SizedBox(width: 16),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subject,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(teacherLabel,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade700)),
                    ],
                  ),
                  if (rescheduleNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      rescheduleNote,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> item) {
    final submission = item['submission'];
    final submissionStatus =
        submission is Map ? submission['status']?.toString() : null;
    final isApproved = submissionStatus == 'APPROVED';
    final bool isCompleted = (item['is_completed'] ?? false) || isApproved;
    final isPending = submissionStatus == 'PENDING';
    final isRejected = submissionStatus == 'REJECTED';
    final isReplaced = item['is_replaced'] == true;
    final typeLabel = item['assignment_type'] == 'VOCAB_TEST' ? '단어 시험' : '과제';
    String statusLabel = '미제출';
    Color statusColor = AppColors.primary;

    // Check if assignment is locked (before start_date)
    bool isLocked = false;
    String? lockMessage;
    DateTime? startDate = _parseDateOnly(item['start_date']);
    if (startDate == null && item['assignment_type'] == 'VOCAB_TEST') {
      final dueDate = _parseDateOnly(item['due_date']);
      if (dueDate != null) {
        startDate = dueDate.subtract(const Duration(days: 1));
      }
    }
    if (startDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (today.isBefore(startDate)) {
        isLocked = true;
        final startDateFormatted = DateFormat('M/d').format(startDate);
        lockMessage = '$startDateFormatted부터 수행 가능';
      }
    }

    if (isLocked) {
      statusLabel = '잠금';
      statusColor = Colors.grey;
    } else if (isCompleted) {
      statusLabel = '완료';
      statusColor = Colors.green;
    } else if (isPending) {
      statusLabel = '검토중';
      statusColor = Colors.orange;
    } else if (isRejected) {
      statusLabel = '반려';
      statusColor = Colors.red;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        onTap: () {
          if (isLocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(lockMessage ?? '아직 수행할 수 없는 과제입니다.'),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }
          if (!isCompleted && item['id'] != null) {
            context.push('/assignment/${item['id']}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status Icon/Color
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                    color: statusColor, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(typeLabel,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isReplaced) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: const Text(
                            '대체됨',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['title'] ?? '제목 없음',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['due_date'] != null
                        ? (() {
                            try {
                              final d = DateTime.parse(item['due_date']);
                              return DateFormat('M월 d일 a h:mm', 'ko_KR')
                                  .format(d);
                            } catch (_) {
                              try {
                                final d = DateFormat('yyyy-MM-dd')
                                    .parse(item['due_date']);
                                return DateFormat('M월 d일', 'ko_KR').format(d);
                              } catch (__) {
                                return item['due_date'].toString();
                              }
                            }
                          })()
                        : '',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              )),
              if (isCompleted)
                const Icon(Icons.check_circle, color: Colors.green)
              else
                ElevatedButton(
                  onPressed: isPending
                      ? null
                      : () {
                          if (item['id'] != null) {
                            context.push('/assignment/${item['id']}');
                          }
                        },
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isRejected ? Colors.red : AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      disabledForegroundColor: Colors.white,
                      minimumSize: const Size(60, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12)),
                  child: Text(isPending ? '검토중' : (isRejected ? '재제출' : '인증'),
                      style: const TextStyle(fontSize: 12)),
                )
            ],
          ),
        ),
      ),
    );
  }

  // [NEW] Helper for makeup Logic
  int _makeupTaskCount = 0;

  bool _isMakeupTask(dynamic assignment) {
    bool isCompleted = assignment['is_completed'] == true;
    if (assignment['submission'] != null &&
        assignment['submission']['status'] == 'APPROVED') {
      isCompleted = true;
    }

    // Completed tasks are never "makeup" in the sense of needing action
    if (isCompleted) return false;

    // Check 7-day rule
    // origin_log_date is the primary source, fallback to start_date or due_date
    String? dateStr = assignment['origin_log_date'] ??
        assignment['start_date'] ??
        assignment['due_date'];
    if (dateStr == null) return false;

    DateTime? baseDate;
    try {
      baseDate = DateTime.parse(dateStr);
    } catch (_) {
      return false;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Cutoff: baseDate + 7 days
    final cutoff = baseDate.add(const Duration(days: 7));
    final cutoffDate = DateTime(cutoff.year, cutoff.month, cutoff.day);

    // If today is ON or AFTER the cutoff date (Day 8+), it's a makeup task
    return today.isAfter(cutoffDate) || today.isAtSameMomentAs(cutoffDate);
  }

  void _calculateMakeupCount() {
    int count = 0;
    for (var a in _assignments) {
      if (_isMakeupTask(a)) {
        count++;
      }
    }
    setState(() => _makeupTaskCount = count);
  }
}
