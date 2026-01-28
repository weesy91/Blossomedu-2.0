import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/vocab_service.dart';

class WordTestReviewScreen extends StatefulWidget {
  final String testResultId;

  const WordTestReviewScreen({
    required this.testResultId,
    super.key,
  });

  @override
  State<WordTestReviewScreen> createState() => _WordTestReviewScreenState();
}

class _WordTestReviewScreenState extends State<WordTestReviewScreen> {
  final VocabService _vocabService = VocabService();
  bool _isLoading = true;
  Map<String, dynamic> _d = {
    'studentName': '',
    'testName': '',
    'score': 0,
    'total': 0,
    'questions': []
  };

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final data =
          await _vocabService.getTestResult(int.parse(widget.testResultId));

      final details = data['details'] as List? ?? [];
      final questions = details.map((d) {
        String status = 'WRONG';
        if (d['is_correct'] == true) status = 'ACCEPTED'; // Or just Correct
        if (d['is_correction_requested'] == true) status = 'PENDING';
        if (d['is_resolved'] == true) {
          status = d['is_correct'] ? 'ACCEPTED' : 'REJECTED';
        }

        return {
          'id': d['id'], // detail ID
          'word': d['word_question'], // Assuming API returns 'word_question'
          'meaning': '', // API doesn't return Meaning? Need to check.
          // DetailSerializer returns [word_question, student_answer, correct_answer]
          // student_answer is user input.
          // correct_answer is the answer key.
          'studentAnswer': d['student_answer'],
          'correctAnswer': d['correct_answer'],
          'isCorrect': d['is_correct'],
          'correctionRequested': d['is_correction_requested'] ?? false,
          'status': status,
          'pos': d['question_pos'], // [NEW] Map POS
        };
      }).toList();

      setState(() {
        _d = {
          'studentName': data['student_name'] ?? 'Unknown',
          'testName': '${data['book_title']} (${data['test_range']})',
          'score': data['score'],
          'total': details.length,
          'questions': questions,
        };
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Load Error: $e')));
      }
    }
  }

  void _handleCorrection(int detailId, bool accept) {
    setState(() {
      final q =
          (_d['questions'] as List).firstWhere((e) => e['id'] == detailId);

      // 1. Calculate Score Delta
      // If previous status was NOT ACCEPTED, and now ACCEPTED -> +1
      // If previous status was ACCEPTED, and now REJECTED -> -1
      final oldStatus = q['status'];
      final newStatus = accept ? 'ACCEPTED' : 'REJECTED';

      if (oldStatus != 'ACCEPTED' && newStatus == 'ACCEPTED') {
        _d['score'] = (_d['score'] as int) + 1;
      } else if (oldStatus == 'ACCEPTED' && newStatus == 'REJECTED') {
        _d['score'] = (_d['score'] as int) - 1;
      }

      q['status'] = newStatus;
    });
  }

  void _resetCorrection(int detailId) {
    setState(() {
      final q =
          (_d['questions'] as List).firstWhere((e) => e['id'] == detailId);
      if (q['status'] == 'ACCEPTED') {
        _d['score'] = (_d['score'] as int) - 1;
      }
      q['status'] = 'PENDING';
    });
  }

  Future<void> _saveReview() async {
    try {
      setState(() => _isLoading = true);
      // Collect changes
      final List<Map<String, dynamic>> corrections = [];
      for (var q in _d['questions']) {
        if (q['status'] == 'ACCEPTED' || q['status'] == 'REJECTED') {
          corrections.add(
              {'word_id': q['word'], 'accepted': q['status'] == 'ACCEPTED'});
        }
      }

      final result = await _vocabService.reviewTestResult(
          int.parse(widget.testResultId), corrections);

      if (mounted) {
        setState(() {
          _isLoading = false;
          // [UX] Update Score from Server Response to be sure
          if (result['new_score'] != null) {
            _d['score'] = result['new_score'];
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채점 결과가 저장되었습니다.')),
        );

        // [UX] Exit after save (List screen will auto-refresh)
        if (mounted) context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = _d['questions'] as List<dynamic>;

    return Scaffold(
      appBar: AppBar(
        title: const Text('단어 시험 정정/검수'),
        actions: [
          TextButton(
            onPressed: _saveReview,
            child: const Text('저장 완료',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 1. Info Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.indigo.shade50,
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.indigo.withOpacity(0.2),
                        child: Text(
                            _d['studentName'].isNotEmpty
                                ? _d['studentName'][0]
                                : '?',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_d['testName'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('현재 점수: ${_d['score']}점',
                                style: const TextStyle(
                                    color: Colors.indigo,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Correction List
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: questions.length,
                    separatorBuilder: (_, __) => const Divider(height: 24),
                    itemBuilder: (context, index) {
                      final q = questions[index];
                      final bool isRequest = q['correctionRequested'];

                      if (!isRequest && q['status'] != 'PENDING') {
                        return _buildResultItem(q);
                      }

                      return _buildCorrectionItem(q);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCorrectionItem(Map<String, dynamic> q) {
    final status = q['status'];
    Color cardColor = Colors.white;
    if (status == 'ACCEPTED') cardColor = Colors.green.shade50;
    if (status == 'REJECTED') cardColor = Colors.red.shade50;

    return Container(
      decoration: BoxDecoration(
          color: cardColor,
          border: Border.all(
              color: status == 'PENDING' ? Colors.orange : Colors.transparent,
              width: 2),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (status == 'PENDING')
              BoxShadow(
                  color: Colors.orange.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 2)
          ]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('이의 제기',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              const Spacer(),
              if (status == 'ACCEPTED' || status == 'REJECTED')
                TextButton(
                  onPressed: () => _resetCorrection(q['id']),
                  child: const Text('되돌리기'),
                ),
              if (status == 'ACCEPTED')
                const Icon(Icons.check_circle, color: Colors.green),
              if (status == 'REJECTED')
                const Icon(Icons.cancel, color: Colors.red),
            ],
          ),
          const SizedBox(height: 12),

          const SizedBox(height: 12),

          // Question (English Word)
          Text('문제: ${q['word']}',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo)),
          if (q['pos'] != null)
            Text(q['pos'],
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('학생 답안 (한글)',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(q['studentAnswer'],
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: status == 'ACCEPTED'
                                ? Colors.green
                                : (status == 'REJECTED'
                                    ? Colors.red
                                    : Colors.black87),
                            decoration: status == 'REJECTED'
                                ? TextDecoration.lineThrough
                                : TextDecoration.none)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Icon(Icons.arrow_forward, color: Colors.grey),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('정답 (한글)',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                        '${q['correctAnswer']} ${q['pos'] != null ? '(${q['pos']})' : ''}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue)),
                  ],
                ),
              ),
            ],
          ),

          if (status == 'PENDING') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleCorrection(q['id'], false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('반려 (오답 유지)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleCorrection(q['id'], true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('정답 인정'),
                  ),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildResultItem(Map<String, dynamic> q) {
    return Opacity(
      opacity: 0.6,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q['word'],
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                // [NEW] Show POS clearly
                if (q['pos'] != null)
                  Text(q['pos'],
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(q['studentAnswer'],
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: q['isCorrect'] ? Colors.green : Colors.red,
                        decoration: q['isCorrect']
                            ? TextDecoration.none
                            : TextDecoration.lineThrough)),
                Text(
                    '${q['correctAnswer']} ${q['pos'] != null ? '(${q['pos']})' : ''}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.blue)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
