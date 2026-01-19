import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart'; // [NEW]
import '../../../core/services/academy_service.dart';

class StudentDetailScreen extends StatefulWidget {
  final int studentId;
  final int initialTabIndex; // [NEW]
  const StudentDetailScreen(
      {super.key, required this.studentId, this.initialTabIndex = 0});

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _academyService = AcademyService();
  bool _isLoading = true;
  bool _isSaving = false;

  // Basic Data
  List<dynamic> _branches = [];
  List<dynamic> _schools = [];

  // Form Fields
  String _name = '';
  String _phone = '';
  String _momPhone = '';
  String _dadPhone = '';
  int? _selectedBranchId;
  int? _selectedSchoolId;
  int _baseGrade = 7;
  String _startDateStr = ''; // [NEW]
  bool _isActive = true;

  // Timetable State
  List<dynamic> _teachers = [];
  List<dynamic> _classes = [];
  List<dynamic> _bookedSyntaxSlots = [];
  List<dynamic> _assignments = [];
  List<dynamic> _classLogs = []; // [NEW]

  int? _syntaxTeacherId;
  int? _readingTeacherId;
  int? _extraTeacherId;

  int? _syntaxClassId;
  int? _readingClassId;
  int? _extraClassId;

  String? _selectedSyntaxDay;
  String? _selectedReadingDay;
  String? _selectedExtraDay;

  String? _extraClassCategory; // [NEW] ('SYNTAX', 'READING', 'MOCK')

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final studentFuture = _academyService.getStudent(widget.studentId);
      final metadataFuture = _academyService.getRegistrationMetadata();
      final assignmentFuture =
          _academyService.getAssignments(studentId: widget.studentId);
      final logFuture =
          _academyService.getClassLogs(studentId: widget.studentId); // [NEW]

      final results = await Future.wait(
          [studentFuture, metadataFuture, assignmentFuture, logFuture]);

      final studentData = results[0] as Map<String, dynamic>;
      final metadata = results[1] as Map<String, dynamic>;
      final assignments = results[2] as List<dynamic>;
      final logs = results[3] as List<dynamic>;

      if (mounted) {
        setState(() {
          // _student = studentData; // Removed unused field

          _branches = metadata['branches'] ?? [];
          _schools = metadata['schools'] ?? [];
          _teachers = metadata['teachers'] ?? [];
          _classes = metadata['classes'] ?? [];
          _bookedSyntaxSlots = metadata['booked_syntax_slots'] ?? [];
          _assignments = assignments;
          _classLogs = logs; // [NEW]

          // Init Form
          _name = studentData['name'] ?? '';
          _phone = studentData['phone_number'] ?? '';
          _momPhone = studentData['parent_phone_mom'] ?? '';
          _dadPhone = studentData['parent_phone_dad'] ?? '';
          _selectedBranchId = studentData['branch'];
          _selectedSchoolId = studentData['school'];
          _baseGrade = studentData['base_grade'] ?? 7;
          _startDateStr = studentData['start_date'] ??
              DateFormat('yyyy-MM-dd').format(DateTime.now()); // [NEW]
          _isActive = studentData['is_active'] ?? true;

          // Init Timetable
          _syntaxTeacherId = studentData['syntax_teacher'];
          _readingTeacherId = studentData['reading_teacher'];
          _extraTeacherId = studentData['extra_class_teacher'];

          _syntaxClassId = studentData['syntax_class'];
          _readingClassId = studentData['reading_class'];
          _extraClassId = studentData['extra_class'];
          _extraClassCategory = studentData['extra_class_category'];

          // Init Days from Classes
          if (_syntaxClassId != null)
            _selectedSyntaxDay = _findDayForClass(_syntaxClassId!);
          if (_readingClassId != null)
            _selectedReadingDay = _findDayForClass(_readingClassId!);
          if (_extraClassId != null)
            _selectedExtraDay = _findDayForClass(_extraClassId!);

          _isLoading = false;
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

  String? _findDayForClass(int classId) {
    try {
      final cls = _classes.firstWhere((c) => c['id'] == classId);
      return cls['day'];
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSaving = true);
    try {
      final payload = {
        'name': _name,
        'phone_number': _phone,
        'parent_phone_mom': _momPhone,
        'parent_phone_dad': _dadPhone,
        'branch': _selectedBranchId,
        'school': _selectedSchoolId,
        'base_grade': _baseGrade,
        'syntax_teacher': _syntaxTeacherId,
        'reading_teacher': _readingTeacherId,
        'extra_class_teacher': _extraTeacherId,
        'syntax_class': _syntaxClassId,
        'reading_class': _readingClassId,
        'extra_class': _extraClassId,
        'extra_class_category': _extraClassCategory,
        'start_date': _startDateStr, // [NEW]
        'user': {'is_active': _isActive}
      };

      await _academyService.updateStudent(widget.studentId, payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수정되었습니다.')),
        );
        context.pop(); // Go back
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteStudent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('계정 삭제'),
        content: const Text(
            '정말로 이 학생 계정을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없으며, 모든 기록이 영구적으로 삭제됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      setState(() => _isLoading = true);
      try {
        await _academyService.deleteStudent(widget.studentId);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('학생 계정이 삭제되었습니다.')));
        context.pop(); // Go back to list
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
          setState(() => _isLoading = false);
        }
      }
    }
  }

  // ... (existing methods: _findDayForClass, _save, _deleteStudent) - Removed placeholder

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('학생 정보')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 5,
      initialIndex: widget.initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name.isNotEmpty ? _name : '학생 정보'),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _isLoading ? null : _deleteStudent,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isSaving ? null : _save,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: '기본 정보'),
              Tab(text: '수업일지'),
              Tab(text: '과제'),
              Tab(text: '단어'),
              Tab(text: '성적'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildInfoTab(),
            _buildClassLogTab(),
            _buildAssignmentTab(),
            _buildVocabTab(),
            _buildGradeTab(),
          ],
        ),
      ),
    );
  }

  /// Tab 1: 기본 정보
  Widget _buildInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Basic Info
            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(labelText: '이름 *'),
              validator: (v) => v!.isEmpty ? '이름을 입력하세요' : null,
              onSaved: (v) => _name = v!,
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _phone,
              decoration: const InputDecoration(labelText: '학생 전화번호 *'),
              validator: (v) => v!.isEmpty ? '전화번호를 입력하세요' : null,
              onSaved: (v) => _phone = v ?? '',
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _momPhone,
              decoration: const InputDecoration(labelText: '어머님 연락처 *'),
              validator: (v) => v!.isEmpty ? '연락처를 입력하세요' : null,
              onSaved: (v) => _momPhone = v ?? '',
            ),
            const SizedBox(height: 16),
            TextFormField(
              initialValue: _dadPhone,
              decoration: const InputDecoration(labelText: '아버님 연락처 *'),
              validator: (v) => v!.isEmpty ? '연락처를 입력하세요' : null,
              onSaved: (v) => _dadPhone = v ?? '',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '지점'),
              value: _selectedBranchId,
              items: _branches.map<DropdownMenuItem<int>>((b) {
                return DropdownMenuItem(value: b['id'], child: Text(b['name']));
              }).toList(),
              onChanged: (v) => setState(() {
                _selectedBranchId = v;
                _selectedSchoolId = null; // Reset school
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '학교'),
              value: _selectedSchoolId,
              items: _schools.where((s) {
                if (_selectedBranchId == null) return true;
                final branches = s['branches'];
                if (branches is List)
                  return branches.contains(_selectedBranchId);
                return true;
              }).map<DropdownMenuItem<int>>((s) {
                return DropdownMenuItem(value: s['id'], child: Text(s['name']));
              }).toList(),
              onChanged: (v) => setState(() => _selectedSchoolId = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              decoration: const InputDecoration(labelText: '학년 (기준 학년)'),
              value: _baseGrade,
              items: const [
                DropdownMenuItem(value: 7, child: Text('중1')),
                DropdownMenuItem(value: 8, child: Text('중2')),
                DropdownMenuItem(value: 9, child: Text('중3')),
                DropdownMenuItem(value: 10, child: Text('고1')),
                DropdownMenuItem(value: 11, child: Text('고2')),
                DropdownMenuItem(value: 12, child: Text('고3')),
              ],
              onChanged: (v) => setState(() => _baseGrade = v ?? 7),
            ),
            const SizedBox(height: 32),

            const Text('배정된 수업 (시간표)',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo)),
            const Divider(),

            // 1. Syntax Section
            _buildMergedAssignmentRow('구문 (Syntax)',
                sectionType: 'SYNTAX',
                dataType: 'SYNTAX',
                onTeacherSaved: (id) => _syntaxTeacherId = id,
                onClassSaved: (id) => _syntaxClassId = id),
            const SizedBox(height: 24),

            // 2. Reading Section
            _buildMergedAssignmentRow('독해 (Reading)',
                sectionType: 'READING',
                dataType: 'READING',
                onTeacherSaved: (id) => _readingTeacherId = id,
                onClassSaved: (id) => _readingClassId = id),
            const SizedBox(height: 24),

            // 3. Extra Section
            _buildMergedAssignmentRow('특강 (Extra)',
                sectionType: 'EXTRA',
                dataType: _extraClassCategory ?? 'EXTRA',
                onTeacherSaved: (id) => _extraTeacherId = id,
                onClassSaved: (id) => _extraClassId = id),

            const SizedBox(height: 24),

            // Start Date Picker & Active Switch
            TextFormField(
              controller: TextEditingController(text: _startDateStr),
              readOnly: true,
              decoration: const InputDecoration(
                labelText: '수업 시작일 (등원일)',
                suffixIcon: Icon(Icons.calendar_today),
                border: OutlineInputBorder(),
              ),
              onTap: () async {
                DateTime initDate = DateTime.now();
                try {
                  initDate = DateTime.parse(_startDateStr);
                } catch (_) {}

                final d = await showDatePicker(
                    context: context,
                    initialDate: initDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030));
                if (d != null) {
                  setState(
                      () => _startDateStr = DateFormat('yyyy-MM-dd').format(d));
                }
              },
            ),
            const SizedBox(height: 24),

            // Active Switch
            SwitchListTile(
              title: const Text('계정 활성화'),
              subtitle: const Text('비활성화 시 로그인이 차단됩니다.'),
              value: _isActive,
              onChanged: (val) => setState(() => _isActive = val),
            ),

            const SizedBox(height: 40),

            // Big Delete Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label:
                    const Text('계정 영구 삭제', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _deleteStudent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab 2: 수업일지 목록
  Widget _buildClassLogTab() {
    if (_classLogs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('작성된 수업일지가 없습니다',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('새 수업일지 작성'),
              onPressed: () {
                context.push(
                    '/teacher/class_log/create?studentId=${widget.studentId}&studentName=$_name');
              },
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _classLogs.length,
      itemBuilder: (context, index) {
        final log = _classLogs[index];
        final date = log['date'] ?? '날짜 미상';
        final teacherName = log['teacher_name'] ?? '선생님';
        final subject = log['subject'] ?? '과목';
        final note = log['note'] ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Colors.indigo.shade50,
              child: Text(subject.isNotEmpty ? subject[0] : '?',
                  style: TextStyle(
                      color: Colors.indigo.shade700,
                      fontWeight: FontWeight.bold)),
            ),
            title: Text('$date - $subject ($teacherName)'),
            subtitle: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('수업 내용',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(note.isEmpty ? '내용 없음' : note),
                    const SizedBox(height: 12),
                    if (log['assignment_title'] != null) ...[
                      Text('배정된 과제',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                          '${log['assignment_title']} (~${log['hw_due_date'] ?? ''})'),
                    ]
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  /// Tab 3: 과제 현황
  Widget _buildAssignmentTab() {
    if (_assignments.isEmpty) {
      return Center(
        child:
            Text('등록된 과제가 없습니다', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _assignments.length,
      itemBuilder: (context, index) {
        final item = _assignments[index];
        final title = item['title'] ?? '과제';
        final dueDate = item['due_date'] ?? '';
        final isCompleted = item['is_completed'] == true;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Icon(
              isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isCompleted ? Colors.green : Colors.grey,
            ),
            title: Text(title,
                style: TextStyle(
                    decoration:
                        isCompleted ? TextDecoration.lineThrough : null)),
            subtitle: Text('마감일: $dueDate'),
            trailing: Icon(Icons.chevron_right, size: 16, color: Colors.grey),
          ),
        );
      },
    );
  }

  /// Tab 4: 단어 학습 기록
  Widget _buildVocabTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.text_fields, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('단어 학습 기록 기능 준비 중',
              style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  /// Tab 5: 성적 및 모의고사
  Widget _buildGradeTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('성적 기록 기능 준비 중', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildMergedAssignmentRow(String title,
      {required String sectionType,
      required String dataType,
      Function(int?)? onTeacherSaved,
      Function(int?)? onClassSaved}) {
    // Filter Teachers
    var teachers = _teachers;
    if (dataType == 'SYNTAX') {
      teachers = _teachers.where((t) => t['is_syntax'] == true).toList();
    } else if (dataType == 'READING') {
      teachers = _teachers.where((t) => t['is_reading'] == true).toList();
    }
    // For MOCK/EXTRA, use all or filter if needed

    // Filter Classes by Type
    final typeClasses = _classes.where((c) => c['type'] == dataType).toList();

    // Extract Unique Days and Sort
    final dayMap = {
      'Mon': '월요일',
      'Tue': '화요일',
      'Wed': '수요일',
      'Thu': '목요일',
      'Fri': '금요일',
      'Sat': '토요일',
      'Sun': '일요일'
    };
    final dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final days = typeClasses
        .map((c) => c['day'] as String?)
        .where((d) => d != null)
        .toSet()
        .toList();

    days.sort((a, b) => dayOrder.indexOf(a!).compareTo(dayOrder.indexOf(b!)));

    // Get selected day based on sectionType
    String? selectedDay;
    int? selectedTeacherId;
    int? selectedClassId;

    if (sectionType == 'SYNTAX') {
      selectedDay = _selectedSyntaxDay;
      selectedTeacherId = _syntaxTeacherId;
      selectedClassId = _syntaxClassId;
    }
    if (sectionType == 'READING') {
      selectedDay = _selectedReadingDay;
      selectedTeacherId = _readingTeacherId;
      selectedClassId = _readingClassId;
    }
    if (sectionType == 'EXTRA') {
      selectedDay = _selectedExtraDay;
      selectedTeacherId = _extraTeacherId;
      selectedClassId = _extraClassId;
    }

    // Filter Classes by Day
    final filteredClasses = typeClasses
        .where((c) => selectedDay == null || c['day'] == selectedDay)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            // 0. Extra Category Selector (Only if sectionType == EXTRA)
            if (sectionType == 'EXTRA') ...[
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '특강 종류'),
                  value: _extraClassCategory,
                  items: const [
                    DropdownMenuItem(value: 'SYNTAX', child: Text('구문')),
                    DropdownMenuItem(value: 'READING', child: Text('독해')),
                    DropdownMenuItem(value: 'MOCK', child: Text('모의고사')),
                    DropdownMenuItem(value: 'EXTRA', child: Text('특강/기타')),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _extraClassCategory = v;
                      // Reset selections
                      _extraTeacherId = null;
                      _selectedExtraDay = null;
                      _extraClassId = null;
                    });
                  },
                  onSaved: (v) => _extraClassCategory = v,
                ),
              ),
              const SizedBox(width: 8),
            ],

            // 1. Teacher
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: '담당 선생님'),
                value: selectedTeacherId,
                items: teachers.map<DropdownMenuItem<int>>((t) {
                  return DropdownMenuItem(
                      value: t['id'], child: Text('${t['name']}'));
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    if (sectionType == 'SYNTAX') _syntaxTeacherId = v;
                    if (sectionType == 'READING') _readingTeacherId = v;
                    if (sectionType == 'EXTRA') _extraTeacherId = v;
                  });
                },
                onSaved: onTeacherSaved,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // 2. Day Selector
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '요일'),
                value: selectedDay,
                items: days.map<DropdownMenuItem<String>>((d) {
                  return DropdownMenuItem(
                      value: d, child: Text(dayMap[d] ?? d!));
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    if (sectionType == 'SYNTAX') {
                      _selectedSyntaxDay = v;
                      _syntaxClassId = null;
                    }
                    if (sectionType == 'READING') {
                      _selectedReadingDay = v;
                      _readingClassId = null;
                    }
                    if (sectionType == 'EXTRA') {
                      _selectedExtraDay = v;
                      _extraClassId = null;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            // 3. Class (Time) Selector
            Expanded(
              flex: 5,
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: '시간 (수업)'),
                isExpanded: true,
                value: selectedClassId,
                items: filteredClasses.map<DropdownMenuItem<int>>((c) {
                  // Availability Check (Copied logic from Registration)
                  bool isBooked = false;
                  bool checkLock = false;
                  if (dataType == 'SYNTAX') checkLock = true;

                  if (checkLock && selectedTeacherId != null) {
                    isBooked = _bookedSyntaxSlots.any((slot) =>
                        slot['syntax_teacher_id'] == selectedTeacherId &&
                        slot['syntax_class_id'] == c['id']);
                  }

                  // Cross-Validation (Self-Collision) - must match BOTH time AND day
                  if (!isBooked) {
                    String myTime = c['time'] ?? '';
                    String myDay = c['day'] ?? '';

                    String syntaxTime = '';
                    String syntaxDay = '';
                    if (_syntaxClassId != null) {
                      try {
                        final syntaxClass = _classes
                            .firstWhere((e) => e['id'] == _syntaxClassId);
                        syntaxTime = syntaxClass['time'] ?? '';
                        syntaxDay = syntaxClass['day'] ?? '';
                      } catch (e) {}
                    }
                    String readingTime = '';
                    String readingDay = '';
                    if (_readingClassId != null) {
                      try {
                        final readingClass = _classes
                            .firstWhere((e) => e['id'] == _readingClassId);
                        readingTime = readingClass['time'] ?? '';
                        readingDay = readingClass['day'] ?? '';
                      } catch (e) {}
                    }
                    String extraTime = '';
                    String extraDay = '';
                    if (_extraClassId != null) {
                      try {
                        final extraClass = _classes
                            .firstWhere((e) => e['id'] == _extraClassId);
                        extraTime = extraClass['time'] ?? '';
                        extraDay = extraClass['day'] ?? '';
                      } catch (e) {}
                    }

                    // Only collide if BOTH time AND day match
                    if (sectionType == 'EXTRA') {
                      if (syntaxTime.isNotEmpty &&
                          myTime == syntaxTime &&
                          myDay == syntaxDay) isBooked = true;
                      if (readingTime.isNotEmpty &&
                          myTime == readingTime &&
                          myDay == readingDay) isBooked = true;
                    } else if (sectionType == 'SYNTAX') {
                      if (extraTime.isNotEmpty &&
                          myTime == extraTime &&
                          myDay == extraDay) isBooked = true;
                    } else if (sectionType == 'READING') {
                      if (extraTime.isNotEmpty &&
                          myTime == extraTime &&
                          myDay == extraDay) isBooked = true;
                    }
                  }

                  // Label Formatting
                  String startTime = c['time'] ?? '';
                  String endTimeStr = '';
                  if (startTime.isNotEmpty) {
                    try {
                      final parts = startTime.split(':');
                      final h = int.parse(parts[0]);
                      final m = int.parse(parts[1]);
                      final startDt = DateTime(2022, 1, 1, h, m);
                      int duration = 30;
                      if (dataType == 'SYNTAX') duration = 80;
                      if (dataType == 'READING') duration = 90;
                      if (dataType == 'MOCK') duration = 90;
                      if (dataType == 'EXTRA') duration = 80;
                      final endDt = startDt.add(Duration(minutes: duration));
                      String endH = endDt.hour.toString().padLeft(2, '0');
                      String endM = endDt.minute.toString().padLeft(2, '0');
                      endTimeStr = '$endH:$endM';
                    } catch (_) {}
                  }

                  return DropdownMenuItem(
                      value: c['id'],
                      enabled: !isBooked, // Disable if booked
                      child: Text(
                        '${c['time']} - $endTimeStr ${isBooked ? '(마감)' : ''}',
                        style: TextStyle(
                          color: isBooked ? Colors.grey : Colors.black,
                        ),
                      ));
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    if (sectionType == 'SYNTAX') _syntaxClassId = v;
                    if (sectionType == 'READING') _readingClassId = v;
                    if (sectionType == 'EXTRA') _extraClassId = v;
                  });
                },
                onSaved: onClassSaved,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
