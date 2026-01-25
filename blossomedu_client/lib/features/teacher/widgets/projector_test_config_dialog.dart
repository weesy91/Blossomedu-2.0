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
          _publishers = results[1];
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

  Widget _buildStep2() {
    // Filter books by publisher
    final filteredBooks = _selectedPublisherId == null
        ? <dynamic>[]
        : _availableBooks.where((b) {
            // Check publisher field. Could be int ID or object depending on serializer.
            // Usually API returns ID or nested object.
            // Let's assume ID or check 'publisher.id' if object.
            // Safe check:
            final p = b['publisher'];
            if (p is int) return p == _selectedPublisherId;
            if (p is Map) return p['id'] == _selectedPublisherId;
            return false;
          }).toList();

    return Padding(
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
            const Text('출판사 선택', style: TextStyle(fontWeight: FontWeight.bold)),
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
            const Text('교재 선택', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedBook?['id'].toString(),
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              hint: Text(_selectedPublisherId == null
                  ? '출판사를 먼저 선택하세요'
                  : (filteredBooks.isEmpty ? '등록된 교재가 없습니다' : '교재를 선택하세요')),
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
              // Disable if no publisher or no books
              onTap: null, // Default
            ),

            const SizedBox(height: 24),

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
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text('학생이 이전에 틀린 단어들 중 최대 30문제를 무작위로 출제합니다.')),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

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
