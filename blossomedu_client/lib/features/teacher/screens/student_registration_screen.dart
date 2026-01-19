import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class StudentRegistrationScreen extends StatefulWidget {
  const StudentRegistrationScreen({super.key});

  @override
  State<StudentRegistrationScreen> createState() =>
      _StudentRegistrationScreenState();
}

class _StudentRegistrationScreenState extends State<StudentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _academyService = AcademyService();
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Metadata
  List<dynamic> _schools = [];
  List<dynamic> _teachers = [];
  List<dynamic> _classes = [];
  int? _defaultBranchId; // Not used in UI yet, but sent back if needed

  // Form Data
  String _name = '';
  String _phone = '';
  String _parentPhoneMom = '';
  String _parentPhoneDad = '';
  String _username = '';
  String _password = '1234'; // Default password

  int? _selectedSchoolId;
  int _selectedGrade = 7; // M1 (Default)
  DateTime? _startDate;

  int? _syntaxTeacherId;
  int? _readingTeacherId;
  int? _extraTeacherId;

  int? _syntaxClassId;
  int? _readingClassId;
  int? _extraClassId;

  // Branch Name from Metadata
  String _branchName = '';

  @override
  void initState() {
    super.initState();
    _fetchMetadata();
  }

  Future<void> _fetchMetadata() async {
    try {
      final data = await _academyService.getRegistrationMetadata();
      if (mounted) {
        setState(() {
          _schools = data['schools'] ?? [];
          _teachers = data['teachers'] ?? [];
          _classes = data['classes'] ?? [];
          _bookedSyntaxSlots = data['booked_syntax_slots'] ?? []; // [NEW]
          _defaultBranchId = data['default_branch_id'];
          _branchName = data['default_branch_name'] ?? '지점 미정';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메타데이터 로딩 실패: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수업 시작일을 선택해주세요')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final Map<String, dynamic> payload = {
        'username': _username,
        'password': _password,
        'name': _name,
        'phone_number': _phone,
        'parent_phone_mom': _parentPhoneMom,
        'parent_phone_dad': _parentPhoneDad, // [NEW]
        'start_date':
            _startDate!.toIso8601String().split('T')[0], // [NEW] YYYY-MM-DD
        'grade': _selectedGrade,
        'branch_id': _defaultBranchId, // Correctly using the ID from metadata
        'school_id': _selectedSchoolId,
        'syntax_teacher_id': _syntaxTeacherId,
        'reading_teacher_id': _readingTeacherId,
        'extra_teacher_id': _extraTeacherId,
        'syntax_class_id': _syntaxClassId,
        'reading_class_id': _readingClassId,
        'extra_class_id': _extraClassId,
        'extra_class_category': _extraClassCategory, // [NEW]
      };

      await _academyService.registerStudent(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('학생이 등록되었습니다.')),
        );
        context.pop(true); // Return success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('등록 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('학생 등록')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Account Creation (Moved to Top)
                    _buildSectionTitle('계정 생성'),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: '아이디 (ID) *',
                        helperText: '학생이 로그인할 때 사용할 ID입니다.',
                        prefixIcon: Icon(Icons.account_circle),
                      ),
                      validator: (v) => v!.isEmpty ? 'ID를 입력하세요' : null,
                      onSaved: (v) => _username = v!,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: _password,
                      decoration: const InputDecoration(
                        labelText: '비밀번호 *',
                        helperText: '기본값: 1234',
                        prefixIcon: Icon(Icons.lock),
                      ),
                      validator: (v) => v!.isEmpty ? '비밀번호를 입력하세요' : null,
                      onSaved: (v) => _password = v!,
                    ),
                    const SizedBox(height: 32),

                    // 2. Basic Info
                    _buildSectionTitle('기본 정보'),
                    // Branch info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.business, color: Colors.indigo),
                          const SizedBox(width: 8),
                          Text('소속 분원: $_branchName',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(labelText: '이름 *'),
                      validator: (v) => v!.isEmpty ? '이름을 입력하세요' : null,
                      onSaved: (v) => _name = v!,
                    ),
                    const SizedBox(height: 16),
                    // Start Date Picker
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) setState(() => _startDate = date);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '수업 시작일 *',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _startDate == null
                              ? '날짜 선택'
                              : _startDate!.toString().split(' ')[0],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(labelText: '학생 전화번호 *'),
                      keyboardType: TextInputType.phone,
                      validator: (v) =>
                          v!.isEmpty ? '전화번호를 입력하세요' : null, // [Required]
                      onSaved: (v) => _phone = v ?? '',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                                labelText: '모(Mother) 연락처 *'),
                            keyboardType: TextInputType.phone,
                            validator: (v) =>
                                v!.isEmpty ? '연락처를 입력하세요' : null, // [Required]
                            onSaved: (v) => _parentPhoneMom = v ?? '',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                                labelText: '부(Father) 연락처 *'), // [NEW]
                            keyboardType: TextInputType.phone,
                            validator: (v) =>
                                v!.isEmpty ? '연락처를 입력하세요' : null, // [Required]
                            onSaved: (v) => _parentPhoneDad = v ?? '',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: '학교'),
                      items: _schools.map<DropdownMenuItem<int>>((s) {
                        return DropdownMenuItem(
                          value: s['id'],
                          child: Text(s['name']),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedSchoolId = v),
                      onSaved: (v) => _selectedSchoolId = v,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: _selectedGrade,
                      decoration: const InputDecoration(labelText: '학년'),
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('중1')),
                        DropdownMenuItem(value: 8, child: Text('중2')),
                        DropdownMenuItem(value: 9, child: Text('중3')),
                        DropdownMenuItem(value: 10, child: Text('고1')),
                        DropdownMenuItem(value: 11, child: Text('고2')),
                        DropdownMenuItem(value: 12, child: Text('고3')),
                      ],
                      onChanged: (v) => setState(() => _selectedGrade = v!),
                    ),
                    const SizedBox(height: 32),

                    // 3. Merged Assignments
                    _buildSectionTitle('선생님 및 시간표 배정'),
                    _buildMergedAssignmentRow('구문 (Syntax)',
                        sectionType: 'SYNTAX',
                        dataType: 'SYNTAX',
                        onTeacherSaved: (t) => _syntaxTeacherId = t,
                        onClassSaved: (c) => _syntaxClassId = c),
                    const SizedBox(height: 16),
                    _buildMergedAssignmentRow(
                      '독해 (Reading)',
                      sectionType: 'READING',
                      dataType: 'READING',
                      onTeacherSaved: (t) => _readingTeacherId = t,
                      onClassSaved: (c) => _readingClassId = c,
                    ),
                    const SizedBox(height: 16),

                    _buildMergedAssignmentRow(
                      '특강 (Extra)',
                      sectionType: 'EXTRA', // Shows it's the 3rd section
                      dataType: _extraClassCategory ??
                          'EXTRA', // Shows what data to load
                      onTeacherSaved: (id) => _extraTeacherId = id,
                      onClassSaved: (id) => _extraClassId = id,
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text('등록하기',
                                style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo)),
        const Divider(thickness: 1.5, height: 24),
      ],
    );
  }

  // State for Day Selection
  String? _selectedSyntaxDay;
  String? _selectedReadingDay;
  String? _selectedExtraDay;

  String? _extraClassCategory; // [NEW] ('SYNTAX', 'READING', 'MOCK')

  List<dynamic> _bookedSyntaxSlots = []; // [NEW]

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
    // MOCK teachers? Assuming Reading teachers handle Mock for now, or all teachers.
    // IF Extra Category is Mock, maybe Filter Reading Teachers? For now, All Teachers if not Syntax/Reading specific.

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

    // Get selected day based on sectionType (The Form Field Identity)
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
        // [REMOVED] Internal Extra Dropdown (Moved to parent)
        Row(
          children: [
            // [NEW] 0. Extra Category Selector (Only if sectionType == EXTRA)
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
                  // Availability Check (Only for SYNTAX)
                  bool isBooked = false;

                  // Rule: Syntax (Main) or Extra (if Category is Syntax) needs locking 1:1
                  bool checkLock = false;
                  if (dataType == 'SYNTAX') checkLock = true;
                  // If extra is syntax, locking applies. dataType handles this if category is passed correctly.

                  if (checkLock && selectedTeacherId != null) {
                    isBooked = _bookedSyntaxSlots.any((slot) =>
                        slot['syntax_teacher_id'] == selectedTeacherId &&
                        slot['syntax_class_id'] == c['id']);
                  }

                  // [NEW] Cross-Validation (Self-Collision) - must match BOTH time AND day
                  if (!isBooked) {
                    String myTime = c['time'] ?? '';
                    String myDay = c['day'] ?? '';

                    // Get clash times and days safely
                    String syntaxTime = '';
                    String syntaxDay = '';
                    if (_syntaxClassId != null) {
                      try {
                        final cl = _classes.firstWhere(
                            (element) => element['id'] == _syntaxClassId);
                        syntaxTime = cl['time'] ?? '';
                        syntaxDay = cl['day'] ?? '';
                      } catch (e) {/* */}
                    }
                    String readingTime = '';
                    String readingDay = '';
                    if (_readingClassId != null) {
                      try {
                        final cl = _classes.firstWhere(
                            (element) => element['id'] == _readingClassId);
                        readingTime = cl['time'] ?? '';
                        readingDay = cl['day'] ?? '';
                      } catch (e) {/* */}
                    }
                    String extraTime = '';
                    String extraDay = '';
                    if (_extraClassId != null) {
                      try {
                        final cl = _classes.firstWhere(
                            (element) => element['id'] == _extraClassId);
                        extraTime = cl['time'] ?? '';
                        extraDay = cl['day'] ?? '';
                      } catch (e) {/* */}
                    }

                    // Collision Check Logic - Only collide if BOTH time AND day match
                    // If I am Extra (sectionType == EXTRA), I must not clash with Syntax or Reading
                    if (sectionType == 'EXTRA') {
                      if (syntaxTime.isNotEmpty &&
                          myTime == syntaxTime &&
                          myDay == syntaxDay) isBooked = true;
                      if (readingTime.isNotEmpty &&
                          myTime == readingTime &&
                          myDay == readingDay) isBooked = true;
                    }
                    // If I am Syntax (sectionType == SYNTAX), I must not clash with Extra
                    else if (sectionType == 'SYNTAX') {
                      if (extraTime.isNotEmpty &&
                          myTime == extraTime &&
                          myDay == extraDay) isBooked = true;
                    }
                    // If I am Reading (sectionType == READING), I must not clash with Extra
                    else if (sectionType == 'READING') {
                      if (extraTime.isNotEmpty &&
                          myTime == extraTime &&
                          myDay == extraDay) isBooked = true;
                    }
                  }

                  // Format Label Cleanly
                  // 1. Calculate End Time based on dataType (the actual class type)
                  String startTime = c['time'] ?? '';
                  String endTimeStr = '';

                  if (startTime.isNotEmpty) {
                    try {
                      final parts = startTime.split(':');
                      final h = int.parse(parts[0]);
                      final m = int.parse(parts[1]);
                      final startDt = DateTime(2022, 1, 1, h, m);

                      int duration = 30; // Default
                      if (dataType == 'SYNTAX') duration = 80;
                      if (dataType == 'READING') duration = 90;
                      if (dataType == 'MOCK') duration = 90;
                      // If 'EXTRA' (generic), default 80
                      if (dataType == 'EXTRA') duration = 80;

                      final endDt = startDt.add(Duration(minutes: duration));
                      endTimeStr =
                          "${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}";
                    } catch (e) {/*Ignore*/}
                  }

                  String label = startTime;
                  if (endTimeStr.isNotEmpty) {
                    label = "$startTime - $endTimeStr";
                  }

                  if (isBooked) label += " (마감)";

                  return DropdownMenuItem(
                    value: c['id'],
                    enabled: !isBooked,
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style:
                          isBooked ? const TextStyle(color: Colors.grey) : null,
                    ),
                  );
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
        )
      ],
    );
  }
}
