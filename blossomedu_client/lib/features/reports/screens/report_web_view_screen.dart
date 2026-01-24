import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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

class ReportWebViewScreen extends StatefulWidget {
  final String uuid;
  final bool isPreview;

  const ReportWebViewScreen(
      {required this.uuid, this.isPreview = false, super.key});

  @override
  State<ReportWebViewScreen> createState() => _ReportWebViewScreenState();
}

class _ReportWebViewScreenState extends State<ReportWebViewScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      final url = Uri.parse(
          '${AppConfig.baseUrl}/academy/api/v1/reports/public/${widget.uuid}/');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        setState(() {
          _report = jsonDecode(utf8.decode(response.bodyBytes));
          _isLoading = false;
        });
      } else {
        throw Exception('성적표를 찾을 수 없습니다.');
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(body: Center(child: Text(_error!)));
    if (_report == null)
      return const Scaffold(body: Center(child: Text('데이터 없음')));

    final data = _report!['data_snapshot'];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
              decoration: const BoxDecoration(
                color: Colors.indigo,
                borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30)),
              ),
              child: Column(
                children: [
                  const Text('BlossomEdu',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          letterSpacing: 2)),
                  const SizedBox(height: 10),
                  Text(_report!['title'] ?? '학습 성적표',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${_report!['student_name']} 학생',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: _buildReportContent(data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent(Map<String, dynamic> data) {
    final stats = data['stats'];
    final logs = data['logs'] as List;
    final assignments = data['assignments'] as List;
    final vocab = data['vocab'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 2. Summary
        _buildSummarySection(stats),
        const SizedBox(height: 24),

        // 2.5 Vocab Chart (Cumulative)
        if (vocab.isNotEmpty) _buildVocabChart(vocab),
        const SizedBox(height: 24),

        // 3. Teacher Comment
        if (data['teacher_comment'] != null &&
            data['teacher_comment'].toString().isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
              ],
              border: Border.all(color: Colors.indigo.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.format_quote, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('선생님 총평',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.indigo)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(data['teacher_comment'],
                    style: const TextStyle(height: 1.6, fontSize: 15)),
              ],
            ),
          ),
        const SizedBox(height: 24),

        // 4. Accordion Details
        _buildExpansionSection('📘 단어 시험 내역',
            vocab.isEmpty ? _emptyView() : _buildVocabList(vocab)),
        const SizedBox(height: 12),
        _buildExpansionSection(
            '📝 과제 수행 내역',
            assignments.isEmpty
                ? _emptyView()
                : _buildAssignmentList(assignments)),
        const SizedBox(height: 12),
        _buildExpansionSection(
            '🏫 수업 일지', logs.isEmpty ? _emptyView() : _buildLogList(logs)),

        const SizedBox(height: 40),
        Center(
            child: Text('BlossomEdu Academy',
                style: TextStyle(color: Colors.grey.shade400))),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSummarySection(Map<String, dynamic> stats) {
    return Row(
      children: [
        _buildStatBox('출석률', '${stats['attendance_rate'].round()}%'),
        const SizedBox(width: 12),
        _buildStatBox('과제 수행',
            '${stats['assignment_completed']}/${stats['assignment_count']}'),
        const SizedBox(width: 12),
        _buildStatBox('단어 평균', '${stats['vocab_avg']}점'),
      ],
    );
  }

  Widget _buildStatBox(String label, String value) {
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
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildVocabChart(List vocab) {
    if (vocab.isEmpty) return const SizedBox();
    List<FlSpot> spots = [];

    // Cumulative Passed Words Chart
    for (int i = 0; i < vocab.length; i++) {
      double val = (vocab[i]['cumulative_passed'] ?? 0).toDouble();
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

  Widget _buildExpansionSection(String title, Widget content) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5)
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          children: [
            Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                child: content),
          ],
        ),
      ),
    );
  }

  Widget _emptyView() => const Padding(
      padding: EdgeInsets.all(16),
      child: Text('데이터가 없습니다.', style: TextStyle(color: Colors.grey)));

  Widget _buildVocabList(List list) {
    return Column(
      children: list
          .map((v) => ExpansionTile(
                title: Text(v['book__title'] ?? '단어장'),
                trailing: Text('${v['score']} / ${v['total_count'] ?? 0}점',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '범위: ${v['test_range'] ?? '전체'} | 오답: ${v['wrong_count']}'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (v['wrong_words'] != null &&
                            (v['wrong_words'] as List).isNotEmpty) ...[
                          const Text('오답 노트',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          const SizedBox(height: 8),
                          Table(
                            border:
                                TableBorder.all(color: Colors.grey.shade200),
                            columnWidths: const {
                              0: FlexColumnWidth(1),
                              1: FlexColumnWidth(1)
                            },
                            children: [
                              TableRow(
                                  decoration: BoxDecoration(
                                      color: Colors.grey.shade100),
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
              ))
          .toList(),
    );
  }

  Widget _buildAssignmentList(List list) {
    return Column(
      children: list
          .map((a) => ExpansionTile(
                leading: Icon(
                    a['is_completed']
                        ? Icons.check_circle_outline
                        : Icons.circle_outlined,
                    color: a['is_completed'] ? Colors.green : Colors.red,
                    size: 24),
                title: Text(a['title']),
                subtitle: a['status'] != null ? Text(a['status']) : null,
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
              ))
          .toList(),
    );
  }

  Widget _buildLogList(List list) {
    return Column(
        children: list.map((l) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(_getSubjectName(l['subject_code'] ?? l['subject']),
                    style: const TextStyle(
                        color: Colors.indigo,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
              ),
              const SizedBox(width: 8),
              Text('${l['date']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
            const SizedBox(height: 12),
            // 진도
            if (l['details'] != null && (l['details'] as List).isNotEmpty) ...[
              const Text('📚 진도 및 학습 내용',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
            // 과제
            if (l['homeworks'] != null &&
                (l['homeworks'] as List).isNotEmpty) ...[
              const Text('📝 배부된 과제',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              ...(l['homeworks'] as List).map((h) => Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                              child: Text('${h['title']}',
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.3))),
                          if (h['due_date'] != null)
                            Container(
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
                  )),
              const SizedBox(height: 12),
            ],
            if (l['teacher_comment'] != null &&
                l['teacher_comment'].toString().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
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
                      Text(l['teacher_comment'],
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ]),
              )
          ],
        ),
      );
    }).toList());
  }
}
