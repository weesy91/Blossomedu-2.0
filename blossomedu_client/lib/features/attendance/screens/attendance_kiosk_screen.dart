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
    if (_input.length < 11) {
      // 11 Digits
      setState(() {
        _input += value;
        _message = null;
      });
    }
  }

  void _onShortcut010() {
    if (_input.isEmpty) {
      setState(() {
        _input = '010';
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

  Future<void> _submit() async {
    if (_input.length < 11) {
      setState(() => _message = '핸드폰 번호 11자리를 입력해주세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final result = await _academyService.checkAttendanceByPhone(_input);
      // result: { 'message': ..., 'mode': 'IN'/'OUT', 'student_name': ... }

      final msg = result['message'];

      setState(() {
        _isSuccess = true;
        _message = msg;
        _input = '';
      });

      Future.delayed(const Duration(seconds: 3), () {
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
        _message = e.toString().replaceAll('Exception: ', '');
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
              '핸드폰 번호 11자리를 입력해주세요',
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
                    _buildKeyRow(['010', '0', '⌫']), // [FIX] C -> 010
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Action Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: SizedBox(
                height: 80,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading || _input.length < 11 ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    '등하원 체크',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
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
    if (key == '010') {
      return _buildActionButton(
          null, Colors.indigo.shade50, Colors.indigo, _onShortcut010, '010');
    } else if (key == '⌫') {
      // Long press clear? For now standard delete.
      return _buildActionButton(
          Icons.backspace, Colors.grey.shade300, Colors.black, _onDelete, null);
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

  Widget _buildActionButton(IconData? icon, Color bg, Color contentColor,
      VoidCallback onTap, String? text) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: InkWell(
          onTap: onTap,
          onLongPress:
              text == null ? _onClear : null, // Long press backspace to clear
          borderRadius: BorderRadius.circular(100),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
            ),
            child: Center(
              child: text != null
                  ? Text(text,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: contentColor))
                  : Icon(icon, color: contentColor, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
