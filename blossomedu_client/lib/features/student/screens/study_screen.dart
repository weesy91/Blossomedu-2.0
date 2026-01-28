import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/services/vocab_service.dart';

import '../../../core/constants.dart';
// import 'student_book_selection_screen.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen>
    with SingleTickerProviderStateMixin {
  final VocabService _vocabService = VocabService();

  // Real Data
  List<dynamic> _myBooks = [];
  Map<String, dynamic> _stats = {'my_books_count': 0, 'wrong_words_count': 0};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ?붾㈃ ?ъ쭊?????ㅻ떟 移댁슫?????곗씠??媛깆떊
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final booksFuture = _vocabService.getVocabBooks();
      final statsFuture = _vocabService.getStats();
      final dashboardFuture = _vocabService.getStudyDashboard();

      final results =
          await Future.wait([booksFuture, statsFuture, dashboardFuture]);

      if (mounted) {
        setState(() {
          _myBooks = results[0] as List<dynamic>;
          _stats = results[1] as Map<String, dynamic>;
          final dashboard = results[2] as Map<String, dynamic>;
          final growth = (dashboard['growth'] as List?) ?? [];
          final heatmap = (dashboard['heatmap'] as List?) ?? [];
          final rankings = (dashboard['rankings'] as Map?) ?? {};
          final events = (rankings['events'] as List?) ?? [];

          _growthSpots.clear();
          int maxCount = 0;
          for (int i = 0; i < growth.length; i++) {
            final item = growth[i] as Map<String, dynamic>? ?? {};
            final count = int.tryParse(item['count']?.toString() ?? '0') ?? 0;
            if (count > maxCount) maxCount = count;
            _growthSpots.add(FlSpot(i.toDouble(), count.toDouble()));
          }
          _growthMaxY = math.max(10, (maxCount * 1.2).ceil()).toDouble();

          _studyHeatmap.clear();
          for (final item in heatmap) {
            final map = item as Map<String, dynamic>? ?? {};
            final intensity =
                int.tryParse(map['intensity']?.toString() ?? '0') ?? 0;
            _studyHeatmap.add(intensity);
          }

          _monthlyRankings.clear();
          final monthly = (rankings['monthly'] as List?) ?? [];
          _monthlyRankings.addAll(
              monthly.map((e) => Map<String, dynamic>.from(e)).toList());

          _activeEvents.clear();
          _eventRankingsByTitle.clear();
          for (final event in events) {
            final eventMap = event as Map<String, dynamic>? ?? {};
            final title = eventMap['title']?.toString() ?? '';
            if (title.isEmpty) continue;
            final bookRaw = eventMap['target_book_id'];
            final bookId = bookRaw is int
                ? bookRaw
                : int.tryParse(bookRaw?.toString() ?? '0') ?? 0;
            if (bookId > 0) {
              _activeEvents[title] = bookId;
            }
            final eventRanks = (eventMap['rankings'] as List?) ?? [];
            _eventRankingsByTitle[title] =
                eventRanks.map((e) => Map<String, dynamic>.from(e)).toList();
          }

          if (_selectedEventTitle == null ||
              !_eventRankingsByTitle.containsKey(_selectedEventTitle)) {
            _selectedEventTitle =
                events.isNotEmpty ? events.first['title']?.toString() : null;
          }
          _eventRankings.clear();
          if (_selectedEventTitle != null) {
            _eventRankings
                .addAll(_eventRankingsByTitle[_selectedEventTitle] ?? []);
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        print('Error loading data: $e');
      }
    }
  }

  // Method to get dynamic study methods
  List<Map<String, dynamic>> get _studyMethods => [
        {
          'title': '\uB0B4 \uB2E8\uC5B4\uC7A5 (My Books)',
          'subtitle':
              '\uB4F1\uB85D\uB41C ${_stats['my_books_count']}\uAD8C\uC758 \uB2E8\uC5B4\uC7A5\uC73C\uB85C \uD559\uC2B5',
          'icon': Icons.menu_book,
          'color': Colors.indigo,
          'route': 'books',
        },
        {
          'title': '\uC624\uB2F5 \uC9D1\uC911 (Snowball)',
          'subtitle':
              '\uD2C0\uB9B0 \uB2E8\uC5B4\uB97C \uBAA8\uC544 \uC9D1\uC911 \uACF5\uB7B5 (${_stats['wrong_words_count']}\uAC1C)',
          'icon': Icons.cleaning_services,
          'color': Colors.redAccent,
          'route': 'wrong_note',
        },
        {
          'title': '\uB7AD\uD0B9\uC804 (Event)',
          'subtitle':
              '\uC9C4\uD589 \uC911\uC778 \uC774\uBCA4\uD2B8 \uBCF4\uAE30',
          'icon': Icons.emoji_events,
          'color': Colors.amber.shade700,
          'route': 'event',
        },
        {
          'title': '\uD1B5\uD569 \uB2E8\uC5B4 \uAC80\uC0C9 (Search)',
          'subtitle':
              '\uBAA8\uB974\uB294 \uB2E8\uC5B4\uB97C \uCC3E\uC544 \uBC14\uB85C \uC624\uB2F5\uB178\uD2B8\uB85C',
          'icon': Icons.search,
          'color': Colors.teal,
          'route': 'search',
        },
      ];

  // Dashboard data (replace mock with real data when API is ready).
  final List<int> _studyHeatmap = [];
  final List<FlSpot> _growthSpots = [];
  double _growthMaxY = 100;

  // Ranking data (empty until backend is connected).
  bool _isEventRanking = true; // Toggle state
  final List<Map<String, dynamic>> _eventRankings = [];
  final List<Map<String, dynamic>> _monthlyRankings = [];
  final Map<String, List<Map<String, dynamic>>> _eventRankingsByTitle = {};
  String? _selectedEventTitle;

  // Active events (empty until backend is connected).
  final Map<String, int> _activeEvents = {};

  // Mock Data for Methods

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('학습 대시보드'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Dashboard Section
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Row: Growth Graph (Left) & Heatmap (Right)
                  SizedBox(
                    height: 240, // Height for the row
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left: Growth Graph
                        Expanded(
                          flex: 5,
                          child: _buildGrowthGraph(),
                        ),
                        const SizedBox(width: 12),
                        // Right: Heatmap (Grass)
                        Expanded(
                          flex: 4,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade100),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                        '\uC6D4\uAC04 \uD559\uC2B5 \uAE30\uB85D',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13)),
                                    const Spacer(),
                                    const Icon(Icons.calendar_month,
                                        size: 14, color: Colors.grey),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                    child: Center(
                                        child: _buildInteractiveHeatmap())),
                                const Align(
                                  alignment: Alignment.centerRight,
                                  child: Text('Click details',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.grey)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Ranking Section (Now Bottom)
                  _buildRankingSection(),
                ],
              ),
            ),

            const SizedBox(height: 24),
            // ... (Methods)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: _studyMethods
                    .map((method) => _buildMethodCard(method))
                    .toList(),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildGrowthGraph() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: _growthSpots.isEmpty
          ? const Center(
              child: Text(
                '\uD559\uC2B5 \uAE30\uB85D\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    '\uCD5C\uADFC \uB204\uC801 \uC678\uC6B4 \uB2E8\uC5B4',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                const Text(
                    '\uCD5C\uADFC 7\uC77C\uAC04\uC758 \uD559\uC2B5\uB7C9 \uBCC0\uD654\uC785\uB2C8\uB2E4.',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(height: 16),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.grey.shade100,
                            strokeWidth: 1,
                          );
                        },
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              switch (value.toInt()) {
                                case 0:
                                  return const Text('Mon',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 10));
                                case 3:
                                  return const Text('Wed',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 10));
                                case 6:
                                  return const Text('Sat',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 10));
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      maxY: _growthMaxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: _growthSpots,
                          isCurved: true,
                          color: AppColors.primary,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.primary.withOpacity(0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRankingSection() {
    final List<String> events = _activeEvents.keys.toList();
    final String? selectedEvent = _selectedEventTitle;
    final List<Map<String, dynamic>> rankingSource =
        _isEventRanking ? _eventRankings : _monthlyRankings;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // 1. Tab Header (Event vs Monthly)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isEventRanking = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: _isEventRanking
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              width: 2)),
                    ),
                    child: Center(
                        child: Text('\uC774\uBCA4\uD2B8 \uB7AD\uD0B9',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isEventRanking
                                    ? AppColors.primary
                                    : Colors.grey))),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isEventRanking = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: !_isEventRanking
                                  ? AppColors.primary
                                  : Colors.grey.shade200,
                              width: 2)),
                    ),
                    child: Center(
                        child: Text('\uC6D4\uAC04 \uB7AD\uD0B9',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: !_isEventRanking
                                    ? AppColors.primary
                                    : Colors.grey))),
                  ),
                ),
              ),
            ],
          ),

          // 2. Event Selector Dropdown (Visible only when Event Ranking is active)
          if (_isEventRanking) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              width: double.infinity,
              color: Colors.grey.shade50,
              child: events.isEmpty
                  ? const Text(
                      '\uC9C4\uD589 \uC911\uC778 \uC774\uBCA4\uD2B8\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
                      style: TextStyle(fontSize: 12, color: Colors.grey))
                  : Row(
                      children: [
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedEvent,
                              isDense: true,
                              isExpanded: true,
                              icon: const Icon(Icons.arrow_drop_down,
                                  size: 20, color: Colors.grey),
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.black87),
                              items: events
                                  .map((e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e,
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedEventTitle = val;
                                  _eventRankings.clear();
                                  if (val != null) {
                                    _eventRankings.addAll(
                                        _eventRankingsByTitle[val] ?? []);
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],

          if (rankingSource.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                  '\uB7AD\uD0B9 \uB370\uC774\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            )
          else
            ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rankingSource.length > 5 ? 5 : rankingSource.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 12, endIndent: 12),
              itemBuilder: (context, index) {
                final ranker =
                    rankingSource.length > index ? rankingSource[index] : null;
                if (ranker == null) return const SizedBox();

                final isTop3 = index < 3;
                return ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  visualDensity: const VisualDensity(vertical: -2),
                  leading: CircleAvatar(
                    radius: 10,
                    backgroundColor: isTop3
                        ? Colors.amber.withOpacity(0.2)
                        : Colors.grey.shade100,
                    child: Text('${index + 1}',
                        style: TextStyle(
                            color: isTop3 ? Colors.amber.shade800 : Colors.grey,
                            fontWeight: FontWeight.bold,
                            fontSize: 10)),
                  ),
                  title: Text(ranker['name'],
                      style: const TextStyle(fontSize: 12)),
                  trailing: Text('${ranker['score']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildInteractiveHeatmap() {
    if (_studyHeatmap.isEmpty) {
      return const Center(
        child: Text(
          '\uD559\uC2B5 \uAE30\uB85D\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final boxWidth = (constraints.maxWidth - (6 * 6)) / 7; // Gap 6px
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _studyHeatmap.asMap().entries.map((entry) {
          final index = entry.key;
          final intensity = entry.value;
          Color color;
          switch (intensity) {
            case 0:
              color = Colors.grey.shade200;
              break;
            case 1:
              color = Colors.green.shade100;
              break;
            case 2:
              color = Colors.green.shade300;
              break;
            case 3:
              color = Colors.green.shade500;
              break;
            default:
              color = Colors.transparent;
          }
          return GestureDetector(
            onTap: () => _showDayHistory(context, index, intensity),
            child: Container(
              width: boxWidth.clamp(10, 40),
              height: boxWidth.clamp(10, 40),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300, width: 0.5),
              ),
            ),
          );
        }).toList(),
      );
    });
  }

  void _showDayHistory(BuildContext context, int dayIndex, int intensity) {
    final targetDate = DateTime.now().subtract(Duration(days: 27 - dayIndex));
    final dateStr = targetDate.toString().substring(0, 10);
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return FutureBuilder<Map<String, dynamic>>(
              future: _vocabService.getDayHistory(dateStr),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return const SizedBox(
                    height: 300,
                    child: Center(
                      child: Text(
                          '\uB370\uC774\uD130\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  );
                }

                final data = snapshot.data ?? {};
                final tests = (data['tests'] as List?) ?? [];

                return Container(
                  padding: const EdgeInsets.all(24),
                  height: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$dateStr \uD559\uC2B5 \uAE30\uB85D',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 16),
                      if (tests.isEmpty)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                    '\uD559\uC2B5 \uAE30\uB85D\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.',
                                    style: TextStyle(color: Colors.grey))))
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: tests.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item =
                                  tests[index] as Map<String, dynamic>? ?? {};
                              final type = item['type']?.toString() ?? 'normal';
                              final bookTitle =
                                  item['book_title']?.toString() ?? '';
                              final time = item['time']?.toString() ?? '--:--';
                              final score = int.tryParse(
                                      item['score']?.toString() ?? '0') ??
                                  0;
                              final total = int.tryParse(
                                      item['total']?.toString() ?? '0') ??
                                  0;
                              final titleText = type == 'monthly'
                                  ? '[\uC6D4\uAC04] $bookTitle'
                                  : bookTitle;

                              return ListTile(
                                leading: Icon(
                                  score >= total * 0.9
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: score >= total * 0.9
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                title: Text(titleText),
                                subtitle: Text('$score / $total'),
                                trailing: Text(time),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              });
        });
  }

  Widget _buildMethodCard(Map<String, dynamic> method) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (method['route'] == 'wrong_note') {
              _showSnowballConfigSheet(context);
            } else if (method['route'] == 'books') {
              _showBookListBottomSheet(context);
            } else if (method['route'] == 'event') {
              _showEventListBottomSheet(context);
            } else if (method['route'] == 'search') {
              _showWordSearchSheet(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      '\uC900\uBE44\uC911\uC778 \uAE30\uB2A5\uC785\uB2C8\uB2E4.')));
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (method['color'] as Color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(method['icon'], color: method['color'], size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method['title'],
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(method['subtitle'],
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBookListBottomSheet(BuildContext context) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(24),
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('\uB0B4 \uB2E8\uC5B4\uC7A5 (My Books)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        final added =
                            await this.context.push('/student/book/select');
                        if (added == true) {
                          _loadData();
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('\uCD94\uAC00'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                    '\uD559\uC2B5\uD560 \uAD50\uC7AC\uB97C \uC120\uD0DD\uD574 \uC8FC\uC138\uC694.',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _myBooks.isEmpty
                          ? const Center(
                              child: Text(
                                  '\uB4F1\uB85D\uB41C \uB2E8\uC5B4\uC7A5\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.'),
                            )
                          : ListView.separated(
                              itemCount: _myBooks.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final book = _myBooks[index];
                                return Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 8),
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                          color: Colors.indigo.shade50,
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: const Icon(Icons.menu_book_rounded,
                                          color: Colors.indigo),
                                    ),
                                    title: Text(book['title'] as String,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                        '${book['publisher_name'] ?? '\uCD9C\uD310\uC0AC \uC5C6\uC74C'} \u00B7 \uCD1D ${book['total_days'] ?? book['totalDays'] ?? 0}\uC77C\uCC28'),
                                    trailing: const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                        color: Colors.grey),
                                    onTap: () {
                                      context.pop();
                                      _showRangePicker(context, book);
                                    },
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        });
  }

  void _handleEventChallenge(String eventName) {
    final targetBookId = _activeEvents[eventName];
    if (targetBookId == null) return;

    final hasBook = _myBooks.any((book) => book['id'] == targetBookId);

    if (hasBook) {
      final book = _myBooks.firstWhere((book) => book['id'] == targetBookId);
      _showRangePicker(context, book);
    } else {
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text(
                    '\uD544\uC694\uD55C \uAD50\uC7AC\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4'),
                content: Text(
                    "'$eventName'\uC5D0 \uCC38\uC5EC\uD558\uB824\uBA74 \uD574\uB2F9 \uAD50\uC7AC\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.\n\uB2E8\uC5B4\uC7A5\uC5D0 \uCD94\uAC00\uD55C \uB4A4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694."),
                actions: [
                  TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('\uD655\uC778')),
                ],
              ));
    }
  }

  void _showEventListBottomSheet(BuildContext context) {
    final events = _activeEvents.keys.toList();

    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(24),
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    '\uC9C4\uD589 \uC911\uC778 \uB7AD\uD0B9 \uC774\uBCA4\uD2B8',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                if (events.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                          '\uC9C4\uD589 \uC911\uC778 \uC774\uBCA4\uD2B8\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final eventName = events[index];
                        return ListTile(
                          leading: const Icon(Icons.emoji_events,
                              color: Colors.amber),
                          title: Text(eventName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text(
                              '\uC774\uBCA4\uD2B8 \uCC38\uC5EC\uD558\uAE30'),
                          trailing: const Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.grey),
                          onTap: () {
                            context.pop();
                            _handleEventChallenge(eventName);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        });
  }

  void _showRangePicker(BuildContext context, Map<String, dynamic> book) {
    int startDay = 1;
    int endDay = 1;

    // Test Options
    bool isWordToMeaning = true;
    String testMode = 'test'; // 'study' (Card) or 'test' (Typing)

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return StatefulBuilder(builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book['title'] as String,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        '\uD559\uC2B5 \uBC94\uC704\uC640 \uBAA8\uB4DC\uB97C \uC124\uC815\uD574\uC8FC\uC138\uC694.',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),

                    // 1. Day Range Picker
                    const Text('\uD559\uC2B5 \uBC94\uC704 (Day)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '\uC2DC\uC791 Day',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            controller:
                                TextEditingController(text: startDay.toString())
                                  ..selection = TextSelection.fromPosition(
                                      TextPosition(
                                          offset: startDay.toString().length)),
                            onChanged: (val) {
                              final parsed = int.tryParse(val);
                              if (parsed != null) {
                                setState(() {
                                  startDay = parsed;
                                  if (endDay < startDay) endDay = startDay;
                                });
                              }
                            },
                          ),
                        ),
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('~',
                                style: TextStyle(
                                    fontSize: 20, color: Colors.grey))),
                        Expanded(
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: '\uC885\uB8CC Day',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            controller:
                                TextEditingController(text: endDay.toString())
                                  ..selection = TextSelection.fromPosition(
                                      TextPosition(
                                          offset: endDay.toString().length)),
                            onChanged: (val) {
                              final parsed = int.tryParse(val);
                              if (parsed != null) {
                                setState(() => endDay = parsed);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 2. Mode Selector (Study vs Test)
                    const Text('\uD559\uC2B5 \uBAA8\uB4DC',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => testMode = 'study'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: testMode == 'study'
                                    ? AppColors.primary.withOpacity(0.1)
                                    : Colors.white,
                                border: Border.all(
                                    color: testMode == 'study'
                                        ? AppColors.primary
                                        : Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.style,
                                      color: testMode == 'study'
                                          ? AppColors.primary
                                          : Colors.grey),
                                  const SizedBox(height: 8),
                                  Text('\uCE74\uB4DC \uD559\uC2B5',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: testMode == 'study'
                                              ? AppColors.primary
                                              : Colors.black)),
                                  const SizedBox(height: 4),
                                  const Text('\uC2DC\uAC04\uC81C\uD55C X',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // [NEW] Practice Mode Button
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => testMode = 'practice'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: testMode == 'practice'
                                    ? Colors.orange.withOpacity(0.1)
                                    : Colors.white,
                                border: Border.all(
                                    color: testMode == 'practice'
                                        ? Colors.orange
                                        : Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.edit_note,
                                      color: testMode == 'practice'
                                          ? Colors.orange
                                          : Colors.grey),
                                  const SizedBox(height: 8),
                                  Text('연습 모드',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: testMode == 'practice'
                                              ? Colors.orange
                                              : Colors.black)),
                                  const SizedBox(height: 4),
                                  const Text('기록 X',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => testMode = 'test'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: testMode == 'test'
                                    ? Colors.red.withOpacity(0.05)
                                    : Colors.white,
                                border: Border.all(
                                    color: testMode == 'test'
                                        ? Colors.red
                                        : Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.timer,
                                      color: testMode == 'test'
                                          ? Colors.red
                                          : Colors.grey),
                                  const SizedBox(height: 8),
                                  Text('\uC2E4\uC804 \uC2E4\uD5D8',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: testMode == 'test'
                                              ? Colors.red
                                              : Colors.black)),
                                  const SizedBox(height: 4),
                                  const Text('\uAE30\uB85D \uBC18\uC601 O',
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 3. Question Type (show for test AND practice)
                    if (testMode == 'test' || testMode == 'practice') ...[
                      const Text('\uBB38\uC81C \uC720\uD615',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilterChip(
                            label: const Text(
                                '\uB2E8\uC5B4 -> \uB73B (\uC8FC\uAD00\uC2DD)'),
                            selected: isWordToMeaning,
                            showCheckmark: false,
                            onSelected: (val) =>
                                setState(() => isWordToMeaning = true),
                            selectedColor: Colors.white,
                            backgroundColor: Colors.grey.shade100,
                            labelStyle: TextStyle(
                                color: isWordToMeaning
                                    ? AppColors.primary
                                    : Colors.grey.shade600,
                                fontWeight: isWordToMeaning
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                  color: isWordToMeaning
                                      ? AppColors.primary
                                      : Colors.transparent,
                                  width: isWordToMeaning ? 2.0 : 1.0),
                            ),
                            elevation: isWordToMeaning ? 2 : 0,
                            shadowColor: Colors.black.withOpacity(0.1),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text(
                                '\uB73B -> \uB2E8\uC5B4 (\uC8FC\uAD00\uC2DD)'),
                            selected: !isWordToMeaning,
                            showCheckmark: false,
                            onSelected: (val) =>
                                setState(() => isWordToMeaning = false),
                            selectedColor: Colors.white,
                            backgroundColor: Colors.grey.shade100,
                            labelStyle: TextStyle(
                                color: !isWordToMeaning
                                    ? AppColors.primary
                                    : Colors.grey.shade600,
                                fontWeight: !isWordToMeaning
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                  color: !isWordToMeaning
                                      ? AppColors.primary
                                      : Colors.transparent,
                                  width: !isWordToMeaning ? 2.0 : 1.0),
                            ),
                            elevation: !isWordToMeaning ? 2 : 0,
                            shadowColor: Colors.black.withOpacity(0.1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                    ],

                    // 4. Start Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          context.pop();
                          context.push('/student/test/start', extra: {
                            'bookId': book['id'],
                            'range': '$startDay-$endDay',
                            'assignmentId':
                                'self_study_${DateTime.now().millisecondsSinceEpoch}',
                            'testMode': testMode, // 'study' or 'test'
                            'isSubjective': true, // Always subjective for now
                            'questionType': isWordToMeaning
                                ? 'word_to_meaning'
                                : 'meaning_to_word',
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        child: Text(
                            testMode == 'study'
                                ? '\uD559\uC2B5 \uC2DC\uC791\uD558\uAE30'
                                : '\uC2E4\uD5D8 \uC2DC\uC791\uD558\uAE30',
                            style: const TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          });
        });
  }

  void _showWordSearchSheet(BuildContext context) {
    final TextEditingController searchController = TextEditingController();
    Map<String, dynamic>? searchResult;
    bool isSearching = false;
    String? errorMessage;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return StatefulBuilder(builder: (context, setState) {
            Future<void> runSearch(String query) async {
              final trimmed = query.trim();
              if (trimmed.isEmpty) return;
              setState(() {
                isSearching = true;
                errorMessage = null;
              });

              try {
                final results = await _vocabService.searchWords(trimmed);
                setState(() {
                  if (results.isNotEmpty) {
                    searchResult = Map<String, dynamic>.from(results.first);
                  } else {
                    searchResult = null;
                    errorMessage =
                        '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.';
                  }
                });
              } catch (e) {
                setState(() {
                  searchResult = null;
                  errorMessage =
                      '\uAC80\uC0C9 \uC911 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4.';
                });
              } finally {
                setState(() => isSearching = false);
              }
            }

            Future<void> addToWrongNote() async {
              if (searchResult == null) return;
              final english = (searchResult?['english'] ?? '').toString();
              final korean = (searchResult?['korean'] ?? '').toString();
              if (english.isEmpty || korean.isEmpty) return;

              try {
                await _vocabService.addPersonalWord(
                  english: english,
                  korean: korean,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          '\uC624\uB2F5\uB178\uD2B8\uC5D0 \uCD94\uAC00\uB418\uC5C8\uC2B5\uB2C8\uB2E4.')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          '\uC624\uB2F5\uB178\uD2B8 \uCD94\uAC00\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.')));
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        '\uD1B5\uD569 \uB2E8\uC5B4 \uAC80\uC0C9 \uD83D\uDD0D',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                        '\uB2E8\uC5B4\uC7A5\uC5D0 \uC5C6\uC73C\uBA74 \uC678\uBD80 \uC0AC\uC804\uC5D0\uC11C \uAC00\uC838\uC635\uB2C8\uB2E4.',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 20),

                    // Search Bar
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                          hintText:
                              '\uB2E8\uC5B4\uB97C \uC785\uB825\uD574 \uC8FC\uC138\uC694.',
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () {
                              runSearch(searchController.text);
                            },
                          )),
                      onSubmitted: (val) => runSearch(val),
                    ),
                    const SizedBox(height: 24),

                    if (isSearching)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (errorMessage != null)
                      Expanded(
                        child: Center(
                          child: Text(errorMessage!,
                              style: const TextStyle(color: Colors.grey)),
                        ),
                      )
                    else if (searchResult == null)
                      const Expanded(
                        child: Center(
                          child: Text(
                              '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5EC\uAE30\uC5D0 \uD45C\uC2DC\uB429\uB2C8\uB2E4.',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4))
                            ]),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(searchResult!['english']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Text(
                                      (searchResult!['from'] == 'db')
                                          ? 'DB'
                                          : 'External API',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.blue)),
                                )
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(searchResult!['korean']?.toString() ?? '',
                                style: const TextStyle(
                                    fontSize: 18, color: Colors.grey)),
                            const SizedBox(height: 8),
                            if (searchResult!['book'] != null)
                              Text(searchResult!['book'].toString(),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: addToWrongNote,
                                icon: const Icon(Icons.add_circle_outline,
                                    color: Colors.white),
                                label: const Text(
                                    '\uC624\uB2F5\uB178\uD2B8\uC5D0 \uB2F4\uAE30',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))),
                              ),
                            )
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          });
        });
  }

  void _showSnowballConfigSheet(BuildContext context) {
    // [Fix] Use Real Data
    final wrongCount = _stats['wrong_words_count'] ?? 0;

    // Default Options
    bool isWordToMeaning = true;
    String testMode = 'test'; // 'study' or 'test'

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return StatefulBuilder(builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('\uC624\uB2F5 \uC9D1\uC911 (Snowball)',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        '\uD2C0\uB9B0 \uB2E8\uC5B4\uB97C \uBAA8\uC544 \uC9D1\uC911 \uD559\uC2B5\uD569\uB2C8\uB2E4.',
                        style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),

                    // 1. Info Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('현재 누적 오답: $wrongCount개',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          const SizedBox(height: 4),
                          // [Fix] Text Update
                          const Text(
                              '\uC9C0\uAE08\uAE4C\uC9C0 \uD559\uC2B5\uD558\uBA70 \uD2C0\uB9B0 \uBAA8\uB4E0 \uB2E8\uC5B4\uAC00 \uD3EC\uD568\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // [Fix] Empty State Handling
                    if (wrongCount == 0) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 64, color: Colors.green),
                              SizedBox(height: 16),
                              Text(
                                  '\uC644\uBCBD\uD569\uB2C8\uB2E4! \uD559\uC2B5\uD560 \uC624\uB2F5\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              SizedBox(height: 8),
                              Text(
                                  '\uC544\uB798\uC5D0\uC11C \uB2E8\uC5B4\uC7A5\uC744 \uD559\uC2B5\uD558\uAC70\uB098 \uC2E4\uD5D8\uC744 \uBD10\uBCF4\uC138\uC694.',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () => context.pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('\uB2EB\uAE30',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18)),
                        ),
                      ),
                    ] else ...[
                      // 2. Mode Selector (Study vs Test)
                      const Text('\uD559\uC2B5 \uBAA8\uB4DC \uC120\uD0DD',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => testMode = 'study'),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: testMode == 'study'
                                      ? AppColors.primary.withOpacity(0.1)
                                      : Colors.white,
                                  border: Border.all(
                                      color: testMode == 'study'
                                          ? AppColors.primary
                                          : Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.style,
                                        color: testMode == 'study'
                                            ? AppColors.primary
                                            : Colors.grey),
                                    const SizedBox(height: 8),
                                    Text(
                                        '\uCE74\uB4DC \uC624\uB2F5 \uD559\uC2B5',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: testMode == 'study'
                                                ? AppColors.primary
                                                : Colors.black)),
                                    const SizedBox(height: 4),
                                    const Text('시간제한 X',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // [NEW] Practice Mode Button
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => testMode = 'practice'),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: testMode == 'practice'
                                      ? Colors.orange.withOpacity(0.1)
                                      : Colors.white,
                                  border: Border.all(
                                      color: testMode == 'practice'
                                          ? Colors.orange
                                          : Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.edit_note,
                                        color: testMode == 'practice'
                                            ? Colors.orange
                                            : Colors.grey),
                                    const SizedBox(height: 8),
                                    Text('연습 모드',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: testMode == 'practice'
                                                ? Colors.orange
                                                : Colors.black)),
                                    const SizedBox(height: 4),
                                    const Text('기록 X',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => testMode = 'test'),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                decoration: BoxDecoration(
                                  color: testMode == 'test'
                                      ? Colors.red.withOpacity(0.05)
                                      : Colors.white,
                                  border: Border.all(
                                      color: testMode == 'test'
                                          ? Colors.red
                                          : Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.timer,
                                        color: testMode == 'test'
                                            ? Colors.red
                                            : Colors.grey),
                                    const SizedBox(height: 8),
                                    Text('\uC2E4\uC804 \uC2E4\uD5D8',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: testMode == 'test'
                                                ? Colors.red
                                                : Colors.black)),
                                    const SizedBox(height: 4),
                                    const Text('\uAE30\uB85D \uBC18\uC601 O',
                                        style: TextStyle(
                                            fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 3. Question Type (show for test AND practice)
                      if (testMode == 'test' || testMode == 'practice') ...[
                        const Text('\uBB38\uC81C \uC720\uD615',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            FilterChip(
                              label: const Text('단어 -> 뜻'),
                              selected: isWordToMeaning,
                              showCheckmark: false,
                              onSelected: (val) =>
                                  setState(() => isWordToMeaning = true),
                              selectedColor: Colors.white,
                              backgroundColor: Colors.grey.shade100,
                              labelStyle: TextStyle(
                                  color: isWordToMeaning
                                      ? AppColors.primary
                                      : Colors.grey,
                                  fontWeight: isWordToMeaning
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                              side: BorderSide(
                                  color: isWordToMeaning
                                      ? AppColors.primary
                                      : Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('뜻 -> 단어'),
                              selected: !isWordToMeaning,
                              showCheckmark: false,
                              onSelected: (val) =>
                                  setState(() => isWordToMeaning = false),
                              selectedColor: Colors.white,
                              backgroundColor: Colors.grey.shade100,
                              labelStyle: TextStyle(
                                  color: !isWordToMeaning
                                      ? AppColors.primary
                                      : Colors.grey,
                                  fontWeight: !isWordToMeaning
                                      ? FontWeight.bold
                                      : FontWeight.normal),
                              side: BorderSide(
                                  color: !isWordToMeaning
                                      ? AppColors.primary
                                      : Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                      ],

                      // Start Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            context.pop();
                            context.push('/student/test/start', extra: {
                              'bookId': 0, // 0 for Snowball
                              'range': 'WRONG_ONLY',
                              'assignmentId': '0',
                              'testMode': testMode, // Passed from state
                              'questionType': isWordToMeaning
                                  ? 'word_to_meaning'
                                  : 'meaning_to_word',
                            }).then((_) => _loadData());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: testMode == 'test'
                                ? Colors.red
                                : AppColors.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(
                              testMode == 'test'
                                  ? '\uC2E4\uD5D8 \uC2DC\uC791\uD558\uAE30'
                                  : '\uD559\uC2B5 \uC2DC\uC791\uD558\uAE30',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.white)),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            );
          });
        });
  }
}
