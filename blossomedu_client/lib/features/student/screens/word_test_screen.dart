import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';
import '../../../core/services/vocab_service.dart';
import '../../../core/services/tts_service.dart';

class WordTestScreen extends StatefulWidget {
  final int bookId;
  final String testRange;
  final String assignmentId;
  final String testMode; // 'study', 'test', or 'practice'
  final String questionType; // 'word_to_meaning' or 'meaning_to_word'

  final List<Map<String, String>>?
      initialWords; // [NEW] Optional words for review

  const WordTestScreen({
    super.key,
    required this.bookId,
    required this.testRange,
    required this.assignmentId,
    this.testMode = 'test',
    this.questionType = 'word_to_meaning',
    this.initialWords,
  });

  @override
  State<WordTestScreen> createState() => _WordTestScreenState();
}

class _WordTestScreenState extends State<WordTestScreen>
    with TickerProviderStateMixin {
  final VocabService _vocabService = VocabService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _words = [];
  String? _errorMessage;
  final TtsService _ttsService = TtsService();
  final bool _autoPlay = true; // [TTS] Auto Play Default
  bool _hasFinishedTest = false;
  bool _canPop = false;
  bool _isProcessing = false; // [NEW] 다음 문제 처리 중 여부 (1초 딜레이)

  int _currentIndex = 0;
  final List<String> _userAnswers = [];

  // Timer Animation
  late AnimationController _timerController;

  // Study Mode State
  bool _isCardFlipped = false;

  // Input Controller
  final TextEditingController _answerController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initializeTest();

    // 2. Initialize Timer
    _timerController =
        AnimationController(vsync: this, duration: const Duration(seconds: 7));

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _submitAnswer(isTimeOver: true);
      }
    });
  }

  Future<void> _initializeTest() async {
    // 1. Fetch Words
    if (widget.initialWords != null && widget.initialWords!.isNotEmpty) {
      _words = widget.initialWords!;
      _isLoading = false;
    } else {
      try {
        final normalizedRange = _normalizeRange(widget.testRange);
        if (widget.testMode == 'study' &&
            widget.bookId > 0 &&
            normalizedRange != 'WRONG_ONLY') {
          final rawWords = await _vocabService.getWords(
            widget.bookId,
            dayRange: normalizedRange.isEmpty ? 'ALL' : normalizedRange,
          );

          // Map backend data to frontend format
          final mappedWords = rawWords
              .map((w) => {
                    'id': w['id'],
                    'wordId': w['id'],
                    'word': w['english'],
                    'meaning': w['korean'],
                    'meaning_groups': w['meaning_groups'],
                    'example': w['example_sentence'] ?? '',
                    'pos': w['pos']
                  })
              .toList()
              .cast<Map<String, dynamic>>();

          if (mounted) {
            setState(() {
              _words = mappedWords;
              _isLoading = false;
            });
            _speakCurrentWord(); // [TTS] Speak First Word
          }
        } else {
          // [FIX] Study Mode should show all wrong words (limit 300)
          final int requestCount = widget.testMode == 'study' ? 300 : 30;
          final rawQuestions = await _vocabService.generateTestQuestions(
            bookId: widget.bookId,
            range: widget.testRange, // Use the passed range
            count: requestCount,
          );

          // Map backend data to frontend format
          final mappedWords = rawQuestions
              .map((w) => {
                    'id': w['id'],
                    'wordId': w['word_id'],
                    'word': w['english'],
                    'meaning': w['korean'],
                    'meaning_groups': w['meaning_groups'],
                    'example': w['example_sentence'] ?? '',
                    'pos': w['pos']
                  })
              .toList()
              .cast<Map<String, dynamic>>();

          if (mounted) {
            setState(() {
              _words = mappedWords;
              _isLoading = false;
            });
            _speakCurrentWord(); // [TTS] Speak First Word
          }
        }
      } catch (e) {
        debugPrint('Error loading test questions: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.toString();
          });
        }
      }
    }

    // 3. Check Penalty (only in Test Mode, NOT practice)
    if (widget.testMode == 'test' && !_isLoading && _words.isNotEmpty) {
      final allowed = await _checkPenalty();
      if (allowed) {
        _startTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusNode.requestFocus();
        });
      } else {
        if (mounted) _showPenaltyDialog();
      }
    } else {
      // Study or Practice mode - just focus (no timer, no penalty)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  Future<bool> _checkPenalty() async {
    print('[DEBUG] _checkPenalty called');
    final prefs = await SharedPreferences.getInstance();
    final lastPenalty = prefs.getInt('last_penalty_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    debugPrint(
        '[DEBUG] Last penalty: $lastPenalty, Now: $now, Diff: ${now - lastPenalty}ms');

    // 3 minutes = 180,000 ms
    if (now - lastPenalty < 180000) {
      print('[DEBUG] Still in penalty period - BLOCKED');
      return false;
    }
    print('[DEBUG] No penalty - ALLOWED');
    return true;
  }

  Future<void> _applyPenalty() async {
    print('[DEBUG] _applyPenalty called');
    if (widget.testMode != 'test') return;
    if (_words.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        'last_penalty_timestamp', DateTime.now().millisecondsSinceEpoch);
    debugPrint(
        '[DEBUG] Penalty timestamp saved: ${DateTime.now().millisecondsSinceEpoch}');
  }

  void _showPenaltyDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
              title: const Text('🚫 응시 제한 (Penalty)'),
              content: const Text(
                  '이전 시험 불합격으로 인해 3분간 재시험이 불가능합니다.\n오답 노트를 복습하고 오세요!'),
              actions: [
                TextButton(
                    onPressed: () {
                      context.pop();
                      context.pop(); // Exit Screen
                    },
                    child: const Text('나가기'))
              ],
            ));
  }

  void _startTimer() {
    print('[DEBUG] _startTimer called - resetting and forwarding timer');
    _timerController.reset();
    _timerController.forward();
  }

  @override
  void dispose() {
    _focusNode.dispose(); // Dispose FocusNode
    _ttsService.stop(); // [TTS] Stop Speaking
    super.dispose();
  }

  // [TTS] Helper
  void _speakCurrentWord() async {
    if (_words.isEmpty || !_autoPlay) return;
    final word = _words[_currentIndex]['word'];
    if (word != null && word.isNotEmpty) {
      await _ttsService.speak(word);
    }
  }

  void _submitAnswer({bool isTimeOver = false}) async {
    // [NEW] 딜레이 중에는 입력 무시 (엔터 연타 방지)
    if (_isProcessing) return;

    // [FIX] Practice mode allows empty answers (skip), test mode requires input
    if (!isTimeOver &&
        widget.testMode == 'test' &&
        _answerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('답을 입력해주세요! (모르면 7초 기다리세요)')));
      _focusNode.requestFocus(); // Keep focus
      return;
    }

    _timerController.stop(); // Stop timer when answer submitted
    _userAnswers.add(_answerController.text.trim());
    _answerController.clear();

    // [FIX] Keep keyboard up immediately
    _focusNode.requestFocus();

    // [NEW] 시험 모드에서 1초 딜레이 추가 (엔터 연타 겹치기 방지)
    if (widget.testMode == 'test' && _currentIndex < _words.length - 1) {
      setState(() => _isProcessing = true);
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _isProcessing = false);
    }

    _nextCard();
    _focusNode.requestFocus(); // Ensure focus for next card
  }

  void _nextCard() {
    if (_currentIndex < _words.length - 1) {
      setState(() {
        _currentIndex++;
        _isCardFlipped = false; // Reset for study mode
      });
      _speakCurrentWord(); // [TTS] Speak Next Word
      if (widget.testMode == 'test') {
        _startTimer();
      }
    } else {
      _finishTest();
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _isCardFlipped = false; // Reset for study mode
      });
      _speakCurrentWord(); // [TTS] Speak Previous Word
    }
  }

  void _handleStudySwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity;
    if (velocity == null || velocity.abs() < 150) return;
    if (velocity < 0) {
      _nextCard();
    } else {
      _prevCard();
    }
  }

  void _finishTest() async {
    _timerController.stop();

    if (widget.testMode == 'test') {
      try {
        setState(() => _isLoading = true);

        // 1. Prepare Data
        final List<Map<String, dynamic>> details = [];
        for (int i = 0; i < _words.length; i++) {
          final detail = <String, dynamic>{
            'english': _words[i]['word'],
            'user_input': i < _userAnswers.length ? _userAnswers[i] : '',
          };
          if (_words[i]['wordId'] != null) {
            detail['word_id'] = _words[i]['wordId'];
          }
          if (_words[i]['pos'] != null) {
            detail['pos'] = _words[i]['pos'];
          }
          details.add(detail);
        }

        // 2. Submit to Server
        final result = await _vocabService.submitTestResult(
          bookId: widget.bookId,
          range: widget.testRange,
          details: details,
          mode: 'challenge', // Default mode
          assignmentId:
              widget.assignmentId.isNotEmpty ? widget.assignmentId : null,
        );

        // 3. Process Response
        final int score = result['score'];
        final List<dynamic> serverResults = result['results'];

        final List<Map<String, dynamic>> wrongWords = [];
        final List<Map<String, String>> answersHistory = [];

        for (var item in serverResults) {
          final isCorrect = item['c'] == true;
          final question = item['q'];

          if (!isCorrect) {
            // Find original word object to pass to Result Screen (for re-study)
            final originalWord = _words.firstWhere(
              (w) => w['word'] == question,
              orElse: () => <String, dynamic>{},
            );
            if (originalWord.isNotEmpty) wrongWords.add(originalWord);
          }

          answersHistory.add({
            'question': item['q'],
            'answer': item['a'],
            'user_input': item['u'],
            'is_correct': isCorrect.toString(),
          });
        }

        // Strict Mode Penalty Check (Fail) - pass threshold is 90% correct.
        final int totalCount = _words.length;
        final bool isPass =
            totalCount > 0 ? (score / totalCount) >= 0.9 : false;
        if (!isPass) {
          await _applyPenalty();
        }

        // [NEW] Sync wrong words to personal wrong note
        debugPrint(
            '[DEBUG] Saving ${wrongWords.length} wrong words to personal note');
        for (final word in wrongWords) {
          try {
            print('[DEBUG] Saving wrong word: ${word['word']}');
            await _vocabService.addPersonalWord(
              english: word['word'] ?? '',
              korean: word['meaning'] ?? '',
            );
            print('[DEBUG] Successfully saved: ${word['word']}');
          } catch (e) {
            debugPrint(
                '[DEBUG] Failed to save wrong word: ${word['word']} - $e');
          }
        }

        if (mounted) {
          setState(() => _isLoading = false);
          _hasFinishedTest = true;
          context.pushReplacement('/student/test/result', extra: {
            'score': score,
            'totalCount': _words.length,
            'correctCount': (score / 100 * _words.length).round(),
            'elapsedTime': 0,
            'wrongWords': wrongWords,
            'answers': answersHistory,
            'testId': result['test_id'] ?? 0,
          });
        }
      } catch (e) {
        debugPrint('Submit Error: $e');
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('결과 저장 실패: $e')),
          );
        }
      }
    } else if (widget.testMode == 'practice') {
      // [NEW] Practice Mode - Local Score Calculation, No Server, No Wrong Word Tracking
      int correctCount = 0;
      final List<Map<String, dynamic>> wrongWords = [];
      final List<Map<String, String>> answersHistory = [];

      for (int i = 0; i < _words.length; i++) {
        final word = _words[i];
        final userInput =
            i < _userAnswers.length ? _userAnswers[i].trim().toLowerCase() : '';
        final correctAnswer =
            (word['meaning'] ?? '').toString().trim().toLowerCase();

        // Simple exact match for practice (can be enhanced)
        final isCorrect =
            userInput.isNotEmpty && correctAnswer.contains(userInput);

        if (isCorrect) {
          correctCount++;
        } else {
          wrongWords.add(word);
        }

        answersHistory.add({
          'question': word['word'] ?? '',
          'answer': word['meaning'] ?? '',
          'user_input': i < _userAnswers.length ? _userAnswers[i] : '',
          'is_correct': isCorrect.toString(),
        });
      }

      final int totalCount = _words.length;
      final int score =
          totalCount > 0 ? ((correctCount / totalCount) * 100).round() : 0;

      if (mounted) {
        _hasFinishedTest = true;
        context.pushReplacement('/student/test/result', extra: {
          'score': score,
          'totalCount': totalCount,
          'correctCount': correctCount,
          'elapsedTime': 0,
          'wrongWords': wrongWords,
          'answers': answersHistory,
          'testId': 0, // No server test ID
          'isPractice': true, // [NEW] Flag for result screen
        });
      }
    } else {
      // Study Mode Finish
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('학습 완료! 🎉'),
                content: const Text('모든 카드를 학습했습니다. 수고하셨어요!'),
                actions: [
                  TextButton(
                      onPressed: () {
                        context.pop(); // Close Dialog
                        context.pop(); // Back to Study Screen
                      },
                      child: const Text('확인'))
                ],
              ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _words.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('오류')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? '설정된 범위에 단어가 없습니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      );
    }

    final currentWord = _words[_currentIndex];
    final bool isStudy = widget.testMode ==
        'study'; // Only study = cards, test/practice = typing
    final bool isPractice = widget.testMode == 'practice';
    final double totalProgress = (_currentIndex + 1) / _words.length;

    return PopScope(
      canPop: _canPop || (widget.testMode != 'test') || _hasFinishedTest,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (widget.testMode == 'test' && !_hasFinishedTest) {
          await _applyPenalty();
        }
        if (mounted) {
          setState(() => _canPop = true);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(isStudy ? '카드 학습' : (isPractice ? '연습 모드' : '실전 시험')),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
        body: Column(
          children: [
            // 1. Total Progress Bar (Thin, Grey)
            LinearProgressIndicator(
                value: totalProgress,
                minHeight: 4,
                backgroundColor: Colors.grey.shade200,
                color: Colors.grey.shade400),

            Expanded(
              child: SingleChildScrollView(
                reverse:
                    !isStudy, // [FIX] Only reverse for Test Mode (Keyboard)
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  // Ensure full height centering for Study Mode
                  height:
                      isStudy ? MediaQuery.of(context).size.height * 0.6 : null,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // [Adjusted] Spacing
                      SizedBox(height: isStudy ? 0 : 20),
                      Text('${_currentIndex + 1} / ${_words.length}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 16)),
                      const SizedBox(height: 20), // Reduced from 40

                      // Question Card
                      if (isStudy)
                        _buildStudyCard(currentWord)
                      else
                        _buildTestInput(currentWord),
                    ],
                  ),
                ),
              ),
            ),

            // [NEW POSITION] Timer Bar (Test Mode Only - NOT practice) - Moved to Bottom
            if (widget.testMode == 'test')
              AnimatedBuilder(
                animation: _timerController,
                builder: (context, child) {
                  final value = 1.0 - _timerController.value;
                  final int remainingSeconds = (value * 7).ceil();

                  // Use a simpler, non-intrusive progress bar at the bottom
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('남은 시간',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12)),
                            Text(
                              '$remainingSeconds초',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: value > 0.3
                                    ? AppColors.primary
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade200,
                            color: value > 0.3 ? AppColors.primary : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  );
                },
              ),

            // Bottom Button (Removed as per request - using keyboard action instead)
            // if (!isStudy) ...
          ],
        ),
      ),
    );
  }

  Widget _buildStudyCard(Map<String, dynamic> word) {
    final meaningWidgets = <Widget>[];
    final rawGroups = word['meaning_groups'];
    if (rawGroups is List) {
      for (final group in rawGroups) {
        String pos = '';
        String meaningText = '';
        if (group is Map) {
          final meaningsRaw = group['meanings'];
          final meaningRaw = group['meaning'];
          pos = group['pos']?.toString() ?? '';
          if (meaningsRaw is List) {
            // Filter out empty strings if any
            final validMeanings = meaningsRaw
                .where((e) => e.toString().trim().isNotEmpty)
                .toList();
            meaningText = validMeanings.join(', ');
          } else if (meaningRaw != null) {
            meaningText = meaningRaw.toString();
          } else if (meaningsRaw != null) {
            meaningText = meaningsRaw.toString();
          }
        } else if (group is String) {
          meaningText = group;
        }

        if (meaningText.trim().isEmpty) {
          continue;
        }
        meaningWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pos.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pos,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue),
                    ),
                  ),
                if (pos.isNotEmpty) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    meaningText,
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    final hasMeaningGroups = meaningWidgets.isNotEmpty;

    return SizedBox(
      height: 350,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: GestureDetector(
                onTap: () => setState(() => _isCardFlipped = !_isCardFlipped),
                onHorizontalDragEnd: _handleStudySwipe,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10))
                    ],
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: _isCardFlipped
                          ? SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (hasMeaningGroups)
                                    ...meaningWidgets
                                  else
                                    Text(word['meaning'] ?? '',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87)),
                                  const SizedBox(height: 20),
                                  if (word['example'] != null &&
                                      word['example'].toString().isNotEmpty)
                                    Text(word['example'],
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey,
                                            fontStyle: FontStyle.italic)),
                                ],
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(word['word'] ?? '',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          // [FIX] 텍스트 길이에 따라 폰트 크기 자동 조절
                                          fontSize:
                                              (word['word'] ?? '').length > 25
                                                  ? 24
                                                  : 32,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary)),
                                ),
                                const SizedBox(height: 24),
                                IconButton(
                                  onPressed: () =>
                                      _ttsService.speak(word['word'] ?? ''),
                                  icon: const Icon(Icons.volume_up,
                                      color: AppColors.primary, size: 32),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _buildNavButton(
              icon: Icons.chevron_left,
              onPressed: _currentIndex > 0 ? _prevCard : null,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: _buildNavButton(
              icon: Icons.chevron_right,
              onPressed:
                  _currentIndex < _words.length - 1 ? _nextCard : _finishTest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final color = onPressed == null ? Colors.grey.shade300 : AppColors.primary;
    return Center(
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        iconSize: 36,
      ),
    );
  }

  String _normalizeRange(String range) {
    return range
        .replaceAll(RegExp(r'day', caseSensitive: false), '')
        .replaceAll(' ', '')
        .trim();
  }

  String _inferPos(String meaning) {
    if (meaning.endsWith('다')) return 'v';
    if (meaning.endsWith('ㄴ') ||
        meaning.endsWith('은') ||
        meaning.endsWith('는') ||
        meaning.endsWith('한') ||
        meaning.endsWith('적인') ||
        meaning.endsWith('의')) {
      return 'adj';
    }
    if (meaning.endsWith('게') ||
        meaning.endsWith('히') ||
        meaning.endsWith('으로')) {
      return 'adv';
    }
    return 'n';
  }

  Widget _buildTestInput(Map<String, dynamic> word) {
    final bool isWordQuestion = widget.questionType == 'word_to_meaning';
    String questionText =
        isWordQuestion ? (word['word'] ?? '') : (word['meaning'] ?? '');

    // [UX] Prepend POS for English Questions to avoid ambiguity
    if (isWordQuestion) {
      final rawPos = word['pos']?.toString();
      final pos = (rawPos != null && rawPos.isNotEmpty)
          ? rawPos
          : _inferPos(word['meaning'] ?? '');
      if (pos.isNotEmpty) {
        questionText = '($pos) $questionText';
      }
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(questionText,
                    style: TextStyle(
                        // [FIX] 텍스트 길이에 따라 폰트 크기 자동 조절
                        fontSize: questionText.length > 35
                            ? 24
                            : questionText.length > 20
                                ? 30
                                : 36,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
              ),
            ),
            if (isWordQuestion) // [TTS] Show Speaker for English Question
              IconButton(
                onPressed: () => _ttsService.speak(word['word'] ?? ''),
                icon:
                    const Icon(Icons.volume_up, color: Colors.black, size: 32),
              ),
          ],
        ),
        const SizedBox(height: 40),
        TextField(
          key: const ValueKey('test_input_field'), // [FIX] Stable Key
          controller: _answerController,
          focusNode: _focusNode,
          // autofocus removed to prevent Flutter Web focus conflict
          textInputAction:
              TextInputAction.go, // [UX] Show "Go" button on keyboard
          onSubmitted: (_) => _submitAnswer(),
          decoration: InputDecoration(
            hintText: isWordQuestion ? '뜻을 입력하세요' : '영어 단어를 입력하세요',
            filled: true,
            fillColor: Colors.white,
            // [UX] Add suffix icon as a replacement for the "Next" button
            suffixIcon: IconButton(
              onPressed: _submitAnswer,
              icon: const Icon(Icons.send_rounded, color: AppColors.primary),
            ),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          ),
          style: const TextStyle(fontSize: 18),
        ),
      ],
    );
  }
}
