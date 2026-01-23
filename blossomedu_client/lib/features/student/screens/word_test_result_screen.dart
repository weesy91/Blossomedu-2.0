import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../core/services/vocab_service.dart';

class WordTestResultScreen extends StatefulWidget {
  final int score;
  final int total;
  final List<Map<String, String>> answers;
  final List<Map<String, dynamic>> wrongWords;
  final int testId;

  const WordTestResultScreen({
    required this.score,
    required this.total,
    required this.answers,
    required this.testId,
    this.wrongWords = const [],
    super.key,
  });

  @override
  State<WordTestResultScreen> createState() => _WordTestResultScreenState();
}

class _WordTestResultScreenState extends State<WordTestResultScreen> {
  final Set<int> _requestedIndices = {};

  // [FIX] Dynamic 90% threshold based on total questions
  bool get isPassed =>
      widget.total > 0 ? (widget.score / widget.total) >= 0.9 : false;

  bool _isServerCorrect(Map<String, String> item) {
    final raw = item['is_correct'];
    if (raw != null) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    final user = item['user_input']?.trim() ?? '';
    final answer = item['answer']?.trim() ?? '';
    return user.isNotEmpty && user == answer;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Result Header
            const SizedBox(height: 40),
            Icon(
              isPassed ? Icons.emoji_events : Icons.sentiment_dissatisfied,
              size: 80,
              color: isPassed ? Colors.amber : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              isPassed ? 'Test Passed!' : 'Try Again...',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.score} / ${widget.total}',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: isPassed ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 32),

            // 2. Answer List
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.answers.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = widget.answers[index];
                    final isCorrect = _isServerCorrect(item);
                    final isRequested = _requestedIndices.contains(index);

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isCorrect ? Icons.check_circle : Icons.cancel,
                        color: isCorrect ? Colors.green : Colors.red,
                      ),
                      title:
                          Text('${item['question']}'), // Question was English
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '답: ${item['user_input']!.isEmpty ? '(미입력)' : item['user_input']} / 정답: ${item['answer']}',
                            style: TextStyle(
                                color:
                                    isCorrect ? Colors.grey : Colors.redAccent),
                          ),
                        ],
                      ),
                      trailing: (!isCorrect)
                          ? isRequested
                              ? const Text('요청됨 ✅',
                                  style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold))
                              : OutlinedButton(
                                  onPressed: () async {
                                    try {
                                      await VocabService().requestCorrection(
                                          widget.testId, item['question']!);
                                      setState(() {
                                        _requestedIndices.add(index);
                                      });
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    '정답 정정 요청이 전송되었습니다. 선생님이 검토 후 반영됩니다.')));
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(content: Text('요청 실패: $e')),
                                        );
                                      }
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    side: const BorderSide(color: Colors.blue),
                                  ),
                                  child: const Text('정정 요청',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                )
                          : null,
                    );
                  },
                ),
              ),
            ),

            // 3. Actions
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.go('/student/study'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('홈으로'),
                    ),
                  ),
                  if (!isPassed) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('3분 쿨타임 중입니다! 잠시 복습하세요.')));
                          // TODO: Check Cooldown
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey, // Disabled look
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('재시험 (3분 대기)',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ] else ...[
                    if (widget.wrongWords.isNotEmpty) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            // [UX] Review Wrong Answers immediately in Study Mode
                            context.push('/student/test/start', extra: {
                              'bookId': 0, // Temporary ID
                              'range': '오답 복습',
                              'testMode': 'study',
                              'words': widget.wrongWords,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('오답 복습',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          // Return to Study List
                          context.go('/student/study');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('학습 목록으로',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
