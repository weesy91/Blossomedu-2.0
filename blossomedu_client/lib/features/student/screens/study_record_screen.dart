import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants.dart';
import '../../../core/services/vocab_service.dart';

class StudyRecordScreen extends StatefulWidget {
  const StudyRecordScreen({super.key});

  @override
  State<StudyRecordScreen> createState() => _StudyRecordScreenState();
}

class _StudyRecordScreenState extends State<StudyRecordScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final VocabService _vocabService = VocabService();

  List<dynamic> _vocabResults = [];
  List<dynamic> _mockResults = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchRecords();
  }

  Future<void> _fetchRecords({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _isLoading = true);
    try {
      final vocabData = await _vocabService.getStudentTestResults();
      final mockData = await _vocabService.getMockExams();

      if (mounted) {
        setState(() {
          _vocabResults = vocabResultsSorted(vocabData);
          _mockResults = mockResultsSorted(mockData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('기록을 불러오지 못했습니다: $e')),
        );
      }
    }
  }

  List<dynamic> vocabResultsSorted(List<dynamic> results) {
    results.sort((a, b) {
      final aDate = DateTime.parse(a['created_at']);
      final bDate = DateTime.parse(b['created_at']);
      return bDate.compareTo(aDate);
    });
    return results;
  }

  List<dynamic> mockResultsSorted(List<dynamic> results) {
    results.sort((a, b) {
      final aDate = DateTime.parse(a['exam_date']);
      final bDate = DateTime.parse(b['exam_date']);
      return bDate.compareTo(aDate);
    });
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('학습 기록 확인'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '단어 시험'),
            Tab(text: '모의고사'),
          ],
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildVocabTab(),
                _buildMockTab(),
              ],
            ),
    );
  }

  Widget _buildVocabTab() {
    return RefreshIndicator(
      onRefresh: () => _fetchRecords(silent: true),
      child: _vocabResults.isEmpty
          ? _buildEmptyState(Icons.history, '단어 시험 기록이 없습니다.')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _vocabResults.length,
              itemBuilder: (context, index) =>
                  _buildVocabListItem(_vocabResults[index]),
            ),
    );
  }

  Widget _buildMockTab() {
    return RefreshIndicator(
      onRefresh: () => _fetchRecords(silent: true),
      child: _mockResults.isEmpty
          ? _buildEmptyState(Icons.assignment, '모의고사 기록이 없습니다.')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _mockResults.length,
              itemBuilder: (context, index) =>
                  _buildMockListItem(_mockResults[index]),
            ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(icon, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Center(
            child: Text(message, style: const TextStyle(color: Colors.grey))),
      ],
    );
  }

  Widget _buildVocabListItem(dynamic result) {
    final DateTime date = DateTime.parse(result['created_at']);
    final String formattedDate = DateFormat('yy.MM.dd HH:mm').format(date);

    final List details = result['details'] ?? [];
    final totalCount =
        result['total_count'] ?? (result['score'] + result['wrong_count']);

    final pendingCount = details
        .where((d) =>
            d['is_correction_requested'] == true && d['is_resolved'] == false)
        .length;
    final resolvedCount = details
        .where((d) =>
            d['is_resolved'] == true && d['is_correction_requested'] == true)
        .length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          result['book_title'] ?? '개별 시험',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$formattedDate | 범위: ${result['test_range']}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${result['score']} / $totalCount',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: result['score'] >= (totalCount * 0.9)
                    ? Colors.green
                    : Colors.redAccent,
              ),
            ),
            if (pendingCount > 0)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('정정 요청중',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold)),
              ),
            if (resolvedCount > 0 && pendingCount == 0)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('정정 반영됨',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        children: [
          const Divider(height: 1),
          Container(
            color: Colors.grey.shade50,
            child: Column(
              children: details.map((d) {
                final bool isCorrect = d['is_correct'];
                final bool isPending = d['is_correction_requested'] == true &&
                    d['is_resolved'] == false;

                final String rawAnswer = d['student_answer'] ?? '';
                final bool isAllEmpty = details.every((item) =>
                    (item['student_answer'] ?? '').toString().isEmpty);

                // Heuristic: If all answers are empty, it's likely an offline test.
                final String displayAnswer = rawAnswer.isEmpty
                    ? (isAllEmpty ? '(오프라인 시험)' : '(미입력)')
                    : rawAnswer;

                return ListTile(
                  dense: true,
                  leading: Icon(
                    isCorrect ? Icons.check_circle : Icons.cancel,
                    color: isCorrect ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  title: Text(d['word_question'],
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle:
                      Text('답: $displayAnswer / 정답: ${d['correct_answer']}'),
                  trailing: isPending
                      ? const Icon(Icons.hourglass_empty,
                          size: 16, color: Colors.orange)
                      : null,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMockListItem(dynamic exam) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          exam['title'] ?? '모의고사',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '시행일: ${exam['exam_date']} | 등급: ${exam['grade'] ?? '-'}등급',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
        trailing: Text(
          '${exam['score']}점',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        onTap: () {
          if (exam['note'] != null && exam['note'].toString().isNotEmpty) {
            showDialog(
                context: context,
                builder: (c) => AlertDialog(
                      title: const Text('피드백/비고'),
                      content: Text(exam['note']),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('확인'),
                        )
                      ],
                    ));
          }
        },
      ),
    );
  }
}
