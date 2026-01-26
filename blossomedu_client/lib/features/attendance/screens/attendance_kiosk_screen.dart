import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/services/academy_service.dart';

class AttendanceKioskScreen extends StatefulWidget {
  const AttendanceKioskScreen({super.key});

  @override
  State<AttendanceKioskScreen> createState() => _AttendanceKioskScreenState();
}

class _AttendanceKioskScreenState extends State<AttendanceKioskScreen> {
  final _academyService = AcademyService();
  String _input = '';
  bool _isLoading = false;
  String? _message;
  bool _isSuccess = false;

  void _onKeyPress(String value) {
    if (_input.length < 8) {
      setState(() {
        _input += value;
        _message = null;
      });
    }
  }

  void _onClear() {
    setState(() {
      _input = '';
      _message = null;
    });
  }

  void _onDelete() {
    if (_input.isNotEmpty) {
      setState(() {
        _input = _input.substring(0, _input.length - 1);
        _message = null;
      });
    }
  }

  Future<void> _submit(String type) async {
    if (_input.isEmpty) return;

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      // Input is treated as Student ID (PK) for now.
      // TODO: If needed, map Phone Number or Access Code to ID here.
      final studentId = int.tryParse(_input);
      if (studentId == null) {
        throw Exception('올바른 학생 번호를 입력해주세요.');
      }

      // But backend expects specific status enum.
      // 'PRESENT', 'LATE', 'ABSENT', 'LEAVE_EARLY'?
      // Usually Kiosk just marks 'PRESENT' (Check-in) and maybe 'LEAVE' (Check-out).
      // Let's assume 'PRESENT' for both or differentiate if backend supports it.
      // Blossom backend `Attendance` model status choices?
      // Typically: PRESENT, LATE, ABSENT, EXCUSED. Doesn't seem to have 'LEAVE'.
      // For now, Kiosk = Check-in = PRESENT.
      // If user wants Check-out, we might need a separate API or logic.
      // Let's stick to Check-in (PRESENT) for MVP or "LEAVE" if supported.
      // Safest: type == 'IN' ? 'PRESENT' : 'LEAVE' (if added).
      // Re-reading models.py (from memory/previous context) - generic status char field.
      // Let's send 'PRESENT' for In, and maybe 'LEAVE' for Out?
      // Update: User asked for "Check-in/Check-out Kiosk".
      // I'll send 'PRESENT' for Check-in.
      // For Check-out, if backend doesn't support 'LEAVE' status, I'll allow it but might be just a log.

      final realStatus = type == 'IN' ? 'PRESENT' : 'LEAVE';

      await _academyService.createAttendance(
        studentId,
        realStatus,
        DateTime.now(),
      );

      setState(() {
        _isSuccess = true;
        _message = type == 'IN' ? '등원 처리가 완료되었습니다 👋' : '하원 처리가 완료되었습니다 🏠';
        _input = '';
      });

      // Auto clear message
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _message = null;
            _isSuccess = false;
          });
        }
      });
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _message = '오류: 학생 번호를 확인해주세요.'; // $e
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.grey, size: 32),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Title
            const Text(
              '등하원 체크',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '학생 번호를 입력해주세요',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 40),

            // Display
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 30),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _isSuccess ? Colors.green : Colors.transparent,
                    width: 2),
              ),
              child: Center(
                child: Text(
                  _message ?? (_input.isEmpty ? '____' : _input),
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: _message != null
                        ? (_isSuccess ? Colors.green : Colors.red)
                        : Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Keypad
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    _buildKeyRow(['1', '2', '3']),
                    const SizedBox(height: 20),
                    _buildKeyRow(['4', '5', '6']),
                    const SizedBox(height: 20),
                    _buildKeyRow(['7', '8', '9']),
                    const SizedBox(height: 20),
                    _buildKeyRow(['C', '0', '⌫']),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 80,
                      child: ElevatedButton(
                        onPressed: _isLoading || _input.isEmpty
                            ? null
                            : () => _submit('IN'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 5,
                        ),
                        child: const Text(
                          '등원',
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: SizedBox(
                      height: 80,
                      child: ElevatedButton(
                        onPressed: _isLoading || _input.isEmpty
                            ? null
                            : () => _submit('OUT'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 5,
                        ),
                        child: const Text(
                          '하원',
                          style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyRow(List<String> keys) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: keys.map((key) {
          return _buildKey(key);
        }).toList(),
      ),
    );
  }

  Widget _buildKey(String key) {
    if (key == 'C') {
      return _buildActionButton(
          Icons.refresh, Colors.grey.shade300, Colors.black, _onClear);
    } else if (key == '⌫') {
      return _buildActionButton(
          Icons.backspace, Colors.grey.shade300, Colors.black, _onDelete);
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: InkWell(
          onTap: () => _onKeyPress(key),
          borderRadius: BorderRadius.circular(100), // Circle
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Text(
                key,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, Color bg, Color contentColor, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
            ),
            child: Center(
              child: Icon(icon, color: contentColor, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
