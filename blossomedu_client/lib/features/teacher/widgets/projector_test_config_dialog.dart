import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  // Step 2: Book & Config
  List<dynamic> _availableBooks = [];
  Map<String, dynamic>? _selectedBook;
  bool _isLoadingBooks = false;

  // Config Options
  double _durationPerWord = 3.0; // Seconds
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
      // 1. Fetch Student's My Books? Or All Books?
      // Since it's teacher/assistant, maybe All Books is better, but "Student's Books" is safer for assignments.
      // Let's fetch ALL books for maximum flexibility (Ad-hoc test).
      final books = await _vocabService.getVocabBooks();
      if (mounted) {
        setState(() {
          _availableBooks = books;
          _isLoadingBooks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBooks = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('교재 로드 실패: $e')));
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
    if (_selectedStudent == null || _selectedBook == null) return;

    // [FIX] Validate Range
    final rangeStr = _rangeController.text.trim();
    if (rangeStr.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('시험 범위를 입력하세요')));
      return;
    }

    setState(() => _isStarting = true);

    final studentId = _selectedStudent!['id'];
    final bookId = _selectedBook!['id'];
    // final rangeStr = ... using controller value now
    final duration = _durationPerWord.toInt();

    try {
      // 1. Fetch random words here (Master Source)
      // This ensures Grading Screen (Main) and Projector (Secondary) use IDENTICAL words/order.
      final result = await _vocabService.getWords(bookId,
          dayRange: rangeStr, shuffle: true);

      var testWords = result.cast<Map<String, dynamic>>();
      // Match limitation logic (e.g. max 30)
      if (testWords.length > 30) {
        testWords = testWords.sublist(0, 30);
      }

      // 2. Extract IDs for Projector URL
      final wordIdsParam = testWords.map((w) => w['id']).join(',');

      // 3. Construct Projector URL
      final uri = Uri(
        path: '/teacher/offline-test/projection',
        queryParameters: {
          'bookId': bookId.toString(),
          'studentId': studentId.toString(),
          'range': rangeStr,
          'duration': duration.toString(),
          'mode': _mode,
          'wordIds': wordIdsParam, // [NEW] Pass exact IDs order
        },
      );
      final fullPath = '/#${uri.toString()}';

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
          'words': testWords, // [IMPORTANT] Pass exact words
          'studentId': studentId,
          'bookId': bookId,
          'range': rangeStr,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('실행 실패: $e')));
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

  // [NEW] Range Controller
  final TextEditingController _rangeController =
      TextEditingController(text: '1-1');

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Book Selector (Autocomplete)
          const Text('교재 검색', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _isLoadingBooks
              ? const LinearProgressIndicator()
              : Autocomplete<Map<String, dynamic>>(
                  initialValue: _selectedBook != null
                      ? TextEditingValue(text: _selectedBook!['title'])
                      : null,
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                    return _availableBooks.where((book) {
                      return book['title']
                          .toString()
                          .toLowerCase()
                          .contains(textEditingValue.text.toLowerCase());
                    }).cast<Map<String, dynamic>>();
                  },
                  displayStringForOption: (option) => option['title'],
                  onSelected: _onBookSelected,
                  fieldViewBuilder: (context, textEditingController, focusNode,
                      onFieldSubmitted) {
                    return TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: '교재 제목 입력 (예: 어휘왕)',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      onSubmitted: (v) {
                        // Allow submit if user typed exact name?
                        // Autocomplete usually handles this via onSelected.
                      },
                    );
                  },
                ),

          const SizedBox(height: 24),

          if (_selectedBook != null) ...[
            // 2. Range Input (Text Field) [FIX]
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              keyboardType: TextInputType.datetime, // Numbers and symbols
            ),

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
                        onChanged: (v) => setState(() => _durationPerWord = v!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],

          const Spacer(),

          // Actions
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _step = 1), // Back
                child: const Text('이전'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: (_selectedBook == null || _isStarting)
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
                  // [FIX] Reduced padding for compactness
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
