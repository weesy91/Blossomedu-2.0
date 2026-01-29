import 'package:flutter/material.dart';
import '../../../core/services/academy_service.dart';

class MockTestDetailScreen extends StatefulWidget {
  final int examId;
  final String title;

  const MockTestDetailScreen(
      {super.key, required this.examId, required this.title});

  @override
  State<MockTestDetailScreen> createState() => _MockTestDetailScreenState();
}

class _MockTestDetailScreenState extends State<MockTestDetailScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = true;
  Map<String, dynamic>? _exam;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final data = await _academyService.getMockExamInfoDetail(widget.examId);
      setState(() {
        _exam = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showQuestionEditDialog(Map<String, dynamic> question) async {
    final int questionId = question['id'];
    int correctAnswer = question['correct_answer'] ?? 1;
    int score = question['score'] ?? 2;
    String category = question['category'] ?? 'TOPIC';

    final categories = {
      'LISTENING': '듣기',
      'PURPOSE': '목적/심경',
      'TOPIC': '주제/제목',
      'DATA': '도표/일치',
      'MEANING': '함축의미',
      'GRAMMAR': '어법',
      'VOCAB': '어휘',
      'BLANK': '빈칸',
      'FLOW': '무관한문장',
      'ORDER': '순서',
      'INSERT': '삽입',
      'SUMMARY': '요약',
      'LONG': '장문'
    };

    await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                title: Text('${question['number']}번 문항 수정'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: '정답'),
                      value: correctAnswer,
                      items: [1, 2, 3, 4, 5]
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text('$e번')))
                          .toList(),
                      onChanged: (v) => setState(() => correctAnswer = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: '배점'),
                      value: score,
                      items: [2, 3]
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text('${e}점')))
                          .toList(),
                      onChanged: (v) => setState(() => score = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: '유형'),
                      value:
                          categories.containsKey(category) ? category : 'TOPIC',
                      items: categories.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => setState(() => category = v!),
                    )
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소')),
                  ElevatedButton(
                      onPressed: () async {
                        final data = {
                          'correct_answer': correctAnswer,
                          'score': score,
                          'category': category
                        };
                        try {
                          await _academyService.updateMockExamQuestion(
                              questionId, data);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('수정되었습니다.')));
                          _fetchDetail(); // Refresh list
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')));
                        }
                      },
                      child: const Text('저장')),
                ],
              );
            }));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final questions = (_exam?['questions'] as List?) ?? [];
    questions
        .sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: questions.isEmpty
          ? const Center(child: Text('등록된 문항이 없습니다.'))
          : ListView.builder(
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final q = questions[index];
                final score = q['score'] ?? 2;
                final isThreePoint = score == 3;
                return ListTile(
                  onTap: () => _showQuestionEditDialog(q),
                  leading: CircleAvatar(
                    backgroundColor: isThreePoint
                        ? Colors.redAccent.withOpacity(0.2)
                        : Colors.grey.withOpacity(0.1),
                    child: Text('${q['number']}',
                        style: TextStyle(
                            color: isThreePoint ? Colors.red : Colors.black,
                            fontWeight: isThreePoint
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  ),
                  title: Text('정답: ${q['correct_answer'] ?? '-'}'),
                  subtitle: Text('배점: ${score}점 | 유형: ${q['category'] ?? '-'}'),
                  trailing: const Icon(Icons.edit, size: 16),
                );
              },
            ),
    );
  }
}
