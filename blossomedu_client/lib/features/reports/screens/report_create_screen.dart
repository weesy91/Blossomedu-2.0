import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';
import 'package:fl_chart/fl_chart.dart';

// Helper Function for Subject Name
String _getSubjectName(String code) {
  switch (code) {
    case 'SYNTAX':
      return '1:1 구문수업';
    case 'READING':
      return '독해수업';
    case 'GRAMMAR':
      return '어법수업';
    case 'LISTENING':
      return '듣기수업';
    default:
      return code;
  }
}

class ReportCreateScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  const ReportCreateScreen({required this.student, super.key});

  @override
  State<ReportCreateScreen> createState() => _ReportCreateScreenState();
}

class _ReportCreateScreenState extends State<ReportCreateScreen> {
  DateTime _currentMonth = DateTime.now();
  final TextEditingController _commentController = TextEditingController();

  bool _isLoading = false;
  Map<String, dynamic>? _previewData;
  String? _generatedLink;

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  void _changeMonth(int offset) {
    setState(() {
      _currentMonth =
          DateTime(_currentMonth.year, _currentMonth.month + offset, 1);
      _generatedLink = null; // Reset link on date change
    });
    _fetchPreview();
  }

  Future<void> _fetchPreview() async {
    setState(() => _isLoading = true);

    // Calculate start/end dates
    final start = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final end =
        DateTime(_currentMonth.year, _currentMonth.month + 1, 0); // Last day

    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return; // Should navigate to login

      final url =
          Uri.parse('${AppConfig.baseUrl}/academy/api/v1/reports/preview/');
      final response = await http.post(url,
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'student_id': widget.student['id'],
            'start_date': startStr,
            'end_date': endStr,
          }));

      if (response.statusCode == 200) {
        setState(() {
          _previewData = jsonDecode(utf8.decode(response.bodyBytes));
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load preview');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _generateReport() async {
    setState(() => _isLoading = true);
    final start = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final end = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final startStr = DateFormat('yyyy-MM-dd').format(start);
    final endStr = DateFormat('yyyy-MM-dd').format(end);

    final title = '${DateFormat('yyyy년 M월').format(_currentMonth)} 학습 성적표';

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final url =
          Uri.parse('${AppConfig.baseUrl}/academy/api/v1/reports/generate/');
      final response = await http.post(url,
          headers: {
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'student_id': widget.student['id'],
            'start_date': startStr,
            'end_date': endStr,
            'title': title,
            'teacher_comment': _commentController.text,
          }));

      if (response.statusCode == 200) {
        final result = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _generatedLink = result['generated_url'];
          _isLoading = false;
        });
        _showLinkDialog();
      } else {
        throw Exception('생성 실패: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showLinkDialog() {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('🎉 성적표 생성 완료!'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('아래 링크를 학부모님께 공유해주세요.'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(_generatedLink ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                        IconButton(
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: _generatedLink ?? ''));
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('복사 완료!')));
                            },
                            icon: const Icon(Icons.copy))
                      ],
                    ),
                  )
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('닫기')),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.student['name']} 성적표'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 1. Month Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Icons.chevron_left)),
                Text(DateFormat('yyyy년 M월').format(_currentMonth),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_previewData != null)
              _buildReportContent()
            else
              const Center(child: Text('데이터를 불러올 수 없습니다.')),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _generateReport,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: Colors.indigo,
          ),
          child: const Text('성적표 생성 및공유',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildReportContent() {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              isScrollable: true,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              tabs: [
                Tab(text: '개요'),
                Tab(text: '단어'),
                Tab(text: '과제'),
                Tab(text: '수업일지'),
                Tab(text: '모의고사'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 600, // Fixed height for tab content
            child: TabBarView(
              children: [
                _buildOverviewTab(),
                _buildVocabTab(),
                _buildAssignmentsTab(),
                _buildLogsTab(),
                _buildMockTestTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final stats = _previewData!['stats'];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummarySection(stats),
          const SizedBox(height: 24),
          const Text('선생님 총평',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '이번 달 학습 태도나 성취도에 대해 작성해주세요.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text('이번 달 진도',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          // Textbook progress is usually part of overview, keeping it simple for now
          // Assuming stats might have progress data or just placeholder
          const SizedBox(height: 100), // Spacing
        ],
      ),
    );
  }

  Widget _buildVocabTab() {
    final vocab = _previewData!['vocab'] as List;
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildVocabHeatmap(vocab),
          const SizedBox(height: 24),
          if (vocab.isNotEmpty) _buildVocabChart(vocab),
          const SizedBox(height: 24),
          _buildVocabList(vocab),
        ],
      ),
    );
  }

  Widget _buildAssignmentsTab() {
    final assignments = _previewData!['assignments'] as List;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('과제 내역 (${assignments.length}건)'),
          ...assignments.map((a) => ExpansionTile(
                leading: Icon(
                  a['is_completed']
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: a['is_completed'] ? Colors.green : Colors.red,
                ),
                title: Text(a['title']),
                subtitle: Text(a['status'] ?? '-'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (a['submission_image'] != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: () => showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                      child: Image.network(
                                          '${AppConfig.baseUrl}${a['submission_image']}'))),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('📷 인증 사진 (탭하여 확대)',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                        '${AppConfig.baseUrl}${a['submission_image']}',
                                        height: 120,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (a['feedback'] != null &&
                            a['feedback'].toString().isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('👨‍🏫 선생님 피드백',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.blue)),
                                  const SizedBox(height: 4),
                                  Text(a['feedback'],
                                      style: TextStyle(
                                          color: Colors.blue.shade900)),
                                ]),
                          ),
                        if (a['due_date'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                                '마감일: ${a['due_date'].toString().substring(0, 10)}',
                                style: const TextStyle(color: Colors.grey)),
                          ),
                      ],
                    ),
                  )
                ],
              )),
        ],
      ),
    );
  }

  Widget _buildLogsTab() {
    final logs = _previewData!['logs'] as List;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('수업 일지 (${logs.length}건)'),
          ...logs.map((l) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.grey.withOpacity(0.1), blurRadius: 6)
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: Colors.indigo.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(
                              _getSubjectName(
                                  l['subject_code'] ?? l['subject']),
                              style: const TextStyle(
                                  color: Colors.indigo,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        Text('${l['date']}',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // 진도
                    if (l['details'] != null &&
                        (l['details'] as List).isNotEmpty) ...[
                      const Text('📚 진도 및 학습 내용',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      ...(l['details'] as List).map((d) {
                        final score = d['score'];
                        Color badgeColor = Colors.grey;
                        if (score == 'A') badgeColor = Colors.blue;
                        if (score == 'B') badgeColor = Colors.green;
                        if (score == 'C') badgeColor = Colors.orange;
                        if (score == 'F') badgeColor = Colors.red;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                      color: badgeColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: badgeColor)),
                                  child: Text(score,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: badgeColor,
                                          fontWeight: FontWeight.bold)),
                                ),
                                Expanded(
                                    child: Text(d['text'] ?? '',
                                        style: const TextStyle(
                                            fontSize: 13, height: 1.3))),
                              ]),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                    // 과제 (Updated with Status Check)
                    if (l['homeworks'] != null &&
                        (l['homeworks'] as List).isNotEmpty) ...[
                      const Text('📝 배부된 과제',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      ...(l['homeworks'] as List).map((h) {
                        final isCompleted = h['is_completed'] == true;
                        return Padding(
                          padding: const EdgeInsets.only(left: 0, top: 4),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 2, right: 6),
                                  child: Icon(
                                      isCompleted
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 14,
                                      color: isCompleted
                                          ? Colors.green
                                          : Colors.red),
                                ),
                                Expanded(
                                    child: Text('${h['title']}',
                                        style: const TextStyle(
                                            fontSize: 13, height: 1.3))),
                                if (h['due_date'] != null)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: Text(
                                        '~${h['due_date'].toString().substring(5, 10)}',
                                        style: const TextStyle(
                                            fontSize: 11, color: Colors.red)),
                                  ),
                              ]),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                    // 코멘트 (Unified Header)
                    if ((l['teacher_comment'] != null &&
                            l['teacher_comment'].toString().isNotEmpty) ||
                        (l['comment'] != null &&
                            l['comment'].toString().isNotEmpty))
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('👨‍🏫 선생님 피드백',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.black87)),
                              const SizedBox(height: 4),
                              Text(
                                  (l['teacher_comment'] != null &&
                                          l['teacher_comment']
                                              .toString()
                                              .isNotEmpty)
                                      ? l['teacher_comment']
                                      : l[
                                          'comment'], // Use general comment if teacher_comment is empty
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.4)),
                            ]),
                      )
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildMockTestTab() {
    return const Center(child: Text('준비중입니다.'));
  }

  Widget _buildVocabList(List vocab) {
    if (vocab.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('단어 시험 (${vocab.length}회) - 클릭하여 상세 확인'),
        ...vocab.map((v) => ExpansionTile(
              title: Text(v['book__title'] ?? '단어장'),
              trailing: Text('${v['score']} / ${v['total_count'] ?? 0}점',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('시험 범위: ${v['test_range'] ?? '전체'}'),
                      const SizedBox(height: 8),
                      if (v['wrong_words'] != null &&
                          (v['wrong_words'] as List).isNotEmpty) ...[
                        const Text('오답 노트',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red)),
                        const SizedBox(height: 8),
                        Table(
                          border: TableBorder.all(color: Colors.grey.shade200),
                          columnWidths: const {
                            0: FlexColumnWidth(1),
                            1: FlexColumnWidth(1)
                          },
                          children: [
                            TableRow(
                                decoration:
                                    BoxDecoration(color: Colors.grey.shade100),
                                children: const [
                                  Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text('문제',
                                          style: TextStyle(fontSize: 12))),
                                  Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text('정답',
                                          style: TextStyle(fontSize: 12))),
                                ]),
                            ...(v['wrong_words'] as List).map((w) =>
                                TableRow(children: [
                                  Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(w['word'] ?? '',
                                          style:
                                              const TextStyle(fontSize: 12))),
                                  Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text(w['answer'] ?? '',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold))),
                                ])),
                          ],
                        )
                      ] else
                        const Text('틀린 단어가 없습니다! 🎉',
                            style: TextStyle(color: Colors.blue)),
                    ],
                  ),
                )
              ],
            )),
      ],
    );
  }

  // Helper for section headers
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 24),
      child: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  // New Summary Section with Detailed Stats
  Widget _buildSummarySection(Map<String, dynamic> stats) {
    // Attendance
    final attRaw = stats['attendance_breakdown'] ?? {};
    int present = int.tryParse(attRaw['present']?.toString() ?? '0') ?? 0;
    int late = int.tryParse(attRaw['late']?.toString() ?? '0') ?? 0;
    int absent = int.tryParse(attRaw['absent']?.toString() ?? '0') ?? 0;
    int totalAtt = present + late + absent;

    // Assignment
    final assignRaw = stats['assignment_breakdown'] ?? {};
    int assignOnTime =
        int.tryParse(assignRaw['on_time']?.toString() ?? '0') ?? 0;
    int assignLate = int.tryParse(assignRaw['late']?.toString() ?? '0') ?? 0;
    int assignMissing =
        int.tryParse(assignRaw['missing']?.toString() ?? '0') ?? 0;

    String vocabAvg = stats['vocab_avg']?.toString() ?? '0';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatBox(
            '출석률',
            '$present / $totalAtt', // Fraction Format
            subWidget: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniLabel('등원 $present', Colors.green),
                const SizedBox(width: 8),
                _miniLabel('지각 $late', Colors.orange),
                const SizedBox(width: 8),
                _miniLabel('결석 $absent', Colors.red),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildStatBox(
            '과제 수행',
            '${stats['assignment_completed']}/${stats['assignment_count']}',
            subWidget: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniLabel('정시 $assignOnTime', Colors.green),
                const SizedBox(width: 8),
                _miniLabel('지각 $assignLate', Colors.orange),
                const SizedBox(width: 8),
                _miniLabel('미제출 $assignMissing', Colors.red),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildStatBox(
            '단어 평균',
            '$vocabAvg%',
            subWidget: const SizedBox(height: 14),
          ),
        ],
      ),
    );
  }

  Widget _miniLabel(String text, Color color) {
    return Text(text,
        style:
            TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold));
  }

  Widget _buildStatBox(String label, String value, {Widget? subWidget}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (subWidget != null) ...[
              const SizedBox(height: 8),
              subWidget,
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildVocabHeatmap(List vocab) {
    if (vocab.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🔥 학습 열정 (최근 30일)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 10,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.0,
            ),
            itemCount: 30,
            itemBuilder: (context, index) {
              final today = DateTime.now();
              final now = DateTime(today.year, today.month, today.day);
              final targetDate = now.subtract(Duration(days: 29 - index));

              bool hasActivity = false;
              for (var v in vocab) {
                if (v['created_at'] != null) {
                  DateTime? d = DateTime.tryParse(v['created_at'].toString());
                  if (d != null) {
                    final localD = d.toLocal();
                    if (localD.year == targetDate.year &&
                        localD.month == targetDate.month &&
                        localD.day == targetDate.day) {
                      hasActivity = true;
                      break;
                    }
                  }
                }
              }

              return Container(
                decoration: BoxDecoration(
                  color: hasActivity ? Colors.green : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${targetDate.day}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasActivity ? Colors.white : Colors.grey.shade400,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          const Text('학습한 날짜에 색이 칠해집니다.',
              style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildVocabChart(List vocab) {
    if (vocab.isEmpty) return const SizedBox();
    List<FlSpot> spots = [];

    // [FIX] Reverse list to plot Chronologically
    final reversedVocab = vocab.reversed.toList();
    for (int i = 0; i < reversedVocab.length; i++) {
      double val = (reversedVocab[i]['cumulative_passed'] ?? 0).toDouble();
      spots.add(FlSpot(i.toDouble(), val));
    }

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📈 누적 통과 단어 수',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(
                  show: true,
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                        show: true, color: Colors.blue.withOpacity(0.1)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
