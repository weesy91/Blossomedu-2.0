import 'dart:async';
import 'dart:convert'; // [NEW]
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart'; // [NEW]
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants.dart';
import '../../../core/services/academy_service.dart';
import '../../../core/services/vocab_service.dart';
import '../../../core/utils/web_monitor_helper.dart';

class ProjectorTestConfigDialog extends StatefulWidget {
  const ProjectorTestConfigDialog({super.key});

  @override
  State<ProjectorTestConfigDialog> createState() =>
      _ProjectorTestConfigDialogState();
}

class _ProjectorTestConfigDialogState extends State<ProjectorTestConfigDialog> {
  final AcademyService _academyService = AcademyService();
  final VocabService _vocabService = VocabService();

  // Step 1: Student Search
  int _step = 1;
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  Map<String, dynamic>? _selectedStudent;

  // [NEW] Book Workflow
  List<dynamic> _availableBooks = [];
  List<dynamic> _publishers = []; // [NEW]
  int? _selectedPublisherId;
  Map<String, dynamic>? _selectedBook;
  bool _isLoadingBooks = false;

  // [NEW] Test Type
  String _testType = 'normal'; // 'normal', 'wrong_answer'

  // [NEW] Range Controller
  final TextEditingController _rangeController =
      TextEditingController(text: '1-1');

  // Config Options
  double _durationPerWord = 5.0; // Seconds [FIX] Default 5s
  String _mode = 'eng_kor'; // eng_kor, kor_eng
  // RangeValues _dayRange = const RangeValues(1, 1); // Removed in favor of Controller
  int _maxDay = 1;

  // [NEW] Book Search
  // Removed unused fields

  @override
  void initState() {
    super.initState();
    // Debounce search? Or just use search button. Text field has onSubmitted.
  }

  // --- Step 1 Logic ---

  Future<void> _searchStudents(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      // Use searchStudents (which returns raw list)
      final results = await _academyService.searchStudents(query: query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('검색 실패: $e')));
      }
    }
  }

  void _selectStudent(Map<String, dynamic> student) {
    setState(() {
      _selectedStudent = student;
      _step = 2;
    });
    _loadBooks();
  }

  // --- Step 2 Logic ---

  Future<void> _loadBooks() async {
    setState(() => _isLoadingBooks = true);
    try {
      // Fetch both books and publishers
      final results = await Future.wait([
        _vocabService.getVocabBooks(),
        _vocabService.getPublishers(),
      ]);

      if (mounted) {
        setState(() {
          _availableBooks = results[0];
          _publishers = results[1]
              .where((p) =>
                  p['name'] != 'SYSTEM' && p['name'] != '개인단어장') // [FIX] Filter
              .toList();
          // Sort publishers by name
          _publishers
              .sort((a, b) => (a['name'] as String).compareTo(b['name']));
          _isLoadingBooks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBooks = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('데이터 로드 실패: $e')));
      }
    }
  }

  void _onBookSelected(Map<String, dynamic> book) {
    setState(() {
      _selectedBook = book;
      // Reset Range
      _maxDay = book['total_days'] ?? book['totalDays'] ?? 30;
      if (_maxDay < 1) _maxDay = 1;
      // [FIX] Use Text Controller
      _rangeController.text = '1-$_maxDay';
    });
  }

  bool _isStarting = false;

  Future<void> _startProjector() async {
    // [FIX] Allow start without book if Wrong Answer Mode
    if (_testType == 'normal' && _selectedBook == null) return;

    final rangeStr = _rangeController.text.trim();
    if (rangeStr.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('시험 범위를 입력하세요')));
      return;
    }

    setState(() => _isStarting = true);

    final bookId = _testType == 'normal' ? _selectedBook!['id'] : 0;
    // For normal test: Student ID is optional. For Wrong Answer: Required.
    final studentId = _selectedStudent != null ? _selectedStudent!['id'] : null;
    final duration = _durationPerWord.toInt();

    try {
      print('[DEBUG] Generating test questions for bookId: $bookId');

      // 1. Generate Test Questions (Server-side handling POS/Selection)
      final List<dynamic> result = await _vocabService.generateTestQuestions(
        bookId: bookId,
        range: _testType == 'normal'
            ? (rangeStr.isEmpty ? 'ALL' : rangeStr)
            : 'WRONG_ONLY',
        count: 30, // Standard Offline Test Size
        // [FIX] Only pass studentId for 'wrong_answer' mode to avoid 400 errors if server validates student state
        studentId: _testType == 'wrong_answer' ? studentId : null,
      );

      print('[DEBUG] Generated ${result.length} questions');

      if (result.isEmpty) {
        throw Exception('출제할 단어가 없습니다. 범위를 확인해주세요.');
      }

      // Map to consistent format safely
      final testWords = result
          .map((w) {
            if (w is! Map) {
              print('[ERROR] Invalid item format: $w');
              return <String, dynamic>{};
            }
            return {
              'id': w['id'],
              'wordId': w['word_id'] ?? 0,
              'english': w['english'] ?? '',
              'korean': w['korean'] ?? '', // Specific meaning for the POS
              'pos': w['pos']?.toString() ?? '', // Specific POS (String)
              'meaning_groups':
                  w['meaning_groups'] ?? [], // Full data if needed
            };
          })
          .where((w) => w.isNotEmpty)
          .toList()
          .cast<Map<String, dynamic>>();

      print('[DEBUG] Mapped words. Encoding to JSON...');

      // 2. Save to SharedPreferences for Projector Window (Cross-Window Data Sharing)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('offline_test_data', jsonEncode(testWords));
        print('[DEBUG] Saved to SharedPreferences');
      } catch (e) {
        print('[ERROR] SharedPreferences error: $e');
        // Continue globally but log it? Or throw? Projector won't work without it.
        throw Exception('설정 저장 실패: $e');
      }

      // 3. Construct Projector URL with 'local' source
      final uri = Uri(
        path: '/teacher/offline-test/projection',
        queryParameters: {
          'dataSource': 'local', // [NEW] Read from Prefs
          'bookId': bookId.toString(), // For BG image
          'duration': duration.toString(),
          'mode': _mode,
          // 'studentId': studentId.toString(), // Optional for display
        },
      );
      final fullPath = '/#${uri.toString()}';

      print('[DEBUG] Opening Projector Window: $fullPath');

      // 4. Open Projector Window
      bool launched = await WebMonitorHelper.openProjectorWindow(fullPath,
          title: 'Blossomedu Projector');
      if (!launched) {
        if (await canLaunchUrl(Uri.parse(fullPath))) {
          await launchUrl(Uri.parse(fullPath), webOnlyWindowName: '_blank');
        }
      }

      // 5. Navigate to Grading Screen (Main Monitor)
      if (mounted) {
        context.pop(); // Close Dialog
        context.push('/teacher/offline-test/grading', extra: {
          'words': testWords, // Pass EXACT same list
          'studentId': studentId?.toString() ?? '',
          'bookId': bookId,
          'range': rangeStr,
        });
      }
    } catch (e) {
      print('[ERROR] _startProjector failed: $e');
      if (mounted) {
        setState(() => _isStarting = false);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('오류 발생'),
            content: Text('시험 실행 중 오류가 발생했습니다.\ndetail: $e'),
            actions: [
              TextButton(
                  onPressed: () => context.pop(), child: const Text('확인'))
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 500, // Fixed width for desktop/tablet
        height: 600,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _step == 1 ? _buildStep1() : _buildStep2(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.connected_tv,
              color: AppColors.primary, size: 28), // Projector Icon
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('단어 시험 실행',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (_step == 2 && _selectedStudent != null)
                Text('학생: ${_selectedStudent!['name']}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('시험 볼 학생을 선택해주세요',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '이름 또는 전화번호 검색',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ))
                  : IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => _searchStudents(_searchController.text),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: _searchStudents,
            autofocus: true,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _searchResults.isEmpty
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? '검색어를 입력하세요.'
                          : '검색 결과가 없습니다.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: _searchResults.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final s = _searchResults[index];
                      // [FIX] Use school_name NOT school (which is ID)
                      final school = s['school_name'] ?? '-';
                      final grade = s['grade_display'] ?? s['grade'] ?? '-';
                      return ListTile(
                        leading: CircleAvatar(child: Text(s['name'][0])),
                        title: Text(s['name']),
                        subtitle: Text('$school / $grade'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _selectStudent(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    // Filter books by publisher
    final filteredBooks = _selectedPublisherId == null
        ? <dynamic>[]
        : _availableBooks.where((b) {
            final p = b['publisher'];
            if (p is int) return p == _selectedPublisherId;
            if (p is Map) return p['id'] == _selectedPublisherId;
            return false;
          }).toList();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [NEW] Test Type Selector
                Row(
                  children: [
                    _buildTypeChip('normal', '일반 시험'),
                    const SizedBox(width: 12),
                    _buildTypeChip('wrong_answer', '오답 노트 시험'),
                  ],
                ),
                const SizedBox(height: 24),

                if (_testType == 'normal') ...[
                  // 1. Publisher Selector
                  const Text('출판사 선택',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _isLoadingBooks
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<int>(
                          value: _selectedPublisherId,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          hint: const Text('출판사를 선택하세요'),
                          items: _publishers.map<DropdownMenuItem<int>>((p) {
                            return DropdownMenuItem(
                              value: p['id'],
                              child: Text(p['name']),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedPublisherId = val;
                              _selectedBook = null; // Reset book
                            });
                          },
                        ),

                  const SizedBox(height: 24),

                  // 2. Book Selector
                  const Text('교재 선택',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedBook?['id'].toString(),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    hint: Text(_selectedPublisherId == null
                        ? '출판사를 먼저 선택하세요'
                        : (filteredBooks.isEmpty
                            ? '등록된 교재가 없습니다'
                            : '교재를 선택하세요')),
                    items: filteredBooks.map<DropdownMenuItem<String>>((book) {
                      return DropdownMenuItem(
                        value: book['id'].toString(),
                        child: Text(
                          book['title'],
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      final book = _availableBooks
                          .firstWhere((b) => b['id'].toString() == val);
                      _onBookSelected(book);
                    },
                    disabledHint: Text(_selectedPublisherId == null
                        ? '출판사를 먼저 선택하세요'
                        : '등록된 교재가 없습니다'),
                    onTap: null,
                  ),

                  // [FIX] Hide Range until book is selected
                  if (_selectedBook != null) ...[
                    const SizedBox(height: 24),
                    // Range Input
                    const Text('시험 범위 (Day)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _rangeController,
                      decoration: InputDecoration(
                        hintText: '예: 1-5 또는 1,3,5',
                        helperText: '최대 Day: $_maxDay',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      keyboardType: TextInputType.datetime,
                    ),
                  ]
                ] else ...[
                  // Wrong Answer Mode UI
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange),
                        const SizedBox(width: 12),
                        const Expanded(
                            child:
                                Text('학생이 이전에 틀린 단어들 중 최대 30문제를 무작위로 출제합니다.')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // [FIX] Show Options only if valid state
                if (_testType == 'wrong_answer' ||
                    (_testType == 'normal' && _selectedBook != null)) ...[
                  const SizedBox(height: 24),
                  // 3. Options (Mode & Duration)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('시험 모드',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _mode,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'eng_kor', child: Text('영어 -> 한글')),
                                DropdownMenuItem(
                                    value: 'kor_eng', child: Text('한글 -> 영어')),
                              ],
                              onChanged: (v) => setState(() => _mode = v!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('제한 시간 (초)',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<double>(
                              value: _durationPerWord,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              items: [2.0, 3.0, 5.0, 7.0, 10.0].map((t) {
                                return DropdownMenuItem(
                                    value: t, child: Text('${t.toInt()}초'));
                              }).toList(),
                              onChanged: (v) =>
                                  setState(() => _durationPerWord = v!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // Actions (Fixed at bottom)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _step = 1), // Back
                child: const Text('이전'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: (_isStarting ||
                        (_testType == 'normal' && _selectedBook == null))
                    ? null
                    : _startProjector,
                icon: _isStarting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_isStarting ? '준비중...' : '단어 시험 실행'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip(String type, String label) {
    final isSelected = _testType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _testType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isSelected ? AppColors.primary : Colors.grey.shade300),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.grey.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
