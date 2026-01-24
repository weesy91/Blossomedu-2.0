import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/constants.dart';

class ReportWebViewScreen extends StatefulWidget {
  final String uuid;
  final bool
      isPreview; // If true, data might be passed via extra? No, preview API is diff.
  // Actually, Web View uses UUID to fetch from public API.

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
    // If isPreview, we might need a different flow, but for now assuming UUID exists.
    try {
      final url = Uri.parse(
          '${AppConfig.baseUrl}/academy/api/v1/reports/public/${widget.uuid}/');
      // No Token Header required for public view
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
    final stats = data['stats'];
    final logs = data['logs'] as List;
    final assignments = data['assignments'] as List;
    final vocab = data['vocab'] as List;
    final attendances = data['attendance'] as List; // Need calendar logic

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2. Summary
                  Row(
                    children: [
                      _buildStatBox(
                          '출석률', '${stats['attendance_rate'].round()}%'),
                      const SizedBox(width: 12),
                      _buildStatBox('단어 평균', '${stats['vocab_avg']}점'),
                      const SizedBox(width: 12),
                      _buildStatBox(
                          '과제 수행', '${stats['assignment_completed']}건'),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 3. Teacher Comment
                  if (_report!['teacher_comment'] != null &&
                      _report!['teacher_comment'].toString().isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10)
                        ],
                        border:
                            Border.all(color: Colors.indigo.withOpacity(0.1)),
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
                                      fontWeight: FontWeight.bold,
                                      color: Colors.indigo)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(_report!['teacher_comment'],
                              style:
                                  const TextStyle(height: 1.6, fontSize: 15)),
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
                      '📅 출결 현황',
                      attendances.isEmpty
                          ? _emptyView()
                          : _buildAttendanceGrid(attendances)),
                  const SizedBox(height: 12),
                  _buildExpansionSection('🏫 수업 일지',
                      logs.isEmpty ? _emptyView() : _buildLogList(logs)),

                  const SizedBox(height: 40),
                  Center(
                      child: Text('BlossomEdu Academy',
                          style: TextStyle(color: Colors.grey.shade400))),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
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
          .map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(item['book__title'] ?? '단어장',
                            overflow: TextOverflow.ellipsis)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text('${item['score']}점',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildAssignmentList(List list) {
    return Column(
      children: list
          .map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                        item['is_completed']
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                        color: item['is_completed'] ? Colors.green : Colors.red,
                        size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item['title'])),
                    if (item['due_date'] != null)
                      Text(item['due_date'].toString().substring(5, 10),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)), // MM-dd
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _buildLogList(List list) {
    return Column(
        children: list.map((l) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l['date']} ${l['subject']}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(l['comment'] ?? '', style: const TextStyle(fontSize: 14)),
          ],
        ),
      );
    }).toList());
  }

  Widget _buildAttendanceGrid(List list) {
    // Simple List for now, Calendar is complex
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: list.map((a) {
        final status = a['status'];
        Color color = Colors.grey;
        if (status == 'PRESENT') color = Colors.green;
        if (status == 'LATE') color = Colors.orange;
        if (status == 'ABSENT') color = Colors.red;

        final date = DateTime.tryParse(a['date']);
        final day = date != null ? date.day.toString() : '';

        return Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(day,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
