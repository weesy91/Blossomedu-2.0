import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import '../../../core/services/academy_service.dart';

class TeacherStudentPlannerScreen extends StatefulWidget {
  final String studentId;
  const TeacherStudentPlannerScreen({required this.studentId, super.key});

  @override
  State<TeacherStudentPlannerScreen> createState() =>
      _TeacherStudentPlannerScreenState();
}

class _TeacherStudentPlannerScreenState
    extends State<TeacherStudentPlannerScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = true;
  List<dynamic> _assignments = [];
  String _studentName = '학생';

  // [NEW] Books for Dialog
  List<Map<String, dynamic>> _vocabBooks = [];
  List<Map<String, dynamic>> _textbooks = [];

  // Timeline State
  late DateTime _startDate;
  late List<DateTime> _weekDates;
  late DateTime _selectedDate;

  final ScrollController _scrollController = ScrollController(); // [NEW]

  @override
  void initState() {
    super.initState();
    _initializeDates();
    _fetchData();
  }

  void _initializeDates() {
    final now = DateTime.now();
    // [FIX] User requested +/- 2 weeks range
    final start = now.subtract(const Duration(days: 14));
    _startDate = DateTime(start.year, start.month, start.day);

    // Total 29 days (14 before + today + 14 after)
    _weekDates = List.generate(29, (i) => _startDate.add(Duration(days: i)));

    // Default selection is Today
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  void _scrollToToday() {
    print('[DEBUG] _scrollToToday called');
    print('[DEBUG] hasClients: ${_scrollController.hasClients}');

    if (!_scrollController.hasClients) {
      print('[DEBUG] No clients attached, aborting scroll');
      return;
    }

    final now = DateTime.now();
    final todayIndex = _weekDates.indexWhere((d) => _isSameDay(d, now));
    print('[DEBUG] todayIndex: $todayIndex');

    if (todayIndex != -1) {
      // Small delay to ensure layout is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_scrollController.hasClients) {
          final offset = (todayIndex * 100.0);
          print('[DEBUG] Scrolling to offset: $offset');
          _scrollController.jumpTo(offset);
        }
      });
    }
  }

  Future<void> _fetchData() async {
    final sId = int.tryParse(widget.studentId);
    if (sId == null) return;

    setState(() => _isLoading = true);
    try {
      final studentFuture = _academyService.getStudent(sId);
      final assignmentFuture = _academyService.getAssignments(studentId: sId);
      final logFuture = _academyService.getClassLogs(studentId: sId);
      final bookFuture = _academyService.getTextbooks();
      final vocabFuture = _academyService.getVocabBooks();

      final results = await Future.wait([
        studentFuture,
        assignmentFuture,
        logFuture,
        bookFuture,
        vocabFuture
      ]);

      final studentData = results[0] as Map<String, dynamic>;
      final assignmentList = results[1] as List<dynamic>;
      final logList = results[2] as List<dynamic>;
      final textbooks = results[3] as List<dynamic>;
      final vocabBooks = results[4] as List<dynamic>;

      // Merge Data
      List<dynamic> merged = [];

      // 1. Assignments
      for (var a in assignmentList) {
        merged.add({
          'id': 'a_${a['id']}',
          'title': a['title'] ?? '과제',
          'type': '과제',
          'due_date': a['due_date'], // DateTime string
          'is_completed': a['is_completed'] ?? false,
        });
      }

      // 2. Class Log Homework
      for (var log in logList) {
        if (log['assignment_title'] != null &&
            log['assignment_title'].toString().isNotEmpty) {
          merged.add({
            'id': 'l_${log['id']}',
            'title': log['assignment_title'],
            'type': '숙제', // From Class Log
            'due_date':
                log['hw_due_date'] ?? log['date'], // fallback to class date
            'is_completed': false, // No completion status in ClassLog yet?
          });
        }
      }

      if (mounted) {
        setState(() {
          _studentName = studentData['name'] ?? '학생';
          _assignments = merged;
          _textbooks = textbooks.map((e) => e as Map<String, dynamic>).toList();
          _vocabBooks =
              vocabBooks.map((e) => e as Map<String, dynamic>).toList();
          _isLoading = false;
        });
        // [FIX] Move outside setState so layout is complete
        WidgetsBinding.instance.addPostFrameCallback((_) {
          print('[DEBUG] PostFrameCallback executed, calling _scrollToToday');
          _scrollToToday();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로딩 실패: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // Helper to check if two dates are same day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<dynamic> _getAssignmentsForDate(DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _assignments.where((a) {
      final dueDate = a['due_date']?.toString();
      if (dueDate == null) return false;
      return dueDate.startsWith(dateStr);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$_studentName의 위클리 플래너'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
            onPressed: _showAddAssignmentDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Left Sidebar: Vertical Timeline
                SizedBox(
                  width: 100,
                  child: ListView.builder(
                    controller: _scrollController, // [NEW] Attach controller
                    itemExtent:
                        100, // [FIX] Force fixed item height for accurate scrolling
                    itemCount: _weekDates.length,
                    itemBuilder: (context, index) {
                      return _buildTimelineTile(
                          _weekDates[index], index == _weekDates.length - 1);
                    },
                  ),
                ),
                // Vertical Divider Line (Visual separation)
                Container(width: 1, color: Colors.grey.shade200),

                // 2. Right Content: Assignments List
                Expanded(
                  child: Container(
                    color: Colors.grey.shade50,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDateHeader(_selectedDate),
                        const SizedBox(height: 24),
                        Expanded(child: _buildAssignmentList()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // --- Widgets ---

  Widget _buildTimelineTile(DateTime date, bool isLast) {
    final isSelected = _isSameDay(date, _selectedDate);
    final isToday = _isSameDay(date, DateTime.now());

    return InkWell(
      onTap: () => setState(() => _selectedDate = date),
      child: Container(
        height: 100, // Fixed height for timeline spacing
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Vertical Line
            if (!isLast)
              Positioned(
                top: 50, // Start from center
                bottom: -50, // Extend to next tile center
                child: Container(
                  width: 2,
                  color: Colors.indigo.withOpacity(0.2),
                ),
              ),
            // Vertical Line (Connector from top if not first)
            // Simplified: Just draw full line and cover?
            // Let's draw line centered.
            Positioned(
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: isLast
                      ? Colors.transparent
                      : Colors.indigo.withOpacity(0.1),
                  // Note: Logic for line needs care.
                  // Simple approach: Line is background. Node is foreground.
                )),

            // Node + Date Text
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Date Text (Left of line? or Right? User said "Date on left of line")
                // Let's put info centered.
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('MM.dd').format(date),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.indigo : Colors.grey,
                      ),
                    ),
                    Text(
                      DateFormat('EEE', 'ko_KR')
                          .format(date), // Requires initializeDateFormatting
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isToday
                            ? Colors.red
                            : (isSelected ? Colors.indigo : Colors.black),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Node
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: isSelected ? Colors.indigo : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isSelected
                                  ? Colors.indigo
                                  : Colors.indigo.withOpacity(0.3),
                              width: 2)),
                    ),
                    if (_getAssignmentsForDate(date).isNotEmpty)
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
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        if (_isSameDay(date, DateTime.now()))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Today',
                style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          )
      ],
    );
  }

  Widget _buildAssignmentList() {
    final items = _getAssignmentsForDate(_selectedDate);

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '일정이 없습니다.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _showAddAssignmentDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('일정 추가'),
            )
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (c, i) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildAssignmentCard(item);
      },
    );
  }

  Widget _buildAssignmentCard(Map<String, dynamic> item) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
          border: Border(
              left: BorderSide(color: _getTypeColor(item['type']), width: 4))),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: _getTypeColor(item['type']).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4)),
            child: Text(item['type'] ?? '과제',
                style: TextStyle(
                    color: _getTypeColor(item['type']),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item['title'],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                item['due_date'] != null
                    ? (() {
                        try {
                          final d = DateTime.parse(item['due_date']);
                          return DateFormat('M월 d일 a h:mm', 'ko_KR').format(d);
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
          IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () async {
                // Delete logic
                final idStr = item['id'].toString(); // e.g. "a_12" or "l_34"
                if (!idStr.startsWith('a_')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('수업일지 과제는 삭제할 수 없습니다.')));
                  return;
                }

                final realId = int.tryParse(idStr.substring(2));
                if (realId == null) return;

                final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                            title: const Text('과제 삭제'),
                            content: const Text('정말 이 과제를 플래너에서 삭제하시겠습니까?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('취소'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('삭제',
                                    style: TextStyle(color: Colors.red)),
                              )
                            ]));

                if (confirm == true) {
                  try {
                    await _academyService.deleteAssignment(realId);
                    _fetchData(); // Refresh list
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('삭제되었습니다.')));
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
                    }
                  }
                }
              })
        ],
      ),
    );
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case '단어':
        return Colors.redAccent;
      case '구문':
        return Colors.indigo;
      case '독해':
        return Colors.teal;
      case '수업':
        return Colors.purple;
      default:
        return Colors.blueAccent;
    }
  }

  Future<void> _showAddAssignmentDialog() async {
    // Default: Selected Date 22:00
    DateTime dueDate = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, 22, 0);

    // State for Tabs
    int? selectedVocabBookId;
    final startDayController = TextEditingController();
    final endDayController = TextEditingController();

    // [NEW] Wrong Answer Mode
    bool isWrongAnswers = false;
    final wrongCountController = TextEditingController(text: '30');

    int? selectedTextbookId;
    final manualTitleController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            title: const Text('과제 추가'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Colors.indigo,
                    unselectedLabelColor: Colors.grey,
                    tabs: [
                      Tab(text: '단어 과제'),
                      Tab(text: '일반/교재 과제'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 350, // [FIX] Increased height
                    child: TabBarView(
                      children: [
                        // Tab 1: Vocab
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                    labelText: '단어장 선택',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12)),
                                value: selectedVocabBookId,
                                isExpanded: true,
                                items: _vocabBooks.map((b) {
                                  return DropdownMenuItem<int>(
                                    value: b['id'],
                                    child: Text(
                                      '[${b['publisher_name'] ?? b['publisher']}] ${b['title']}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  );
                                }).toList(),
                                onChanged: isWrongAnswers
                                    ? null
                                    : (v) => setDialogState(
                                        () => selectedVocabBookId = v),
                              ),
                              const SizedBox(height: 12),

                              // [NEW] Wrong Answer Toggle
                              CheckboxListTile(
                                title: const Text('오답 단어 복습 (Day 범위 비활성)'),
                                value: isWrongAnswers,
                                onChanged: (val) {
                                  setDialogState(() {
                                    isWrongAnswers = val ?? false;
                                    if (isWrongAnswers) {
                                      selectedVocabBookId =
                                          null; // Clear selection
                                    }
                                  });
                                },
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),

                              if (isWrongAnswers)
                                TextField(
                                  controller: wrongCountController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '복습할 단어 개수',
                                    hintText: '예: 30',
                                    border: OutlineInputBorder(),
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: startDayController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: '시작 Day',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('~'),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: endDayController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: '종료 Day',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),

                        // Tab 2: Manual / Textbook
                        SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                    labelText: '교재 선택 (필수)', // [FIX] Required
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12)),
                                value: selectedTextbookId,
                                isExpanded: true,
                                // [FIX] Removed "Direct Input" option
                                items: _textbooks.map((b) {
                                  return DropdownMenuItem<int>(
                                    value: b['id'],
                                    child: Text(
                                      '[${b['category']}] ${b['title']}',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (v) => setDialogState(
                                    () => selectedTextbookId = v),
                              ),
                              if (_textbooks.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text('등록된 교재가 없습니다. 관리자에게 문의하세요.',
                                      style: TextStyle(
                                          color: Colors.red.shade400,
                                          fontSize: 12)),
                                ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: manualTitleController,
                                decoration: const InputDecoration(
                                  labelText: '과제 내용 / 범위',
                                  hintText: '예: 10~20페이지 풀기',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Common: Due Date
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      const Text('마감: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                              context: context,
                              initialDate: dueDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030));
                          if (d != null) {
                            final t = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(dueDate));
                            if (t != null) {
                              setDialogState(() {
                                dueDate = DateTime(
                                    d.year, d.month, d.day, t.hour, t.minute);
                              });
                            }
                          }
                        },
                        child: Text(
                          DateFormat('M월 d일 a h:mm', 'ko_KR').format(dueDate),
                          style: const TextStyle(
                              color: Colors.indigo,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Map<String, dynamic>? payload;

                  final sStart = startDayController.text.trim();
                  final sEnd = endDayController.text.trim();
                  final mTitle = manualTitleController.text.trim();

                  // Determine active tab context implicitly
                  bool isVocabFlow = (selectedVocabBookId != null &&
                          (isWrongAnswers ||
                              (sStart.isNotEmpty && sEnd.isNotEmpty))) ||
                      (isWrongAnswers && wrongCountController.text.isNotEmpty);
                  bool isManualFlow =
                      selectedTextbookId != null && mTitle.isNotEmpty;

                  try {
                    if (isVocabFlow) {
                      String title = '';
                      int? start;
                      int? end;

                      if (isWrongAnswers) {
                        final count = wrongCountController.text;
                        title = '🔥 오답 단어 복습 (${count}개)';
                        start = 0;
                        end = int.tryParse(count) ?? 30; // Store count in end
                      } else {
                        final book = _vocabBooks
                            .firstWhere((b) => b['id'] == selectedVocabBookId);
                        title = '[${book['title']}] Day $sStart-$sEnd';
                        start = int.tryParse(sStart);
                        end = int.tryParse(sEnd);
                      }

                      payload = {
                        'student': widget.studentId, // [FIX] Use 'student'
                        'title': title,
                        'due_date': dueDate.toIso8601String(),
                        'assignment_type': 'VOCAB_TEST',
                        'related_vocab_book': selectedVocabBookId,
                        'vocab_range_start': start ?? 0,
                        'vocab_range_end': end ?? 0,
                        'is_cumulative': isWrongAnswers, // [NEW] Pass flag
                      };
                    } else if (isManualFlow) {
                      final book = _textbooks
                          .firstWhere((b) => b['id'] == selectedTextbookId);
                      String title = '[${book['title']}] $mTitle';

                      payload = {
                        'student': widget.studentId, // [FIX] Use 'student'
                        'title': title,
                        'due_date': dueDate.toIso8601String(),
                        'assignment_type': 'MANUAL',
                      };
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('필수 정보를 입력해주세요. (단어장+범위 또는 교재+내용)')));
                      return;
                    }

                    await _academyService.createAssignment(payload);
                    if (mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('일정이 추가되었습니다.')));
                      _fetchData();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('오류 발생: $e')));
                    }
                  }
                },
                child: const Text('생성'),
              ),
            ],
          ),
        );
      }),
    );
  }
}
