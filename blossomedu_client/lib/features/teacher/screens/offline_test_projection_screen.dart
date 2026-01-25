import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/vocab_service.dart';

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

  bool _isFetching = false;
  bool _isFinished = false;
  List<Map<String, dynamic>> _localWords = [];

  @override
  void initState() {
    super.initState();
    _localWords = widget.words;

    // Use passed words if available, otherwise fetch
    if (_localWords.isEmpty && widget.bookId != 0) {
      _fetchWords();
    } else {
      _startTimer();
    }
  }

  Future<void> _fetchWords() async {
    setState(() => _isFetching = true);
    try {
      final vocabService = VocabService();
      final result = await vocabService.getWords(
        widget.bookId,
        dayRange: widget.range,
        shuffle: true,
      );

      if (mounted) {
        setState(() {
          var testWords = result.cast<Map<String, dynamic>>();
          if (testWords.length > 30) {
            testWords = testWords.sublist(0, 30);
          }
          _localWords = testWords;
          _isFetching = false;
          _startTimer();
        });
      }
    } catch (e) {
      print('Error fetching words: $e');
      if (mounted) setState(() => _isFetching = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    if (_localWords.isEmpty && !_isFetching) return;

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
    if (_currentIndex < _localWords.length - 1) {
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
    final isProjectorMode = widget.words.isEmpty;

    if (isProjectorMode) {
      setState(() => _isFinished = true);
    } else {
      context.pushReplacement('/teacher/offline-test/grading', extra: {
        'words': _localWords,
        'bookId': widget.bookId,
        'range': widget.range,
        'studentId': widget.studentId,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetching) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_isFinished) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            '시험 종료',
            style: TextStyle(
                color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    if (_localWords.isEmpty) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
              child: Text('단어 목록이 비어있습니다.',
                  style: TextStyle(color: Colors.white))));
    }

    final currentWord = _localWords[_currentIndex];
    final displayWord = widget.mode == 'eng_kor'
        ? currentWord['english']
        : currentWord['korean'];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () {
                _timer?.cancel();
                context.pop();
              },
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: LinearProgressIndicator(
                  value: (_currentIndex + 1) / _localWords.length,
                  backgroundColor: Colors.grey.shade800,
                  color: Colors.blue,
                  minHeight: 8.0,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${_currentIndex + 1} / ${_localWords.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 18),
              ),
              const SizedBox(height: 60),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    displayWord ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
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
