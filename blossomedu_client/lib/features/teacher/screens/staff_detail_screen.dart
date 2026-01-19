import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class StaffDetailScreen extends StatefulWidget {
  final int staffId;
  const StaffDetailScreen({super.key, required this.staffId});

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _academyService = AcademyService();
  bool _isLoading = true;
  bool _isSaving = false;

  List<dynamic> _branches = [];

  // Form Fields
  String _name = '';
  String _username = ''; // [NEW]
  String? _password; // [NEW]
  String _phoneNumber = ''; // [NEW]
  String _email = ''; // [NEW]
  String _memo = ''; // [NEW]
  int? _selectedBranchId;
  String _position = 'TEACHER';
  DateTime? _joinDate; // [NEW]
  DateTime? _resignationDate; // [NEW]
  bool _isSyntax = false;
  bool _isReading = false;
  bool _isActive = true; // [NEW]

  List<dynamic> _allStaff = []; // [NEW]
  List<int> _managedTeacherUserIds = []; // [NEW]

  final List<Map<String, String>> _positions = [
    {'value': 'TEACHER', 'label': '일반 강사'},
    {'value': 'VICE', 'label': '부원장'},
    {'value': 'PRINCIPAL', 'label': '원장'},
    {'value': 'TA', 'label': '조교'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final staffFuture = _academyService.getStaff(widget.staffId);
      final metadataFuture = _academyService.getStaffRegistrationMetadata();
      final allStaffFuture = _academyService.searchStaff(); // [NEW]

      final results =
          await Future.wait([staffFuture, metadataFuture, allStaffFuture]);
      final staffData = results[0] as Map<String, dynamic>;
      final metadata = results[1] as Map<String, dynamic>;
      final allStaff = results[2] as List<dynamic>;

      if (mounted) {
        setState(() {
          _branches = metadata['branches'] ?? [];
          _allStaff = allStaff;

          // Init Form
          _name = staffData['name'] ?? '';
          _username = staffData['username'] ?? ''; // [NEW]
          _phoneNumber = staffData['phone_number'] ?? ''; // [NEW]
          _email = staffData['email'] ?? ''; // [NEW]
          _memo = staffData['memo'] ?? ''; // [NEW]
          _selectedBranchId = staffData['branch'];
          // [FIX] Normalize position to UpperCase and ensure valid value
          String receivedPos =
              (staffData['position'] ?? 'TEACHER').toString().toUpperCase();
          const validPositions = ['TEACHER', 'VICE', 'PRINCIPAL', 'TA'];
          if (!validPositions.contains(receivedPos)) {
            receivedPos = 'TEACHER'; // Fallback
          }
          _position = receivedPos;

          _isSyntax = staffData['is_syntax_teacher'] ?? false;
          _isReading = staffData['is_reading_teacher'] ?? false;
          _isActive = staffData['is_active'] ?? true; // [NEW]

          if (staffData['managed_teachers'] != null) {
            _managedTeacherUserIds =
                List<int>.from(staffData['managed_teachers']);
          }

          if (staffData['join_date'] != null) {
            _joinDate = DateTime.parse(staffData['join_date']);
          }
          if (staffData['resignation_date'] != null) {
            _resignationDate = DateTime.parse(staffData['resignation_date']);
          }

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSaving = true);
    try {
      final payload = {
        'name': _name,
        'phone_number': _phoneNumber,
        'memo': _memo,
        'username': _username, // [FIX] Top-level for serializer mapping
        'email': _email, // [FIX] Top-level for serializer mapping
        'user': {
          'username': _username,
          'email': _email,
          'is_active': _isActive // Used for manual extraction in backend
        }, // [NEW] Nested user update
        if (_password != null && _password!.isNotEmpty)
          'password': _password, // [NEW]
        'branch': _selectedBranchId,
        'position': _position,
        'is_syntax_teacher': _isSyntax,
        'is_reading_teacher': _isReading,
        if (_joinDate != null)
          'join_date': _joinDate!.toIso8601String().split('T')[0],
        'resignation_date':
            _resignationDate?.toIso8601String().split('T')[0], // Nullable
        if (_position == 'VICE')
          'managed_teachers': _managedTeacherUserIds, // [NEW] Only for VICE
      };

      await _academyService.updateStaff(widget.staffId, payload);

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

  // [NEW] Delete Handler
  Future<void> _deleteStaff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('강사 계정 삭제'),
        content: const Text(
            '정말로 이 강사 계정을 삭제하시겠습니까?\n이 작업은 되돌릴 수 없으며, 모든 기록이 영구적으로 삭제됩니다.'),
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
        await _academyService.deleteStaff(widget.staffId);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('강사 계정이 삭제되었습니다.')));
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('강사 정보 수정')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$_name 정보 수정'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red), // [NEW]
            onPressed: _isLoading ? null : _deleteStaff,
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('계정 정보'),
              TextFormField(
                initialValue: _username,
                decoration: const InputDecoration(
                  labelText: '아이디 (ID)',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v!.isEmpty ? '아이디를 입력하세요' : null,
                onSaved: (v) => _username = v!,
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: '비밀번호 변경',
                  helperText: '변경하지 않으려면 비워두세요',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                onSaved: (v) => _password = v,
              ),
              const SizedBox(height: 32),
              _buildSectionTitle('기본 정보'),
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: '이름'),
                validator: (v) => v!.isEmpty ? '이름을 입력하세요' : null,
                onSaved: (v) => _name = v!,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: '소속 지점'),
                value: _selectedBranchId,
                items: _branches.map<DropdownMenuItem<int>>((b) {
                  return DropdownMenuItem(
                      value: b['id'], child: Text(b['name']));
                }).toList(),
                onChanged: (v) => setState(() => _selectedBranchId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: '직책'),
                value: _position,
                items: _positions.map((p) {
                  return DropdownMenuItem(
                      value: p['value'], child: Text(p['label']!));
                }).toList(),
                onChanged: (v) => setState(() => _position = v!),
              ),

              if (_position == 'VICE') ...[
                const SizedBox(height: 16),
                _buildSectionTitle('담당 강사 관리'),
                if (_allStaff.isEmpty)
                  const Text('등록된 강사가 없습니다.')
                else
                  Builder(builder: (context) {
                    final filteredStaff = _allStaff.where((s) {
                      if (s['id'] == widget.staffId) return false;
                      if (s['branch'] != _selectedBranchId) return false;
                      if (s['position'] == 'PRINCIPAL') return false;
                      return true;
                    }).toList();

                    if (filteredStaff.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text('관리할 수 있는 강사가 없습니다.\n(같은 지점의 강사/부원장만 표시됨)',
                            style: TextStyle(color: Colors.grey)),
                      );
                    }

                    return Wrap(
                      spacing: 8.0,
                      children: filteredStaff.map((staff) {
                        final userId = staff['user_id'];
                        final isSelected =
                            _managedTeacherUserIds.contains(userId);
                        return FilterChip(
                          label: Text(staff['name'] ?? staff['username']),
                          selected: isSelected,
                          onSelected: (bool selected) {
                            setState(() {
                              if (selected) {
                                _managedTeacherUserIds.add(userId);
                              } else {
                                _managedTeacherUserIds.remove(userId);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  }),
                const Divider(height: 32),
              ],
              const SizedBox(height: 16),
              // Join Date
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _joinDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) setState(() => _joinDate = date);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: '입사일 (계약 시작일)'),
                  child: Text(_joinDate == null
                      ? '날짜 선택'
                      : _joinDate!.toString().split(' ')[0]),
                ),
              ),
              const SizedBox(height: 16),
              // Resignation Date
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _resignationDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) setState(() => _resignationDate = date);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '퇴사일 (선택)',
                    suffixIcon: Icon(Icons.exit_to_app),
                  ),
                  child: Text(_resignationDate == null
                      ? '-'
                      : _resignationDate!.toString().split(' ')[0]),
                ),
              ),

              const SizedBox(height: 16),
              // Phone
              TextFormField(
                initialValue: _phoneNumber, // [NEW]
                decoration: const InputDecoration(labelText: '연락처 (전화번호)'),
                onSaved: (v) => _phoneNumber = v ?? '',
              ),
              const SizedBox(height: 16),
              // Email
              TextFormField(
                initialValue: _email, // [NEW]
                decoration: const InputDecoration(labelText: '이메일'),
                onSaved: (v) => _email = v ?? '',
              ),

              const SizedBox(height: 32),
              _buildSectionTitle('담당 과목'),
              CheckboxListTile(
                title: const Text('구문(Syntax) 담당'),
                value: _isSyntax,
                onChanged: (v) => setState(() => _isSyntax = v ?? false),
              ),
              CheckboxListTile(
                title: const Text('독해(Reading) 담당'),
                value: _isReading,
                onChanged: (v) => setState(() => _isReading = v ?? false),
              ),

              const SizedBox(height: 32),
              _buildSectionTitle('관리자 메모'),
              TextFormField(
                initialValue: _memo,
                decoration: const InputDecoration(
                  hintText: '특이사항이나 계약 관련 메모를 입력하세요.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
                onSaved: (v) => _memo = v ?? '',
              ),
              const SizedBox(height: 32),
              _buildSectionTitle('계정 활성화'),
              SwitchListTile(
                title: const Text('계정 활성화'),
                subtitle: const Text('비활성화 시 로그인이 차단됩니다.'),
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
              ),

              const SizedBox(height: 40),

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
}
