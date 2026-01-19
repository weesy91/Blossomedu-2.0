import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/services/academy_service.dart';

/// ?†ÏÉù???µÌï© ?åÎûò?? ?òÏóÖ + Í≥ºÏ†úÎ•??†ÏßúÎ≥ÑÎ°ú ?úÏãú
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
  List<dynamic> _dailyAttendances = []; // [NEW]

  // Timeline State
  late DateTime _startDate;
  late DateTime _selectedDate;
  late List<DateTime> _allDates;
  final ScrollController _timelineScrollController =
      ScrollController(); // [NEW]

  // Filter: 'all' | 'class' | 'assignment'
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _fetchData();
  }

  void _initializeDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 2Ï£???~ 2Ï£???(Ï¥?29??
    _startDate = today.subtract(const Duration(days: 14));
    _allDates = List.generate(29, (i) => _startDate.add(Duration(days: i)));
    _selectedDate = today;
  }

  Future<void> _fetchData() async {
    try {
      final students = await _academyService.getStudents(scope: 'my');
      // Fetch teacher's assignments
      final assignments = await _academyService.getTeacherAssignments();

      setState(() {
        _students = students;
        _assignments = assignments;
        _isLoading = false;
      });
      // [NEW] Scroll to today after layout
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
      // [NEW] Fetch daily attendance
      _fetchDailyData(_selectedDate);
    } catch (e) {
      debugPrint('Error fetching data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _scrollToToday() {
    final now = DateTime.now();
    final todayIndex = _allDates.indexWhere((d) => _isSameDay(d, now));
    if (todayIndex != -1 && _timelineScrollController.hasClients) {
      // Each tile is ~80 height, scroll to put today near top
      final offset = (todayIndex * 80.0);
      _timelineScrollController.jumpTo(offset);
    }
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
        return 'Íµ¨Î¨∏';
      case 'READING':
        return '?ÖÌï¥';
      case 'GRAMMAR':
        return 'Î¨∏Î≤ï';
      default:
        return code ?? '';
    }
  }

  /// ?¥Îãπ ?†Ïßú???òÏóÖ???àÎäî ?ôÏÉù???ÑÌÑ∞Îß?
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

  /// ?¥Îãπ ?†Ïßú??ÎßàÍ∞ê??Í≥ºÏ†ú???ÑÌÑ∞Îß?
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

  /// ?µÌï© ?ÑÏù¥??Î¶¨Ïä§???ùÏÑ±
  List<Map<String, dynamic>> _getCombinedItemsForDate(DateTime date) {
    final items = <Map<String, dynamic>>[];

    // ?òÏóÖ Ï∂îÍ?
    if (_filter == 'all' || _filter == 'class') {
      final dateStr =
          DateFormat('yyyy-MM-dd').format(date); // [FIX] Add dateStr
      for (final student in _getStudentsForDate(date)) {
        final classTimes = student['class_times'] as List<dynamic>? ?? [];
        final dayCode = _getDayCode(date);
        // [NEW] Check for rescheduling (Cancellation of regular class)
        bool isRescheduled = false;
        String rescheduleNote = '';
        final tempSchedules = student['temp_schedules'] as List<dynamic>? ?? [];

        for (final ts in tempSchedules) {
          // Check if this regular class date is marked as 'original_date' of a change
          if (ts['original_date'] == dateStr && ts['is_extra_class'] == false) {
            isRescheduled = true;
            rescheduleNote = '${ts['new_date']}Î°?Î≥ÄÍ≤ΩÎê®';
            break;
          }
        }

        // [NEW] Check Attendance Status
        String attendanceStatus = 'UNKNOWN';
        if (_dailyAttendances.isNotEmpty) {
          final att = _dailyAttendances.firstWhere(
              (a) => a['student'].toString() == student['id'].toString(),
              orElse: () => null);
          if (att != null) attendanceStatus = att['status'];
        }

        for (final ct in classTimes) {
          if (ct['day'] == dayCode) {
            items.add({
              'type': 'class',
              'student': student,
              'classTime': ct,
              'isRescheduled': isRescheduled,
              'rescheduleNote': rescheduleNote,
              'attendanceStatus': attendanceStatus, // [NEW]
            });
          }
        }

        // [NEW] Temp Schedules
        for (final ts in tempSchedules) {
          if (ts['new_date'] == dateStr) {
            final startTime = ts['new_start_time']?.toString() ?? '';
            final isExtraClass = ts['is_extra_class'] == true;
            final label = isExtraClass ? 'Î≥¥Í∞ï' : '?¥Îèô';
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
              'tempSchedule': ts,
            });
          }
        }
      }
    }

    // Í≥ºÏ†ú Ï∂îÍ?
    if (_filter == 'all' || _filter == 'assignment') {
      for (final assignment in _getAssignmentsForDate(date)) {
        items.add({
          'type': 'assignment',
          'assignment': assignment,
        });
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('?åÎûò??),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
        actions: [
          // ?ÑÌÑ∞ ?úÎ°≠?§Ïö¥
          PopupMenuButton<String>(
            tooltip: '?ïÎ†¨ ?ÑÌÑ∞',
            onSelected: (value) => setState(() => _filter = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('?ÑÏ≤¥')),
              const PopupMenuItem(value: 'class', child: Text('?òÏóÖÎß?)),
              const PopupMenuItem(value: 'assignment', child: Text('Í≥ºÏ†úÎß?)),
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
                        ? '?ÑÏ≤¥'
                        : (_filter == 'class' ? '?òÏóÖ' : 'Í≥ºÏ†ú'),
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
                // 1. Left Sidebar - Timeline (?∏Î°ú ?§ÌÅ¨Î°?
                SizedBox(
                  width: 80,
                  child: ListView.builder(
                    controller: _timelineScrollController, // [NEW]
                    itemExtent: 80, // [NEW] Fixed height for accurate scrolling
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
            DateFormat('M??d??EEEE', 'ko_KR').format(date),
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
            Text('?ºÏ†ï???ÜÏäµ?àÎã§.', style: TextStyle(color: Colors.grey.shade500)),
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
    final name = student['name'] ?? '?ôÏÉù';
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
    if (subject.contains('?ÖÌï¥') || subject.contains('READING')) {
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
          subtitle: Text('$subject ¬∑ $rescheduleNote',
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
                      Text('?òÏóÖ',
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
                      '$school ¬∑ $grade${subject.isNotEmpty ? ' ¬∑ $subject' : ''}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            // Actions
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(Icons.edit_note, '?ºÏ?', Colors.green,
                    () async {
                  final studentId = student['id']?.toString();
                  final dateStr =
                      DateFormat('yyyy-MM-dd').format(_selectedDate);

                  // [NEW] Future Log Restriction
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  if (_selectedDate.isAfter(today)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('?ÑÏßÅ ?òÏóÖ?òÏ? ?äÏ? ?†Ïßú???ºÏ????ëÏÑ±?????ÜÏäµ?àÎã§.')));
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
                const SizedBox(width: 8),
                // [NEW] Make-up Class Button
                _buildActionButton(
                    Icons.access_time_filled,
                    canEditSchedule ? '?¥Îèô' : 'Î≥¥Í∞ï',
                    Colors.orange, () {
                  if (canEditSchedule) {
                    _showMakeUpEditDialog(student, tempSchedule!);
                  } else {
                    // Pass current date as potentially the "Original Date" for rescheduling
                    _showMakeUpDialog(student, _selectedDate);
                  }
                }),
                const SizedBox(width: 8),
                // [NEW] Student Planner Button
                _buildActionButton(Icons.calendar_month, '?ôÏÉù', Colors.indigo,
                    () async {
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
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> item) {
    final assignment = item['assignment'];
    final title = assignment['title'] ?? 'Í≥ºÏ†ú';
    final studentName = assignment['student_name'] ?? '';
    final isCompleted = assignment['is_completed'] ?? false;
    final submission = assignment['submission'];
    final submissionStatus =
        submission is Map ? submission['status']?.toString() : null;
    final isPending = submissionStatus == 'PENDING';
    final isRejected = submissionStatus == 'REJECTED';
    final isReplaced = assignment['is_replaced'] == true;

    String statusLabel = isCompleted ? '?ÑÎ£å' : 'Í≥ºÏ†ú';
    Color statusColor = isCompleted ? Colors.green : Colors.orange;
    if (isPending) {
      statusLabel = 'Í≤Ä?†Ï§ë';
      statusColor = Colors.orange;
    } else if (isRejected) {
      statusLabel = 'Î∞òÎ†§';
      statusColor = Colors.red;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.orange.shade100)),
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
                            '?ÄÏ≤¥Îê®',
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
                child: const Text('Í≤Ä??),
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
              const Text('Î∞òÎ†§', style: TextStyle(color: Colors.red))
            else
              const Text('ÎØ∏Ï†úÏ∂?, style: TextStyle(color: Colors.grey)),
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

    TimeOfDay selectedTime = TimeOfDay.now();
    String selectedSubject = 'SYNTAX';
    bool isExtraClass = true; // Default: Make-up (Extra)
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('${student['name']} ?ºÏ†ï Í¥ÄÎ¶?),
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
                        label: const Text('Î≥¥Í∞ï (Ï∂îÍ?)'),
                        selected: isExtraClass,
                        onSelected: (v) => setState(() => isExtraClass = true),
                        selectedColor: Colors.orange.shade100,
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('?òÏóÖ Î≥ÄÍ≤?),
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
                        'Í∏∞Ï°¥ ?òÏóÖ?? ${DateFormat('yyyy-MM-dd').format(currentDate)} (Ï∑®ÏÜå??',
                        style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),

                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '???†Ïßú: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final d = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2025),
                            lastDate: DateTime(2030));
                        if (d != null) setState(() => selectedDate = d);
                      }),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('???úÍ∞Ñ: ${selectedTime.format(context)}'),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final t = await showTimePicker(
                            context: context, initialTime: selectedTime);
                        if (t != null) setState(() => selectedTime = t);
                      }),
                  DropdownButtonFormField<String>(
                    value: selectedSubject,
                    items: const [
                      DropdownMenuItem(
                          value: 'SYNTAX', child: Text('Íµ¨Î¨∏ (SYNTAX)')),
                      DropdownMenuItem(
                          value: 'READING', child: Text('?ÖÌï¥ (READING)')),
                      DropdownMenuItem(
                          value: 'GRAMMAR', child: Text('?¥Î≤ï (GRAMMAR)')),
                    ],
                    onChanged: (v) => setState(() => selectedSubject = v!),
                    decoration: const InputDecoration(labelText: 'Í≥ºÎ™©'),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Î©îÎ™® (?†ÌÉù)'),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Ï∑®ÏÜå')),
              ElevatedButton(
                  onPressed: () async {
                    try {
                      final dateStr =
                          DateFormat('yyyy-MM-dd').format(selectedDate);
                      final h = selectedTime.hour.toString().padLeft(2, '0');
                      final m = selectedTime.minute.toString().padLeft(2, '0');

                      final payload = {
                        'student': student['id'],
                        'subject': selectedSubject,
                        'new_date': dateStr,
                        'new_start_time': '$h:$m',
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
                            const SnackBar(content: Text('?ºÏ†ï???Ä?•Îêò?àÏäµ?àÎã§.')));
                        _fetchData(); // Refresh UI
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('?Ä??)),
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ºˆ¡§«“ ∫∏∞≠ ¿œ¡§¿Ã æ¯Ω¿¥œ¥Ÿ.')));
      return;
    }

    final scheduleDateStr = schedule['new_date']?.toString();
    DateTime selectedDate =
        DateTime.tryParse(scheduleDateStr ?? '') ?? _selectedDate;
    TimeOfDay selectedTime =
        _parseTimeOfDay(schedule['new_start_time']?.toString());
    String selectedSubject =
        (schedule['subject']?.toString() ?? 'SYNTAX').toUpperCase();
    final noteController =
        TextEditingController(text: schedule['note']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text('${student['name']} ∫∏∞≠ Ω√∞£ ºˆ¡§'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '≥Ø¬•: ${DateFormat('yyyy-MM-dd').format(selectedDate)}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final d = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2025),
                            lastDate: DateTime(2030));
                        if (d != null) setState(() => selectedDate = d);
                      }),
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Ω√∞£: ${selectedTime.format(context)}'),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final t = await showTimePicker(
                            context: context, initialTime: selectedTime);
                        if (t != null) setState(() => selectedTime = t);
                      }),
                  DropdownButtonFormField<String>(
                    value: selectedSubject,
                    items: const [
                      DropdownMenuItem(
                          value: 'SYNTAX', child: Text('±∏πÆ (SYNTAX)')),
                      DropdownMenuItem(
                          value: 'READING', child: Text('µ∂«ÿ (READING)')),
                      DropdownMenuItem(
                          value: 'GRAMMAR', child: Text('πÆπ˝ (GRAMMAR)')),
                    ],
                    onChanged: (v) =>
                        setState(() => selectedSubject = v ?? selectedSubject),
                    decoration: const InputDecoration(labelText: '∞˙∏Ò'),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: '∏ﬁ∏ (º±≈√)'),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('√Îº“')),
              TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                              title: const Text('∫∏∞≠ ªË¡¶'),
                              content: const Text('∫∏∞≠ ºˆæ˜¿ª ªË¡¶«“±Óø‰?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('√Îº“')),
                                ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('ªË¡¶')),
                              ],
                            ));
                    if (confirmed != true) return;
                    try {
                      await _academyService.deleteTemporarySchedule(scheduleId);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('∫∏∞≠¿Ã ªË¡¶µ«æ˙Ω¿¥œ¥Ÿ.')));
                        _fetchData();
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('ªË¡¶')),
              ElevatedButton(
                  onPressed: () async {
                    try {
                      final dateStr =
                          DateFormat('yyyy-MM-dd').format(selectedDate);
                      final h = selectedTime.hour.toString().padLeft(2, '0');
                      final m = selectedTime.minute.toString().padLeft(2, '0');

                      final payload = {
                        'subject': selectedSubject,
                        'new_date': dateStr,
                        'new_start_time': '$h:$m',
                        'note': noteController.text,
                      };

                      await _academyService.updateTemporarySchedule(
                          scheduleId, payload);

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('∫∏∞≠ Ω√∞£¿Ã ºˆ¡§µ«æ˙Ω¿¥œ¥Ÿ.')));
                        _fetchData(); // Refresh UI
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('¿˙¿Â')),
            ],
          );
        });
      },
    );
  }

  TimeOfDay _parseTimeOfDay(String? value) {
    if (value == null || value.isEmpty) {
      return TimeOfDay.now();
    }
    final parts = value.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return TimeOfDay(hour: hour, minute: minute);
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
        title: const Text('Ï∂úÍ≤∞ ?ïÏù∏'),
        content: const Text('Í≤∞ÏÑù Ï≤òÎ¶¨???ôÏÉù?ÖÎãà??\n?ºÏ?Î•??ëÏÑ±?òÎ†§Î©?Ï∂úÏÑù ?ÅÌÉúÎ•?Î≥ÄÍ≤ΩÌï¥???©Îãà??'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ï∑®ÏÜå'),
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
                        const SnackBar(content: Text('Ï∂úÏÑù?ºÎ°ú Î≥ÄÍ≤ΩÎêò?àÏäµ?àÎã§.')));
                    _fetchDailyData(_selectedDate); // Refresh status
                  }
                }
              } catch (e) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Ï∂úÏÑù?ºÎ°ú Î≥ÄÍ≤?),
          ),
        ],
      ),
    );
  }
}

