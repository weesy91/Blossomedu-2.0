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
  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(body: Center(child: Text(_error!)));
    if (_report == null)
      return const Scaffold(body: Center(child: Text('데이터 없음')));

    final data = _report!['data_snapshot'];

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: Text(_report!['title'] ?? '학습 성적표'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '개요'),
              Tab(text: '단어'),
              Tab(text: '과제'),
              Tab(text: '수업일지'),
              Tab(text: '모의고사'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOverviewTab(data),
            _buildVocabTab(data),
            _buildAssignmentsTab(data),
            _buildLogsTab(data),
            _buildMockTestTab(),
          ],
        ),
      ),
    );
  }

  // 1. Overview Tab
  Widget _buildOverviewTab(Map<String, dynamic> data) {
    final stats = data['stats'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1.1 Stats
          _buildSummarySection(stats),
          const SizedBox(height: 24),

          // 1.2 Textbook Progress (Derived from logs/vocab if possible, or placeholder logic)
          _buildTextbookProgress(data),
          const SizedBox(height: 24),

          // 1.3 Teacher Comment (Updated to check root key)
          if ((_report!['teacher_comment'] != null &&
                  _report!['teacher_comment'].toString().isNotEmpty) ||
              (data['teacher_comment'] != null &&
                  data['teacher_comment'].toString().isNotEmpty))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05), blurRadius: 10)
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
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Fix: Use data['teacher_comment'] if available, or try to find it in root _report object if accessible,
                  // but here we only have 'data'. However, in _fetchReport we see:
                  // _report = jsonDecode(...)
                  // data = _report!['data_snapshot']
                  // If teacher_comment is at root, we assume the backend puts it in data_snapshot OR we need to pass it.
                  // Current implementation of 'generate' in backend saves it to model, serializer likely puts it at root.
                  // So we should try to use the one passed in 'data' dictionary which comes from 'data_snapshot'.
                  // Wait, previous investigation showed backend DOES NOT put it in data_snapshot.
                  // So we must rely on what was passed to this function.
                  // I will modify the call site to include teacher_comment in data map or access _report.
                  // Since I cannot change call site easily within this function, I will assume the caller has been updated
                  // OR I will check if I can access outer class state. I can't access _report from here easily if it's not in state.
                  // Actually, I am in _ReportWebViewScreenState, so I CAN access _report!.

                  Text(
                      (_report != null && _report!['teacher_comment'] != null)
                          ? _report!['teacher_comment']
                          : (data['teacher_comment'] ?? '작성된 총평이 없습니다.'),
                      style: const TextStyle(height: 1.6, fontSize: 15)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 2. Vocab Tab
  Widget _buildVocabTab(Map<String, dynamic> data) {
    final vocab = data['vocab'] as List;
    final stats = data['stats'];
    final isRank1 = stats['rank'] == 1 || stats['rank_text'] == '1등';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 2.1 Rank Banner
          if (isRank1)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.amber, Colors.orange]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.emoji_events, color: Colors.white),
                  SizedBox(width: 8),
                  Text('🎉 이번 달 단어 랭킹 1등! 축하합니다!',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
            ),

          // 2.2 Existing Graph
          if (vocab.isNotEmpty) _buildVocabChart(vocab),
          const SizedBox(height: 24),

          // 2.3 Heatmap (Custom Simple Implementation)
          _buildVocabHeatmap(vocab),
          const SizedBox(height: 24),

          // 2.4 List
          if (vocab.isEmpty) _emptyView() else _buildVocabList(vocab),
        ],
      ),
    );
  }

  // 3. Assignments Tab
  Widget _buildAssignmentsTab(Map<String, dynamic> data) {
    final assignments = data['assignments'] as List;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: assignments.isEmpty
          ? _emptyView()
          : _buildAssignmentList(assignments),
    );
  }

  // 4. Logs Tab
  Widget _buildLogsTab(Map<String, dynamic> data) {
    final logs = data['logs'] as List;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: logs.isEmpty ? _emptyView() : _buildLogList(logs),
    );
  }

  // 5. Mock Test Tab
  Widget _buildMockTestTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('모의고사 성적표는 준비 중입니다.',
              style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }

  // --- Helpers for New Features ---

  Widget _buildTextbookProgress(Map<String, dynamic> data) {
    final tpMap = data['textbook_progress'];
    if (tpMap == null || (tpMap is! Map) || tpMap.isEmpty) {
      return const SizedBox();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📚 교재 진도율',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          ...tpMap.entries.map((entry) {
            final categoryKey = entry.key;
            final booksList = entry.value as List;
            if (booksList.isEmpty) return const SizedBox();

            String categoryName = categoryKey;
            switch (categoryKey) {
              case 'VOCABULARY':
                categoryName = '단어';
                break;
              case 'SYNTAX':
                categoryName = '구문';
                break;
              case 'GRAMMAR':
                categoryName = '문법';
                break;
              case 'READING':
                categoryName = '독해';
                break;
              case 'SCHOOL_EXAM':
                categoryName = '내신';
                break;
              case 'LISTENING':
                categoryName = '듣기';
                break;
              case 'OTHER':
                categoryName = '기타';
                break;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.only(
                      left: 4, top: 4, bottom: 4, right: 0),
                  decoration: const BoxDecoration(
                      border: Border(
                          left: BorderSide(color: Colors.blue, width: 3))),
                  child: Text('  $categoryName',
                      style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
                const SizedBox(height: 12),
                ...booksList.map((b) {
                  final totalUnits = b['total_units'] ?? 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b['title'] ?? '교재',
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      _buildSegmentedProgressBar(
                        totalUnits: totalUnits,
                        history: b['history'] ?? {},
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                            '${(b['history'] as Map).length} / $totalUnits 강',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 16),
                    ],
                  );
                }),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
          const SizedBox(height: 16),
          // Legend
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _buildLegendItem(
                      'A (100점)', const Color(0xFF2962FF)), // Blue A700
                  _buildLegendItem(
                      'B (95점~)', const Color(0xFF00C853)), // Green A700
                  _buildLegendItem(
                      'C (90점~)', const Color(0xFFFFAB00)), // Amber A700
                  _buildLegendItem(
                      'F (~89점)', const Color(0xFFD50000)), // Red A700
                  _buildLegendItem(
                      '수업/완료', const Color(0xFF00B8D4)), // Cyan A700
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildSegmentedProgressBar(
      {required int totalUnits, required Map history}) {
    if (totalUnits <= 0) return const SizedBox();

    if (totalUnits <= 0) return const SizedBox();

    const int itemsPerRow = 10;
    final int rowCount = (totalUnits / itemsPerRow).ceil();

    return Column(
      children: List.generate(rowCount, (rowIndex) {
        final int start = rowIndex * itemsPerRow;
        final int end = (start + itemsPerRow) > totalUnits
            ? totalUnits
            : start + itemsPerRow;
        final int itemsInThisRow = end - start;

        return Padding(
          padding: const EdgeInsets.only(bottom: 4), // Line spacing
          child: Row(
            children: [
              // True Items
              ...List.generate(itemsInThisRow, (index) {
                final globalIndex = start + index;
                final unitNum = globalIndex + 1;
                final score = history[unitNum.toString()];

                Color color = Colors.grey.shade200;
                Color textColor = Colors.grey.shade600;

                final s = score?.toString().toUpperCase();
                if (s == 'A') {
                  color = const Color(0xFF2962FF);
                  textColor = Colors.white;
                } else if (s == 'B') {
                  color = const Color(0xFF00C853);
                  textColor = Colors.white;
                } else if (s == 'C') {
                  color = const Color(0xFFFFAB00);
                  textColor = Colors.white;
                } else if (s == 'F') {
                  color = const Color(0xFFD50000);
                  textColor = Colors.white;
                } else if (s == 'P' || s == '수업' || s == '완료') {
                  color = const Color(0xFF00B8D4);
                  textColor = Colors.white;
                }

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: 18, // Slightly taller for text
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$unitNum',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: textColor),
                      ),
                    ),
                  ),
                );
              }),
              // Spacer Items (to keep alignment in last row)
              ...List.generate(itemsPerRow - itemsInThisRow, (_) {
                return const Expanded(child: SizedBox());
              }),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildVocabHeatmap(List vocab) {
    if (vocab.isEmpty) return const SizedBox();

    // Create a set of dates where vocab tests were taken
    // vocab list items likely have 'created_at' or 'test_date'
    // Checking existing usage or guess: usually vocab items in report are test results

    // Let's assume we want to show last 4 weeks activity
    // We will render a simple grid of 28 squares

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
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(30, (index) {
              // Calculate date for this cell (Today - 29 + index)
              // Wait, usually heatmap is ordered [Day-29, ..., Today]
              final today = DateTime.now();
              // Normalize today to start of day
              final now = DateTime(today.year, today.month, today.day);
              final targetDate = now.subtract(Duration(days: 29 - index));

              // Check if activity exists on targetDate
              bool hasActivity = false;
              for (var v in vocab) {
                if (v['created_at'] != null) {
                  DateTime? d = DateTime.tryParse(v['created_at'].toString());
                  if (d != null) {
                    final localD = d.toLocal(); // [FIX] Timezone match
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
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                    color: hasActivity ? Colors.green : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4)),
              );
            }),
          ),
          const SizedBox(height: 8),
          const Text('학습한 날짜에 색이 칠해집니다.',
              style: TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSummarySection(Map<String, dynamic> stats) {
    // [FIX] Calculate Attendance Counts locally
    int present = 0;
    int late = 0;
    int absent = 0;
    int totalAtt = 0;

    if (_report != null && _report!['data_snapshot'] != null) {
      final att = _report!['data_snapshot']['attendance'] as List?;
      if (att != null) {
        present = att.where((e) => e['status'] == 'PRESENT').length;
        late = att.where((e) => e['status'] == 'LATE').length;
        absent = att.where((e) => e['status'] == 'ABSENT').length;
        totalAtt = present + late + absent; // Total scheduled days
      }
    }

    // Assignment Breakdown
    final bd = stats['assignment_breakdown'] ?? {};
    final int assignOnTime = bd['on_time'] ?? 0;
    final int assignLate = bd['late'] ?? 0;
    final int assignMissing = bd['missing'] ?? 0;

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
            '${stats['vocab_avg']}%',
            subWidget: const SizedBox(
                height:
                    14), // Spacer to match height if needed, or rely on stretch
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

  Widget _buildStatBox(String label, String value,
      {VoidCallback? onTap, Widget? subWidget}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
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
      ),
    );
  }

  Widget _buildVocabChart(List vocab) {
    if (vocab.isEmpty) return const SizedBox();
    List<FlSpot> spots = [];

    // Cumulative Passed Words Chart
    // [FIX] Reverse list to plot Chronologically (Oldest -> Latest)
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

  Widget _emptyView() => const Padding(
      padding: EdgeInsets.all(16),
      child: Text('데이터가 없습니다.', style: TextStyle(color: Colors.grey)));

  Widget _buildVocabList(List list) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📝 상세 기록',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          Column(
            children: list
                .map((v) => ExpansionTile(
                      title: Text(v['book__title'] ?? '단어장'),
                      trailing: Text(
                          '${v['score']} / ${v['total_count'] ?? 0}점',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${v['created_at'].toString().substring(0, 10)} | 범위: ${v['test_range'] ?? '전체'} | 오답: ${v['wrong_count']}'),
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
                                  border: TableBorder.all(
                                      color: Colors.grey.shade200),
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
                                                  style:
                                                      TextStyle(fontSize: 12))),
                                          Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Text('정답',
                                                  style:
                                                      TextStyle(fontSize: 12))),
                                        ]),
                                    ...(v['wrong_words'] as List).map((w) =>
                                        TableRow(children: [
                                          Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(w['word'] ?? '',
                                                  style: const TextStyle(
                                                      fontSize: 12))),
                                          Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(w['answer'] ?? '',
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold))),
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
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentList(List list) {
    return Column(
      children: list
          .map((a) => ExpansionTile(
                leading: Icon(
                    a['is_completed']
                        ? Icons.check_circle
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
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '마감일: ${a['due_date'] != null ? a['due_date'].toString().substring(0, 10) : '미정'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.redAccent,
                                fontSize: 12),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)
          ],
        ),
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
            // 과제 (Updated with Status Check)
            if (l['homeworks'] != null &&
                (l['homeworks'] as List).isNotEmpty) ...[
              const Text('📝 배부된 과제',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              ...(l['homeworks'] as List).map((h) {
                final isCompleted = h['is_completed'] == true;
                return Padding(
                  padding: const EdgeInsets.only(left: 0, top: 4),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 6),
                          child: Icon(
                              isCompleted
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 14,
                              color: isCompleted ? Colors.green : Colors.red),
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
                (l['comment'] != null && l['comment'].toString().isNotEmpty))
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
                                  l['teacher_comment'].toString().isNotEmpty)
                              ? l['teacher_comment']
                              : l['comment'], // Use general comment if teacher_comment is empty
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ]),
              )
          ],
        ),
      );
    }).toList());
  }
}
