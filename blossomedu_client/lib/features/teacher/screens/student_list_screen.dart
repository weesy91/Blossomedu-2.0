import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/services/academy_service.dart';

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = true;
  List<dynamic> _students = [];

  // Date State
  late DateTime _selectedDate;
  late List<DateTime> _weekDates;
  // bool _showScheduledOnly = true; // [REMOVED] Always show by date

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _fetchStudents();
  }

  void _initializeDates() {
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _generateWeekDates();
  }

  void _generateWeekDates() {
    // Generate 7 days centered on selected date?
    // Or just start from selected date?
    // User wants to scroll. Let's center it.
    final start = _selectedDate.subtract(const Duration(days: 3));
    _weekDates = List.generate(7, (i) => start.add(Duration(days: i)));
  }

  String _getDayCode(DateTime date) {
    const codes = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return codes[date.weekday - 1];
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // [NEW] Getter for filtered list
  List<dynamic> get _filteredStudents {
    return _students.where((s) {
      return (s['name'] ?? '').toString().contains(_searchQuery);
    }).toList();
  }

  void _applyFilter() {
    setState(() {});
  }

  Future<void> _fetchStudents() async {
    setState(() => _isLoading = true);
    try {
      // Always filter by selected date
      final dayParam = _getDayCode(_selectedDate);

      final data = await _academyService.getStudents(day: dayParam);
      if (!mounted) return;

      setState(() {
        _students = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('학생 목록 로딩 실패: $e')),
        );
      }
    }
  }

  // --- Attendance Logic ---
  Future<void> _handleLogCreation(Map<String, dynamic> student) async {
    final studentId = student['id'];
    final name = student['name'];

    // 1. Check existing attendance
    try {
      final existing =
          await _academyService.checkAttendance(studentId, _selectedDate);

      if (!mounted) return; // [FIX]

      if (existing != null) {
        // Already recorded
        // If Absent, warn?
        if (existing['status'] == 'ABSENT') {
          _showAbsentDialog(name); // Just info
        } else {
          _navigateToLogCreate(student);
        }
      } else {
        // 2. Ask for Attendance
        _showAttendanceDialog(student);
      }
    } catch (e) {
      if (!mounted) return; // [FIX]
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('오류: $e')));
    }
  }

  void _showAttendanceDialog(Map<String, dynamic> student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${student['name']} 학생 출석 확인'),
        content:
            Text('${DateFormat('M월 d일').format(_selectedDate)} 출석 여부를 체크해주세요.'),
        actions: [
          TextButton(
            onPressed: () => _submitAttendance(student, 'ABSENT'),
            child:
                const Text('결석 (수업 없음)', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => _submitAttendance(student, 'LATE'),
            child: const Text('지각'),
          ),
          ElevatedButton(
            onPressed: () => _submitAttendance(student, 'PRESENT'),
            child: const Text('출석'),
          ),
        ],
      ),
    );
  }

  void _showAbsentDialog(String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('결석 처리됨'),
        content: Text('$name 학생은 결석으로 처리되어 있습니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<void> _submitAttendance(
      Map<String, dynamic> student, String status) async {
    // [FIX] Pop from Root Navigator because showDialog uses Root Navigator by default.
    // Previous "Navigator.pop(context)" was popping the StudentListScreen itself from the ShellBranch navigator!
    Navigator.of(context, rootNavigator: true).pop();
    try {
      await _academyService.createAttendance(
          student['id'], status, _selectedDate);

      if (!mounted) return; // [FIX] Prevent use of unmounted context

      if (status == 'ABSENT') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('결석 처리되었습니다.')));
      } else {
        _navigateToLogCreate(student);
      }
    } catch (e) {
      if (!mounted) return; // [FIX]
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
    }
  }

  void _navigateToLogCreate(Map<String, dynamic> student) {
    // Pass selected date!
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    context.push(Uri(path: '/teacher/class_log/create', queryParameters: {
      'studentId': student['id'].toString(),
      'studentName': student['name'],
      'date': dateStr // Pre-fill date
    }).toString());
  }

  // Helpers
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      locale: const Locale('ko', 'KR'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _generateWeekDates();
        _fetchStudents();
      });
    }
  }

  void _prevWeek() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 7));
      _generateWeekDates();
      _fetchStudents();
    });
  }

  void _nextWeek() {
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 7));
      _generateWeekDates();
      _fetchStudents();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('학생 관리'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          // [NEW] Calendar Picker (Moved to AppBar)
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month, color: Colors.indigo),
            tooltip: '날짜 선택',
          ),
          // Removed redundant "Show Scheduled Only" button
        ],
      ),
      body: Column(
        children: [
          // 1. Date Strip (Always Visible)
          Container(
            height: 80,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: _prevWeek,
                  icon: const Icon(Icons.chevron_left, color: Colors.indigo),
                  tooltip: '이전 주',
                ),
                Expanded(
                  child: Center(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                        },
                      ),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true, // Centers the list if it fits
                        physics: const BouncingScrollPhysics(),
                        itemCount: _weekDates.length,
                        itemBuilder: (context, index) {
                          final date = _weekDates[index];
                          final isSelected = isSameDay(date, _selectedDate);
                          final isToday = isSameDay(date, DateTime.now());

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedDate = date;
                                _fetchStudents();
                              });
                            },
                            child: Container(
                              width: 60,
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.indigo
                                    : (isToday
                                        ? Colors.indigo.shade50
                                        : Colors.white),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: isSelected
                                        ? Colors.indigo
                                        : Colors.grey.shade300),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    DateFormat('E', 'ko_KR').format(date),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    date.day.toString(),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ), // Close Expanded
                ),
                IconButton(
                  onPressed: _nextWeek,
                  icon: const Icon(Icons.chevron_right, color: Colors.indigo),
                  tooltip: '다음 주',
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Filters & Search
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: SearchBar(
                    hintText: '학생 검색...',
                    leading: const Icon(Icons.search),
                    elevation: WidgetStateProperty.all(0),
                    backgroundColor: WidgetStateProperty.all(Colors.white),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                        _applyFilter();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // Toggle Button REMOVED
              ],
            ),
          ),

          // Student List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredStudents.length,
                    itemBuilder: (context, index) {
                      final student = _filteredStudents[index];
                      // Determine status based on _selectedDate attendance
                      // We don't have attendance status in student list yet,
                      // assume 'pending' or fetch if possible.
                      // For now, simple card.

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.indigo.shade50,
                                    child: Text(
                                        student['name'].isNotEmpty
                                            ? student['name'][0]
                                            : '?',
                                        style: TextStyle(
                                            color: Colors.indigo.shade700,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(student['name'] ?? '이름 없음',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                          '${student['school'] ?? '학교 미정'} • ${student['grade'] ?? ''}',
                                          style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12)),
                                    ],
                                  ),
                                  const Spacer(),
                                  // Quick Status (Optional)
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _buildActionBtn(
                                      Icons.edit_note,
                                      '일지 작성',
                                      Colors.blue,
                                      () => _handleLogCreation(
                                          student)), // Updated Action
                                  _buildActionBtn(Icons.assignment_ind, '학습 로그',
                                      Colors.orange, () {
                                    // [FIX] Navigate to Class Log Tab (Tab 1)
                                    context.push(
                                        '/teacher/management/students/${student['id']}?tab=1');
                                  }),
                                  _buildActionBtn(Icons.chat_bubble_outline,
                                      '알림장', Colors.green, () {
                                    // context.push('/teacher/message/create');
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('알림장 기능 준비 중')));
                                  }),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.bold))
          ],
        ),
      ),
    );
  }
}
