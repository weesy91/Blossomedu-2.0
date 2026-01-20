import 'package:flutter/material.dart';
import '../../../core/services/vocab_service.dart';
import '../../../core/services/academy_service.dart';

class TeacherVocabEventManageScreen extends StatefulWidget {
  const TeacherVocabEventManageScreen({super.key});

  @override
  State<TeacherVocabEventManageScreen> createState() =>
      _TeacherVocabEventManageScreenState();
}

class _TeacherVocabEventManageScreenState
    extends State<TeacherVocabEventManageScreen> {
  final VocabService _vocabService = VocabService();
  final AcademyService _academyService = AcademyService(); // [NEW]
  bool _isLoading = true;
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _books = [];
  List<Map<String, dynamic>> _branches = []; // [NEW]

  bool _isEventCandidateBook(Map<String, dynamic> book) {
    final title = (book['title'] ?? '').toString().trim().toLowerCase();
    final publisher =
        (book['publisher_name'] ?? '').toString().trim().toLowerCase();
    if (title == '내 단어장') return false;
    if (title == 'wrong only') return false;
    if (publisher == '개인단어장') return false;
    if (publisher == 'system') return false;
    return true;
  }

  List<Map<String, dynamic>> _sortEvents(List<Map<String, dynamic>> events) {
    final sorted = List<Map<String, dynamic>>.from(events);
    sorted.sort((a, b) {
      final aDate = a['start_date']?.toString() ?? '';
      final bDate = b['start_date']?.toString() ?? '';
      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;
      final aId = a['id'] ?? 0;
      final bId = b['id'] ?? 0;
      return bId.compareTo(aId);
    });
    return sorted;
  }

  void _upsertEvent(Map<String, dynamic> event) {
    final next = List<Map<String, dynamic>>.from(_events);
    final idx = next.indexWhere((e) => e['id'] == event['id']);
    if (idx >= 0) {
      next[idx] = event;
    } else {
      next.add(event);
    }
    setState(() => _events = _sortEvents(next));
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final results = await Future.wait([
        _vocabService.getRankingEvents(),
        _vocabService.getVocabBooks(),
        _academyService.getBranches(), // [NEW]
      ]);
      final events =
          (results[0]).map((e) => Map<String, dynamic>.from(e)).toList();
      final books =
          (results[1]).map((e) => Map<String, dynamic>.from(e)).toList();
      final branches =
          (results[2]).map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {
        _events = _sortEvents(events);
        _books = books;
        _branches = branches; // [NEW]
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('이벤트 로딩 실패: $e')));
    }
  }

  Future<void> _openEventDialog({Map<String, dynamic>? event}) async {
    final titleController =
        TextEditingController(text: event?['title']?.toString() ?? '');
    int? selectedBookId = event?['target_book'] as int?;
    final availableBooks =
        _books.where(_isEventCandidateBook).toList(growable: false);
    if (selectedBookId != null &&
        !availableBooks.any((b) => b['id'] == selectedBookId)) {
      selectedBookId = null;
    }

    // [NEW] Branch Selection
    int? selectedBranchId = event?['branch'] as int?;
    // If Creating New, default to global (null) or user's branch?
    // Backend auto-sets creator's branch if null.
    // But now we allow EXPLICIT selection.
    // Let's default to null (Global) or leave as is.
    DateTime startDate =
        DateTime.tryParse(event?['start_date']?.toString() ?? '') ??
            DateTime.now();
    DateTime endDate =
        DateTime.tryParse(event?['end_date']?.toString() ?? '') ??
            DateTime.now().add(const Duration(days: 7));
    bool isActive = event?['is_active'] == true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(event == null ? '이벤트 단어장 추가' : '이벤트 단어장 수정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: '이벤트 제목'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedBookId,
                    items: availableBooks
                        .map((b) => DropdownMenuItem<int>(
                              value: b['id'] as int,
                              child: Text(b['title']?.toString() ?? ''),
                            ))
                        .toList(),
                    onChanged: (val) =>
                        setDialogState(() => selectedBookId = val),
                    decoration: const InputDecoration(labelText: '이벤트 단어장'),
                  ),
                  const SizedBox(height: 12),
                  // [NEW] Branch Selector
                  DropdownButtonFormField<int?>(
                    value: selectedBranchId,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('전체 지점 (본사)'),
                      ),
                      ..._branches.map((b) => DropdownMenuItem<int?>(
                            value: b['id'] as int,
                            child: Text(b['name']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedBranchId = val),
                    decoration: const InputDecoration(labelText: '적용 지점'),
                  ),
                  const SizedBox(height: 12),
                  _buildDateRow(
                    label: '시작일',
                    date: startDate,
                    onPick: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => startDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildDateRow(
                    label: '종료일',
                    date: endDate,
                    onPick: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => endDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (val) => setDialogState(() => isActive = val),
                    title: const Text('이벤트 진행 중'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty || selectedBookId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('제목과 단어장을 입력해주세요.')));
                    return;
                  }
                  if (endDate.isBefore(startDate)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('종료일은 시작일 이후여야 합니다.')));
                    return;
                  }

                  final payload = {
                    'title': title,
                    'target_book': selectedBookId,
                    'branch': selectedBranchId, // [NEW]
                    'start_date': startDate.toString().substring(0, 10),
                    'end_date': endDate.toString().substring(0, 10),
                    'is_active': isActive,
                  };

                  try {
                    final saved = event == null
                        ? await _vocabService.createRankingEvent(payload)
                        : await _vocabService.updateRankingEvent(
                            event['id'] as int, payload);
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    // Wait a bit for dialog to close before reloading
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (!mounted) return;
                    _upsertEvent(Map<String, dynamic>.from(saved));
                    await _loadData(showLoading: false);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(event == null
                            ? '이벤트가 생성되었습니다.'
                            : '이벤트가 수정되었습니다.')));
                  } catch (e) {
                    if (!mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
                  }
                },
                child: const Text('저장'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildDateRow(
      {required String label,
      required DateTime date,
      required VoidCallback onPick}) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        Expanded(
          child: OutlinedButton(
            onPressed: onPick,
            child: Text(date.toString().substring(0, 10)),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('이벤트 삭제'),
              content: const Text('정말로 이 이벤트를 삭제하시겠습니까?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('삭제'),
                ),
              ],
            ));

    if (confirm != true) return;
    try {
      await _vocabService.deleteRankingEvent(event['id'] as int);
      if (!mounted) return;
      setState(() {
        _events.removeWhere((e) => e['id'] == event['id']);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이벤트가 삭제되었습니다.')));
    } catch (e) {
      if (!mounted) return;
      // Even on error (like 404), refresh to sync with server state
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    } finally {
      // Always reload data to ensure UI matches server state
      if (mounted) {
        _loadData(showLoading: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('이벤트 단어장 관리'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEventDialog(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const Center(
                  child: Text('등록된 이벤트가 없습니다.',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  itemCount: _events.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    final title = event['title']?.toString() ?? '';
                    final bookTitle =
                        event['target_book_title']?.toString() ?? '';
                    final start = event['start_date']?.toString() ?? '';
                    final end = event['end_date']?.toString() ?? '';
                    final isActive = event['is_active'] == true;

                    return ListTile(
                      title: Text(title),
                      subtitle: Text('$bookTitle\n$start ~ $end'),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('진행 중',
                                  style: TextStyle(
                                      color: Colors.green, fontSize: 10)),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _openEventDialog(event: event),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            onPressed: () => _deleteEvent(event),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
