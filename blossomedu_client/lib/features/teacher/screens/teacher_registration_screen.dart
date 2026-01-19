import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class TeacherRegistrationScreen extends StatefulWidget {
  const TeacherRegistrationScreen({super.key});

  @override
  State<TeacherRegistrationScreen> createState() =>
      _TeacherRegistrationScreenState();
}

class _TeacherRegistrationScreenState extends State<TeacherRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _academyService = AcademyService();
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Metadata
  List<dynamic> _branches = [];
  List<dynamic> _positions = [];

  // Form Data
  String _username = '';
  String _password = '1234';
  String _name = '';
  String _phoneNumber = '';
  String _email = '';
  String _memo = '';
  int? _selectedBranchId;
  String _selectedPosition = 'TEACHER';
  DateTime? _joinDate; // [NEW]
  bool _isSyntax = false;
  bool _isReading = false;

  @override
  void initState() {
    super.initState();
    _fetchMetadata();
  }

  Future<void> _fetchMetadata() async {
    try {
      final data = await _academyService.getStaffRegistrationMetadata();
      if (mounted) {
        setState(() {
          _branches = data['branches'] ?? [];
          _positions = data['positions'] ?? [];
          _isLoading = false;

          // Set default branch if only one exists
          if (_branches.isNotEmpty) {
            // _selectedBranchId = _branches[0]['id'];
            // Or let user choose
          }
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

    if (_selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지점을 선택해주세요.')),
      );
      return;
    }

    if (_joinDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('입사일(계약일)을 선택해주세요.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final Map<String, dynamic> payload = {
        'username': _username,
        'password': _password,
        'name': _name,
        'phone_number': _phoneNumber,
        'email': _email,
        'memo': _memo,
        'branch_id': _selectedBranchId,
        'position': _selectedPosition,
        'join_date': _joinDate!.toIso8601String().split('T')[0],
        'is_syntax': _isSyntax,
        'is_reading': _isReading,
      };

      await _academyService.registerStaff(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('선생님이 등록되었습니다.')),
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
      appBar: AppBar(title: const Text('선생님 등록')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('계정 생성'),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: '아이디 (ID) *',
                        helperText: '선생님 로그인 ID',
                        prefixIcon: Icon(Icons.person_outline),
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
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) => v!.isEmpty ? '비밀번호를 입력하세요' : null,
                      onSaved: (v) => _password = v!,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionTitle('기본 정보'),
                    TextFormField(
                      decoration: const InputDecoration(labelText: '이름 *'),
                      validator: (v) => v!.isEmpty ? '이름을 입력하세요' : null,
                      onSaved: (v) => _name = v!,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration:
                          const InputDecoration(labelText: '연락처 (전화번호)'),
                      onSaved: (v) => _phoneNumber = v ?? '',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(labelText: '이메일'),
                      onSaved: (v) => _email = v ?? '',
                    ),
                    const SizedBox(height: 16),
                    // Start Date Picker
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (date != null) setState(() => _joinDate = date);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '입사일 (계약 시작일) *',
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _joinDate == null
                              ? '날짜 선택'
                              : _joinDate!.toString().split(' ')[0],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: '소속 지점 *'),
                      items: _branches.map<DropdownMenuItem<int>>((b) {
                        return DropdownMenuItem(
                          value: b['id'],
                          child: Text(b['name']),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedBranchId = v),
                      value: _selectedBranchId,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: '직책 *'),
                      items: _positions.map<DropdownMenuItem<String>>((p) {
                        return DropdownMenuItem(
                          value: p['value'],
                          child: Text(p['label']),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedPosition = v!),
                      value: _selectedPosition,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionTitle('담당 과목 (중복 가능)'),
                    CheckboxListTile(
                      title: const Text('구문 (Syntax) 담당'),
                      value: _isSyntax,
                      onChanged: (v) => setState(() => _isSyntax = v!),
                    ),
                    CheckboxListTile(
                      title: const Text('독해 (Reading) 담당'),
                      value: _isReading,
                      onChanged: (v) => setState(() => _isReading = v!),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: '관리자 메모',
                        hintText: '특이사항이나 계약 관련 메모',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      onSaved: (v) => _memo = v ?? '',
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
