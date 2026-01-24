import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OfflineTestProjectionScreen extends StatefulWidget {
  final List<Map<String, dynamic>> words;
  final int durationPerWord;
  final String mode; // 'eng_kor' or 'kor_eng'
  final int bookId;
  final String range;
  final String studentId;

  const OfflineTestProjectionScreen({
    super.key,
    required this.words,
    required this.durationPerWord,
    this.mode = 'eng_kor',
    required this.bookId,
    required this.range,
    required this.studentId,
  });

  @override
  State<OfflineTestProjectionScreen> createState() =>
      _OfflineTestProjectionScreenState();
}

class _OfflineTestProjectionScreenState
    extends State<OfflineTestProjectionScreen> {
  int _currentIndex = 0;
  Timer? _timer;
  int _timeLeft = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timeLeft = widget.durationPerWord;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_timeLeft > 0) {
            _timeLeft--;
          } else {
            _nextWord();
          }
        });
      }
    });
  }

  void _nextWord() {
    if (_currentIndex < widget.words.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _startTimer();
    } else {
      _finishTest();
    }
  }

  void _finishTest() {
    _timer?.cancel();
    context.pushReplacement('/teacher/offline-test/grading', extra: {
      'words': widget.words,
      'bookId': widget.bookId,
      'range': widget.range,
      'studentId': widget.studentId,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.words.isEmpty) {
      return const Scaffold(body: Center(child: Text('단어 목록이 비어있습니다.')));
    }

    final currentWord = widget.words[_currentIndex];
    final displayWord = widget.mode == 'eng_kor'
        ? currentWord['english']
        : currentWord['korean']; // Or meaning

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Close Button
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () {
                _timer?.cancel();
                // If closed manually, maybe go back or still go to grading?
                // Assuming manual close means cancel -> go back
                context.pop();
              },
            ),
          ),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Progress
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: LinearProgressIndicator(
                  value: (_currentIndex + 1) / widget.words.length,
                  backgroundColor: Colors.grey.shade800,
                  color: Colors.blue,
                  minHeight: 8.0,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${_currentIndex + 1} / ${widget.words.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 18),
              ),
              const SizedBox(height: 60),

              // Word Display
              Center(
                child: Text(
                  displayWord ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 80, // Large font for projection
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Timer Indicator
              Text(
                '$_timeLeft',
                style: TextStyle(
                  color: _timeLeft <= 3 ? Colors.red : Colors.yellow,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
