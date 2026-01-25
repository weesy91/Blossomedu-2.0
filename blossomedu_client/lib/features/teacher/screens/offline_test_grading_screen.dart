import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/vocab_service.dart';
import '../../../core/utils/web_monitor_helper.dart'; // [NEW]

class OfflineTestGradingScreen extends StatefulWidget {
  final List<Map<String, dynamic>> words;
  final int bookId;
  final String range;
  final String studentId;

  const OfflineTestGradingScreen({
    super.key,
    required this.words,
    required this.bookId,
    required this.range,
    required this.studentId,
  });

  @override
  State<OfflineTestGradingScreen> createState() =>
      _OfflineTestGradingScreenState();
}

class _OfflineTestGradingScreenState extends State<OfflineTestGradingScreen> {
  final VocabService _vocabService = VocabService();
  late List<bool> _results; // true = O, false = X
  bool _isSaving = false;

  @override
  void dispose() {
    WebMonitorHelper.sendCloseSignal(); // [NEW] Auto-close projector
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Default all correct? Or all wrong? Let's default to all correct for convenience?
    // Usually exams are mostly correct.
    _results = List.filled(widget.words.length, true);
  }

  int get _score {
    return _results.where((r) => r).length;
  }

  String get _grade {
    final total = widget.words.length;
    if (total == 0) return 'F';
    final percentage = _score / total;

    if (_score == total) return 'A';
    if (percentage >= 0.95) return 'B';
    if (percentage >= 0.90) return 'C';
    return 'F';
  }

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      final details = <Map<String, dynamic>>[];
      for (int i = 0; i < widget.words.length; i++) {
        final word = widget.words[i];
        details.add({
          'english': word['english'],
          'is_correct': _results[i],
          // 'user_input': '', // Offline test has no user input data available
        });
      }

      await _vocabService.submitOfflineTestResult(
        studentId: int.parse(widget.studentId),
        bookId: widget.bookId,
        range: widget.range,
        score: _score, // Pass calculated score
        details: details,
      );

      if (mounted) {
        // Return Grade to Class Log Screen
        context.pop(_grade);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('채점하기'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '$_score / ${widget.words.length} = $_grade',
                style: const TextStyle(
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.words.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final word = widget.words[index];
                final isCorrect = _results[index];

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade200,
                    child: Text('${index + 1}'),
                  ),
                  title: Text(
                    word['english'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(word['korean'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleButton(index, true, isCorrect),
                      const SizedBox(width: 8),
                      _buildToggleButton(index, false, isCorrect),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pop(), // Cancel returns null
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('취소'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.indigo,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('저장 및 일지 입력',
                            style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(int index, bool value, bool groupValue) {
    final isSelected = value == groupValue;
    final color = value ? Colors.green : Colors.red;

    return InkWell(
      onTap: () {
        setState(() {
          _results[index] = value;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          value ? 'O' : 'X',
          style: TextStyle(
            color: isSelected ? color : Colors.grey,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
