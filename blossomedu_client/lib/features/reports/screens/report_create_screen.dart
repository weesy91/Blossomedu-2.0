import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants.dart';

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
    final stats = _previewData!['stats'];
    final logs = _previewData!['logs'] as List;
    final assignments = _previewData!['assignments'] as List;
    final vocab = _previewData!['vocab'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 2. Summary Cards
        Row(
          children: [
            _buildSummaryCard(
                '출석률', '${stats['attendance_rate'].round()}%', Colors.blue),
            const SizedBox(width: 8),
            _buildSummaryCard(
                '과제 수행',
                '${stats['assignment_completed']}/${stats['assignment_count']}',
                Colors.green),
            const SizedBox(width: 8),
            _buildSummaryCard('단어 평균', '${stats['vocab_avg']}', Colors.orange),
          ],
        ),
        const SizedBox(height: 24),

        // 3. Comment Input
        const Text('선생님 총평',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _commentController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '이번 달 학습 태도나 성취도에 대해 작성해주세요.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),

        // 4. Details (Simple Preview)
        _buildSectionHeader('단어 시험 (${vocab.length}회)'),
        ...vocab.take(3).map((v) => ListTile(
              title: Text(v['book__title'] ?? '단어장'),
              trailing: Text('${v['score']} / ${v['total_count'] ?? 0}'),
              visualDensity: VisualDensity.compact,
            )),
        if (vocab.length > 3)
          const Padding(padding: EdgeInsets.all(8), child: Text('...외 다수')),

        _buildSectionHeader('과제 내역 (${assignments.length}건)'),
        ...assignments.take(3).map((a) => ListTile(
              title: Text(a['title']),
              trailing: Icon(
                a['is_completed'] ? Icons.check_circle : Icons.cancel,
                color: a['is_completed'] ? Colors.green : Colors.red,
                size: 20,
              ),
              visualDensity: VisualDensity.compact,
            )),

        _buildSectionHeader('수업 일지 (${logs.length}건)'),
        ...logs.take(3).map((l) => ListTile(
              title: Text('${l['date']} ${l['subject']}'),
              subtitle: Text(l['comment'] ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              visualDensity: VisualDensity.compact,
            )),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }
}
