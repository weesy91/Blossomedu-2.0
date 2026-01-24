import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/services/academy_service.dart';

/// Teacher planner: show classes and assignments by day.
class TeacherPlannerScreen extends StatefulWidget {
  const TeacherPlannerScreen({super.key});

  @override
  State<TeacherPlannerScreen> createState() => _TeacherPlannerScreenState();
}

class _TeacherPlannerScreenState extends State<TeacherPlannerScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = true;
  List<dynamic> _students = [];
  List<dynamic> _assignments = [];
  List<dynamic> _classes = [];
  int? _defaultBranchId;
  List<dynamic> _dailyAttendances = []; // [NEW]

  // Timeline State
  late DateTime _startDate;
  late DateTime _selectedDate;
  late List<DateTime> _allDates;
  static const double _timelineItemExtent = 80.0;
  static const int _maxScrollAttempts = 6;
  late final ScrollController _timelineScrollController;
  int _scrollAttempts = 0;

  // Filter: 'all' | 'class' | 'assignment'
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _timelineScrollController = ScrollController(
      initialScrollOffset: _getTodayOffset(),
    );
    _scheduleScrollToToday();
    _fetchData();
  }

  void _initializeDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 2 weeks before to 2 weeks after (29 days total).
    _startDate = today.subtract(const Duration(days: 14));
    _allDates = List.generate(29, (i) => _startDate.add(Duration(days: i)));
    _selectedDate = today;
  }

  Future<void> _fetchData() async {
    try {
      final students = await _academyService.getStudents(scope: 'my');
      // Fetch teacher's assignments
      final assignments = await _academyService.getTeacherAssignments();
      final metadata = await _academyService.getRegistrationMetadata();

      setState(() {
        _students = students;
        _assignments = assignments;
        _classes = metadata['classes'] ?? [];
        _defaultBranchId = metadata['default_branch_id'];
        _isLoading = false;
      });
      _scheduleScrollToToday();
    } catch (e) {
      print('Error loading teacher planner data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _scheduleScrollToToday() {
    _scrollAttempts = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  void _retryScrollToToday() {
    if (_scrollAttempts >= _maxScrollAttempts) {
      return;
    }
    _scrollAttempts += 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  double _getTodayOffset() {
    final now = DateTime.now();
    final todayIndex = _allDates.indexWhere((d) => _isSameDay(d, now));
    if (todayIndex <= 0) {
      return 0.0;
    }
    return todayIndex * _timelineItemExtent;
  }

  void _scrollToToday() {
    if (!mounted) {
      return;
    }
    if (!_timelineScrollController.hasClients) {
      _retryScrollToToday();
      return;
    }
    final position = _timelineScrollController.position;
    if (!position.hasContentDimensions) {
      _retryScrollToToday();
      return;
    }
    final target = _getTodayOffset();
    final maxOffset = position.maxScrollExtent;
    final clamped = target.clamp(0.0, maxOffset);
    if ((position.pixels - clamped).abs() < 0.5) {
      return;
    }
    _timelineScrollController.jumpTo(clamped);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _getDayCode(DateTime date) {
    const codes = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return codes[date.weekday - 1];
  }

  String _subjectLabel(String? code) {
    switch ((code ?? '').toUpperCase()) {
      case 'SYNTAX':
        return '구문';
      case 'READING':
        return '독해';
      case 'GRAMMAR':
        return '문법';
      default:
        return code ?? '';
    }
  }

  String _classTypeForSubject(String subject) {
    if (subject.toUpperCase() == 'GRAMMAR') return 'EXTRA';
    return subject.toUpperCase();
  }

  int _durationMinutesForSubject(String subject) {
    switch (subject.toUpperCase()) {
      case 'READING':
        return 90;
      case 'SYNTAX':
        return 80;
      case 'GRAMMAR':
        return 80;
      default:
        return 80;
    }
  }

  String _formatClassTimeLabel(Map<String, dynamic> classTime, String subject) {
    final startTime = classTime['time']?.toString() ?? '';
    if (startTime.isEmpty) return startTime;
    final parts = startTime.split(':');
    if (parts.length < 2) return startTime;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final startDt = DateTime(2022, 1, 1, hour, minute);
    final endDt =
        startDt.add(Duration(minutes: _durationMinutesForSubject(subject)));
    final endStr =
        '${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}';
    return '$startTime - $endStr';
  }

  String _normalizeTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    return timeStr.length >= 5 ? timeStr.substring(0, 5) : timeStr;
  }

  List<dynamic> _getEffectiveClassesForStudent(Map<String, dynamic> student) {
    final branchId = student['branch'] ?? _defaultBranchId;
    if (branchId == null) return _classes;
    final branchClasses =
        _classes.where((c) => c['branch_id'] == branchId).toList();
    if (branchClasses.isNotEmpty) return branchClasses;
    return _classes.where((c) => c['branch_id'] == null).toList();
  }

  List<dynamic> _getAvailableClassesForSchedule(
      Map<String, dynamic> student, DateTime date, String subject) {
    final dayCode = _getDayCode(date);
    final effectiveClasses = _getEffectiveClassesForStudent(student);
    final dayClasses =
        effectiveClasses.where((c) => c['day'] == dayCode).toList();
    if (dayClasses.isEmpty) return [];
    final type = _classTypeForSubject(subject);
    final hasType = dayClasses
        .any((c) => (c['type']?.toString().toUpperCase() ?? '') == type);
    final filtered = hasType
        ? dayClasses
            .where((c) => (c['type']?.toString().toUpperCase() ?? '') == type)
            .toList()
        : dayClasses;
    filtered.sort((a, b) =>
        (a['time']?.toString() ?? '').compareTo(b['time']?.toString() ?? ''));
    return filtered;
  }

  int? _defaultClassIdForSchedule(
      Map<String, dynamic> student, DateTime date, String subject) {
    final options = _getAvailableClassesForSchedule(student, date, subject);
    if (options.isEmpty) return null;
    return options.first['id'] as int?;
  }

  int? _findClassIdForSchedule(Map<String, dynamic> student, DateTime date,
      String subject, String? timeStr) {
    final timeKey = _normalizeTime(timeStr);
    final options = _getAvailableClassesForSchedule(student, date, subject);
    if (timeKey.isNotEmpty) {
      for (final option in options) {
        final optionTime = _normalizeTime(option['time']?.toString());
        if (optionTime == timeKey) return option['id'] as int?;
      }
    }
    return options.isNotEmpty ? options.first['id'] as int? : null;
  }

  /// Students who have classes on the given date.
  List<dynamic> _getStudentsForDate(DateTime date) {
    final dayCode = _getDayCode(date);
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _students.where((s) {
      if (s['is_active'] == false) return false;
      // [NEW] Start Date Check
      final startDateStr = s['start_date']?.toString();
      if (startDateStr != null && startDateStr.isNotEmpty) {
        if (dateStr.compareTo(startDateStr) < 0) {
          return false;
        }
      }

      final classTimes = s['class_times'] as List<dynamic>? ?? [];
      final hasRegularClass = classTimes.any((ct) => ct['day'] == dayCode);

      // [NEW] Check Temporary Schedules
      final tempSchedules = s['temp_schedules'] as List<dynamic>? ?? [];
      final hasTempClass = tempSchedules.any((ts) => ts['new_date'] == dateStr);

      return hasRegularClass || hasTempClass;
    }).toList();
  }

  /// Assignments due on the given date.
  List<dynamic> _getAssignmentsForDate(DateTime date) {
    return _assignments.where((a) {
      final dueDateStr = a['due_date']?.toString();
      // [FIX] Filter out invalid assignments (empty title)
      final title = a['title']?.toString();
      if (dueDateStr == null || title == null || title.isEmpty) return false;
      final parsed = DateTime.tryParse(dueDateStr);
      if (parsed == null) return false;
      return _isSameDay(parsed.toLocal(), date);
    }).toList();
  }

  /// Combine classes and assignments for the selected date.
  List<Map<String, dynamic>> _getCombinedItemsForDate(DateTime date) {
    final items = <Map<String, dynamic>>[];

    // Classes
    if (_filter == 'all' || _filter == 'class') {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      for (final student in _getStudentsForDate(date)) {
        final classTimes = student['class_times'] as List<dynamic>? ?? [];
        final dayCode = _getDayCode(date);
        final tempSchedules = student['temp_schedules'] as List<dynamic>? ?? [];

        // [NEW] Check Attendance Status
        String attendanceStatus = 'UNKNOWN';
        if (_dailyAttendances.isNotEmpty) {
          final att = _dailyAttendances.firstWhere(
              (a) => a['student'].toString() == student['id'].toString(),
              orElse: () => null);
          if (att != null) attendanceStatus = att['status'];
        }

        // 1. Regular Classes
        for (final ct in classTimes) {
          if (ct['day'] == dayCode) {
            bool isRescheduled = false;
            String rescheduleNote = '';

            // Check if this specific class subject is moved
            for (final ts in tempSchedules) {
              if (ts['original_date'] == dateStr &&
                  ts['is_extra_class'] == false) {
                // [FIX] Check subject match (SYNTAX vs READING)
                // ts['subject'] is uppercase (SYNTAX/READING/GRAMMAR)
                // ct['type'] is also uppercase (inferred from backend serializer)
                if (ts['subject'] == ct['type']) {
                  isRescheduled = true;
                  rescheduleNote = '${ts['new_date']}로 변경됨';
                  break;
                }
              }
            }

            items.add({
              'type': 'class',
              'student': student,
              'classTime': ct,
              'isRescheduled': isRescheduled,
              'rescheduleNote': rescheduleNote,
              'attendanceStatus': attendanceStatus,
            });
          }
        }

        // 2. Temporary Schedules (Moved/Extra classes on this day)
        for (final ts in tempSchedules) {
          if (ts['new_date'] == dateStr) {
            final startTime = ts['new_start_time']?.toString() ?? '';
            final isExtraClass = ts['is_extra_class'] == true;
            final label = isExtraClass ? '보강' : '이동';

            // Construct pseudo ClassTime object for moved class
            items.add({
              'type': 'class',
              'student': student,
              'classTime': {
                'subject': '${_subjectLabel(ts['subject'])} ($label)',
                'start_time': startTime.length >= 5
                    ? startTime.substring(0, 5)
                    : startTime,
                'is_makeup': isExtraClass,
                'schedule_id': ts['id'],
                'type': ts['subject'],
              },
              'tempSchedule': ts, // Allow editing this temp schedule
              'isRescheduled': false, // This IS the rescheduled class
              'attendanceStatus': attendanceStatus,
            });
          }
        }
      }
    }

    // Assignments
    if (_filter == 'all' || _filter == 'assignment') {
      for (final assignment in _getAssignmentsForDate(date)) {
        items.add({
          'type': 'assignment', // [FIX] Add type field for assignments
          'assignment': assignment,
        });
      }
    }

    // [FIX] Sort by Time
    items.sort((a, b) {
      // Helper to get comparable minutes from midnight
      int getMinutes(Map<String, dynamic> item) {
        if (item['type'] == 'class') {
          final timeStr = item['classTime']['start_time'] as String? ?? '00:00';
          final parts = timeStr.split(':');
          if (parts.length == 2) {
            return (int.tryParse(parts[0]) ?? 0) * 60 +
                (int.tryParse(parts[1]) ?? 0);
          }
        } else if (item['type'] == 'assignment') {
          final dueStr = item['assignment']['due_date']?.toString();
          if (dueStr != null) {
            final dt = DateTime.tryParse(dueStr);
            if (dt != null) {
              return dt.hour * 60 + dt.minute;
            }
          }
        }
        return 24 * 60; // Put at end if unknown
      }

      return getMinutes(a).compareTo(getMinutes(b));
    });

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('플래너'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
        actions: [
          // Filter menu
          PopupMenuButton<String>(
            tooltip: '정렬 필터',
            onSelected: (value) => setState(() => _filter = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('전체')),
              const PopupMenuItem(value: 'class', child: Text('수업')),
              const PopupMenuItem(value: 'assignment', child: Text('과제')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    _filter == 'all'
                        ? '전체'
                        : (_filter == 'class' ? '수업' : '과제'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Left Sidebar - Timeline (vertical scroll)
                SizedBox(
                  width: 80,
                  child: ListView.builder(
                    controller: _timelineScrollController, // [NEW]
                    itemExtent:
                        _timelineItemExtent, // [NEW] Fixed height for accurate scrolling
                    itemCount: _allDates.length,
                    itemBuilder: (context, index) {
                      return _buildTimelineTile(
                          _allDates[index], index == _allDates.length - 1);
                    },
                  ),
                ),
                // Divider
                Container(width: 1, color: Colors.grey.shade200),
                // 2. Right Content
                Expanded(
                  child: Container(
                    color: Colors.grey.shade50,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDateHeader(_selectedDate),
                        const SizedBox(height: 16),
                        Expanded(child: _buildItemList()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTimelineTile(DateTime date, bool isLast) {
    final isSelected = _isSameDay(date, _selectedDate);
    final isToday = _isSameDay(date, DateTime.now());
    final hasAssignments = _getAssignmentsForDate(date).isNotEmpty;

    return InkWell(
      onTap: () => _onDaySelected(date), // [FIX] Call method logic
      child: SizedBox(
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Vertical Line
            if (!isLast)
              Positioned(
                top: 40,
                bottom: -40,
                child:
                    Container(width: 2, color: Colors.indigo.withOpacity(0.2)),
              ),
            Positioned(
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                color: isLast
                    ? Colors.transparent
                    : Colors.indigo.withOpacity(0.1),
              ),
            ),
            // Node + Text Background
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.indigo
                    : (isToday ? Colors.indigo.shade50 : Colors.transparent),
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: Colors.indigo.shade200)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('MM.dd').format(date),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('EEE', 'ko_KR').format(date),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : (isToday ? Colors.indigo : Colors.black),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (hasAssignments)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    return Row(
      children: [
        Flexible(
          child: Text(
            DateFormat('M월 d일 EEEE', 'ko_KR').format(date),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
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

  Widget _buildItemList() {
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
        if (item['type'] == 'class') {
          return _buildClassCard(item);
        } else {
          return _buildAssignmentCard(item);
        }
      },
    );
  }

  Widget _buildClassCard(Map<String, dynamic> item) {
    final student = item['student'];
    final classTime = item['classTime'];
    final name = student['name'] ?? '학생';
    final school = student['school'] ?? '';
    final grade = student['grade'] ?? '';
    final startTime = classTime['start_time'] ?? '';
    final subject = classTime['subject'] ?? '';
    final type =
        classTime['type'] ?? ''; // [NEW] Use type for robust navigation
    final tempSchedule = item['tempSchedule'] as Map<String, dynamic>?;
    final canEditSchedule = tempSchedule != null;

    // [NEW] Handle Rescheduled Class style
    final isRescheduled = item['isRescheduled'] ?? false;
    final rescheduleNote = item['rescheduleNote'] ?? '';
    final attendanceStatus = item['attendanceStatus'] ?? 'UNKNOWN';
    final isAbsent = attendanceStatus == 'ABSENT';

    Color subjectColor = Colors.indigo;
    if (subject.contains('독해') || subject.contains('READING')) {
      subjectColor = Colors.purple;
    }

    if (isRescheduled) {
      return Card(
        elevation: 0,
        color: Colors.grey.shade100,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade300)),
        child: ListTile(
          leading: const Icon(Icons.event_busy, color: Colors.grey),
          title: Text(name,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  decoration: TextDecoration.lineThrough)),
          subtitle: Text('$subject · $rescheduleNote',
              style: const TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ),
      );
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: isAbsent ? Colors.red.shade50 : null, // [NEW] Red bg for absent
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: isAbsent
                  ? Colors.red.shade200
                  : subjectColor.withOpacity(0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type indicator
            Container(
              width: 4,
              height: 50,
              decoration: BoxDecoration(
                  color: subjectColor, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 16),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.school, size: 14, color: subjectColor),
                      const SizedBox(width: 4),
                      Text('수업',
                          style: TextStyle(
                              fontSize: 11,
                              color: subjectColor,
                              fontWeight: FontWeight.bold)),
                      if (startTime.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(startTime,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                      '$school · $grade${subject.isNotEmpty ? ' · $subject' : ''}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  // Actions - Moved here for mobile layout safety
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildActionButton(Icons.edit_note, '일지', Colors.green,
                          () async {
                        final studentId = student['id']?.toString();
                        final dateStr =
                            DateFormat('yyyy-MM-dd').format(_selectedDate);

                        // [NEW] Future Log Restriction
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        if (_selectedDate.isAfter(today)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('아직 수업이 없는 날짜는 일지를 작성할 수 없습니다.')));
                          return;
                        }

                        // [NEW] Absent Restriction
                        if (isAbsent) {
                          _showAbsentDialog(student);
                          return;
                        }

                        if (studentId != null) {
                          // [FIX] Pass `type` instead of `subject` to ensure correct matching (SYNTAX/READING)
                          final subjectParam = type.isNotEmpty ? type : subject;
                          await context.push(
                              '/teacher/class_log/create?studentId=$studentId&date=$dateStr&subject=$subjectParam');
                          // [FIX] Refresh data after returning from Class Log
                          _fetchData();
                        }
                      }),
                      // [NEW] Make-up Class Button
                      _buildActionButton(Icons.access_time_filled,
                          canEditSchedule ? '이동' : '보강', Colors.orange, () {
                        if (canEditSchedule) {
                          _showMakeUpEditDialog(student, tempSchedule);
                        } else {
                          // Pass current date as potentially the "Original Date" for rescheduling
                          _showMakeUpDialog(student, _selectedDate);
                        }
                      }),
                      // [NEW] Student Planner Button
                      _buildActionButton(
                          Icons.calendar_month, '학생', Colors.indigo, () async {
                        final studentId = student['id']?.toString();
                        if (studentId != null) {
                          await context.push('/teacher/student/$studentId');
                          _fetchData(); // [FIX] Refresh data after return
                        }
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> item) {
    final assignment = item['assignment'];
    final title = assignment['title'] ?? '과제';
    final studentName = assignment['student_name'] ?? '';
    final isCompleted = assignment['is_completed'] ?? false;
    final submission = assignment['submission'];
    final submissionStatus =
        submission is Map ? submission['status']?.toString() : null;
    final isPending = submissionStatus == 'PENDING';
    final isRejected = submissionStatus == 'REJECTED';
    final isReplaced = assignment['is_replaced'] == true;

    final dueDateStr = assignment['due_date'];
    DateTime? dueDate;
    if (dueDateStr != null) {
      dueDate = DateTime.tryParse(dueDateStr);
    }

    String statusLabel = isCompleted ? '완료' : '과제';
    Color statusColor = isCompleted ? Colors.green : Colors.orange;

    if (isPending) {
      statusLabel = '검토중';
      statusColor = Colors.orange;
    } else if (isRejected) {
      statusLabel = '반려';
      statusColor = Colors.red;
    } else if (!isCompleted && dueDate != null) {
      // Check for Overdue
      // Compare dates only: if due date is strictly before today, it's overdue.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (dueDate.isBefore(today)) {
        statusLabel = '미제출';
        statusColor = Colors.red;
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: statusColor.withOpacity(0.3))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 50,
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
                      Icon(Icons.assignment, size: 14, color: statusColor),
                      const SizedBox(width: 6),
                      Text(statusLabel,
                          style: TextStyle(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.bold)),
                      if (isReplaced) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
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
                      const SizedBox(width: 8),
                      if (studentName.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(studentName,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (isCompleted)
              const Icon(Icons.check_circle, color: Colors.green)
            else if (isPending)
              TextButton(
                child: const Text('검토'),
                onPressed: () {
                  final assignmentId = assignment['id']?.toString();
                  if (assignmentId != null) {
                    context
                        .push('/teacher/assignment/review/$assignmentId')
                        .then((_) => _fetchData());
                  }
                },
              )
            else if (isRejected)
              const Text('반려', style: TextStyle(color: Colors.red))
            else
              const Text('미제출', style: TextStyle(color: Colors.grey))
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showMakeUpDialog(Map<String, dynamic> student, DateTime currentDate) {
    // Default new date: Tomorrow (for convenience)
    DateTime selectedDate = currentDate.add(const Duration(days: 1));
    if (selectedDate.isBefore(DateTime.now())) {
      selectedDate = DateTime.now();
    }

    String selectedSubject = 'SYNTAX';
    int? selectedClassId =
        _defaultClassIdForSchedule(student, selectedDate, selectedSubject);
    bool isExtraClass = true; // Default: Make-up (Extra)
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('${student['name']} 일정 관리'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mode Selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('보강 (추가)'),
                        selected: isExtraClass,
                        onSelected: (v) => setState(() => isExtraClass = true),
                        selectedColor: Colors.orange.shade100,
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('수업 이동'),
                        selected: !isExtraClass,
                        onSelected: (v) => setState(() => isExtraClass = false),
                        selectedColor: Colors.red.shade100,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (!isExtraClass)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        '기존 수업은 ${DateFormat('yyyy-MM-dd').format(currentDate)} (취소됨)',
                        style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),

                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '날짜: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final d = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2025),
                            lastDate: DateTime(2030));
                        if (d != null) {
                          setState(() {
                            selectedDate = d;
                            selectedClassId = _defaultClassIdForSchedule(
                                student, selectedDate, selectedSubject);
                          });
                        }
                      }),
                  Builder(builder: (context) {
                    final availableClasses = _getAvailableClassesForSchedule(
                        student, selectedDate, selectedSubject);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<int>(
                          value: selectedClassId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '시간'),
                          items: availableClasses.map((c) {
                            return DropdownMenuItem<int>(
                              value: c['id'],
                              child: Text(
                                _formatClassTimeLabel(c, selectedSubject),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => selectedClassId = v),
                        ),
                        if (availableClasses.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '선택 가능한 시간표가 없습니다.',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ),
                      ],
                    );
                  }),
                  DropdownButtonFormField<String>(
                    value: selectedSubject,
                    items: const [
                      DropdownMenuItem(
                          value: 'SYNTAX', child: Text('구문 (SYNTAX)')),
                      DropdownMenuItem(
                          value: 'READING', child: Text('독해 (READING)')),
                    ],
                    onChanged: (v) => setState(() {
                      selectedSubject = v!;
                      selectedClassId = _defaultClassIdForSchedule(
                          student, selectedDate, selectedSubject);
                    }),
                    decoration: const InputDecoration(labelText: '과목'),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '사유'),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소')),
              ElevatedButton(
                  onPressed: () async {
                    try {
                      final dateStr =
                          DateFormat('yyyy-MM-dd').format(selectedDate);
                      if (selectedClassId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('시간표를 선택해주세요.')));
                        return;
                      }
                      final availableClasses = _getAvailableClassesForSchedule(
                          student, selectedDate, selectedSubject);
                      final selectedClass = availableClasses.firstWhere(
                          (c) => c['id'] == selectedClassId,
                          orElse: () => null);
                      if (selectedClass == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('시간표를 다시 선택해주세요.')));
                        return;
                      }
                      final startTime =
                          _normalizeTime(selectedClass?['time']?.toString());

                      final payload = {
                        'student': student['id'],
                        'subject': selectedSubject,
                        'new_date': dateStr,
                        'target_class': selectedClassId,
                        if (startTime.isNotEmpty) 'new_start_time': startTime,
                        'is_extra_class': isExtraClass,
                        'note': noteController.text,
                      };

                      // If rescheduling, set original_date
                      if (!isExtraClass) {
                        payload['original_date'] =
                            DateFormat('yyyy-MM-dd').format(currentDate);
                      }

                      await _academyService.createTemporarySchedule(payload);

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('일정이 저장되었습니다.')));
                        _fetchData(); // Refresh UI
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('저장')),
            ],
          );
        });
      },
    );
  }

  void _showMakeUpEditDialog(
      Map<String, dynamic> student, Map<String, dynamic> schedule) {
    final scheduleId = int.tryParse(schedule['id']?.toString() ?? '');
    if (scheduleId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('수정할 보강 일정이 없습니다.')));
      return;
    }

    final scheduleDateStr = schedule['new_date']?.toString();
    DateTime selectedDate =
        DateTime.tryParse(scheduleDateStr ?? '') ?? _selectedDate;
    String selectedSubject =
        (schedule['subject']?.toString() ?? 'SYNTAX').toUpperCase();
    int? selectedClassId = _findClassIdForSchedule(
        student, selectedDate, selectedSubject, schedule['new_start_time']);
    final noteController =
        TextEditingController(text: schedule['note']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('${student['name']} 보강 시간 수정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '날짜: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final d = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2025),
                            lastDate: DateTime(2030));
                        if (d != null) {
                          setState(() {
                            selectedDate = d;
                            selectedClassId = _defaultClassIdForSchedule(
                                student, selectedDate, selectedSubject);
                          });
                        }
                      }),
                  Builder(builder: (context) {
                    final availableClasses = _getAvailableClassesForSchedule(
                        student, selectedDate, selectedSubject);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<int>(
                          value: selectedClassId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '시간'),
                          items: availableClasses.map((c) {
                            return DropdownMenuItem<int>(
                              value: c['id'],
                              child: Text(
                                _formatClassTimeLabel(c, selectedSubject),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => selectedClassId = v),
                        ),
                        if (availableClasses.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '선택 가능한 시간표가 없습니다.',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ),
                      ],
                    );
                  }),
                  DropdownButtonFormField<String>(
                    value: selectedSubject,
                    items: const [
                      DropdownMenuItem(
                          value: 'SYNTAX', child: Text('구문 (SYNTAX)')),
                      DropdownMenuItem(
                          value: 'READING', child: Text('독해 (READING)')),
                    ],
                    onChanged: (v) => setState(() {
                      selectedSubject = v ?? selectedSubject;
                      selectedClassId = _defaultClassIdForSchedule(
                          student, selectedDate, selectedSubject);
                    }),
                    decoration: const InputDecoration(labelText: '과목'),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '사유'),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소')),
              TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                              title: const Text('보강 삭제'),
                              content: const Text('보강 수업을 삭제할까요?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('취소')),
                                ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('삭제')),
                              ],
                            ));
                    if (confirmed != true) return;
                    try {
                      await _academyService.deleteTemporarySchedule(scheduleId);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('보강이 삭제되었습니다.')));
                        _fetchData();
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('삭제')),
              ElevatedButton(
                  onPressed: () async {
                    try {
                      final dateStr =
                          DateFormat('yyyy-MM-dd').format(selectedDate);
                      if (selectedClassId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('시간표를 선택해주세요.')));
                        return;
                      }
                      final availableClasses = _getAvailableClassesForSchedule(
                          student, selectedDate, selectedSubject);
                      final selectedClass = availableClasses.firstWhere(
                          (c) => c['id'] == selectedClassId,
                          orElse: () => null);
                      if (selectedClass == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('시간표를 다시 선택해주세요.')));
                        return;
                      }
                      final startTime =
                          _normalizeTime(selectedClass?['time']?.toString());

                      final payload = {
                        'subject': selectedSubject,
                        'new_date': dateStr,
                        'target_class': selectedClassId,
                        if (startTime.isNotEmpty) 'new_start_time': startTime,
                        'note': noteController.text,
                      };

                      await _academyService.updateTemporarySchedule(
                          scheduleId, payload);

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('보강 시간이 수정되었습니다.')));
                        _fetchData(); // Refresh UI
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('저장')),
            ],
          );
        });
      },
    );
  }

  Future<void> _fetchDailyData(DateTime date) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final atts = await _academyService.getAttendances(date: dateStr);
      if (mounted) {
        setState(() {
          _dailyAttendances = atts;
        });
      }
    } catch (e) {
      debugPrint('Error loading daily data: $e');
    }
  }

  void _onDaySelected(DateTime date) {
    if (_isSameDay(_selectedDate, date)) return;
    setState(() {
      _selectedDate = date;
      _dailyAttendances = []; // Clear pending load
    });
    _fetchDailyData(date);
  }

  void _showAbsentDialog(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('출석 확인'),
        content: const Text('결석 처리한 학생입니다.\n일지를 작성하려면 출석 상태를 변경해주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                Navigator.pop(context);
                final studentId = student['id'];
                if (studentId != null) {
                  await _academyService.createAttendance(
                      studentId, 'PRESENT', _selectedDate);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('출석으로 변경되었습니다.')));
                    _fetchDailyData(_selectedDate); // Refresh status
                  }
                }
              } catch (e) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('출석으로 변경'),
          ),
        ],
      ),
    );
  }
}
