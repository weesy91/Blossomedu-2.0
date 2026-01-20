import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
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
  final Set<int> _deletingEventIds = {};

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

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is Map) {
      final id = value['id'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id);
    }
    return null;
  }

  String? _formatDate(DateTime? date) {
    if (date == null) return null;
    return date.toIso8601String().substring(0, 10);
  }

  List<Map<String, dynamic>> _sortEvents(List<Map<String, dynamic>> events) {
    final deduped = <Map<String, dynamic>>[];
    final seenIds = <dynamic>{};
    for (final event in events) {
      final id = _asInt(event['id']) ?? event['id'];
      if (id == null || seenIds.add(id)) {
        deduped.add(event);
      }
    }
    deduped.sort((a, b) {
      final aDate = a['start_date']?.toString() ?? '';
      final bDate = b['start_date']?.toString() ?? '';
      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;
      final aId = _asInt(a['id']) ?? 0;
      final bId = _asInt(b['id']) ?? 0;
      return bId.compareTo(aId);
    });
    return deduped;
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
    List<Map<String, dynamic>>? events;
    try {
      final rawEvents = await _vocabService.getRankingEvents();
      events = rawEvents.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이벤트 로드 실패: $e')),
        );
      }
    }

    if (!mounted) return;
    if (events != null) {
      setState(() {
        _events = _sortEvents(events!);
      });
    }

    try {
      final rawBooks = await _vocabService.getVocabBooks();
      if (mounted) {
        setState(() {
          _books = rawBooks.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Event books load failed: $e');
    }

    try {
      final rawBranches = await _academyService.getBranches(); // [NEW]
      if (mounted) {
        setState(() {
          _branches =
              rawBranches.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Event branches load failed: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openEventDialog({Map<String, dynamic>? event}) async {
    final titleController =
        TextEditingController(text: event?['title']?.toString() ?? '');
    int? selectedBookId = _asInt(event?['target_book']);
    selectedBookId ??= _asInt(event?['target_book_id']);
    final availableBooks = <Map<String, dynamic>>[];
    final seenBookIds = <int>{};
    for (final book in _books.where(_isEventCandidateBook)) {
      final id = _asInt(book['id']);
      if (id == null || !seenBookIds.add(id)) continue;
      availableBooks.add(book);
    }

    // [NEW] Branch Selection
    int? selectedBranchId = _asInt(event?['branch']);
    selectedBranchId ??= _asInt(event?['branch_id']);
    final availableBranches = <Map<String, dynamic>>[];
    final seenBranchIds = <int>{};
    for (final branch in _branches) {
      final id = _asInt(branch['id']);
      if (id == null || !seenBranchIds.add(id)) continue;
      availableBranches.add(branch);
    }
    // If Creating New, default to global (null) or user's branch?
    // Backend auto-sets creator's branch if null.
    // But now we allow EXPLICIT selection.
    // Let's default to null (Global) or leave as is.
    DateTime? startDate =
        DateTime.tryParse(event?['start_date']?.toString() ?? '') ??
            DateTime.now();
    DateTime? endDate =
        DateTime.tryParse(event?['end_date']?.toString() ?? '') ??
            DateTime.now().add(const Duration(days: 7));
    bool isActive = event?['is_active'] == true;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          final selectedBookValue = selectedBookId != null &&
                  availableBooks.any((b) => _asInt(b['id']) == selectedBookId)
              ? selectedBookId
              : null;
          final selectedBranchValue = selectedBranchId != null &&
                  availableBranches
                      .any((b) => _asInt(b['id']) == selectedBranchId)
              ? selectedBranchId
              : null;
          return AlertDialog(
            title: Text(event == null ? '이벤트 단어장 추가' : '이벤트 단어장 수정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    enabled: !isSaving,
                    decoration: const InputDecoration(labelText: '이벤트 제목'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: selectedBookValue,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('선택'),
                      ),
                      ...availableBooks.map((b) {
                        final id = _asInt(b['id'])!;
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(b['title']?.toString() ?? ''),
                        );
                      })
                    ],
                    onChanged: isSaving
                        ? null
                        : (val) => setDialogState(() => selectedBookId = val),
                    decoration: const InputDecoration(labelText: '이벤트 단어장'),
                  ),
                  const SizedBox(height: 12),
                  // [NEW] Branch Selector
                  DropdownButtonFormField<int?>(
                    value: selectedBranchValue,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('전체 지점 (본사)'),
                      ),
                      ...availableBranches.map((b) {
                        final id = _asInt(b['id'])!;
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(b['name']?.toString() ?? ''),
                        );
                      }),
                    ],
                    onChanged: isSaving
                        ? null
                        : (val) => setDialogState(() => selectedBranchId = val),
                    decoration: const InputDecoration(labelText: '적용 지점'),
                  ),
                  const SizedBox(height: 12),
                  _buildDateRow(
                    label: '시작일',
                    date: startDate,
                    onPick: () async {
                      if (isSaving) return;
                      final baseDate = startDate ?? DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: baseDate,
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
                      if (isSaving) return;
                      final baseDate = endDate ?? DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: baseDate,
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
                    onChanged: isSaving
                        ? null
                        : (val) => setDialogState(() => isActive = val),
                    title: const Text('이벤트 진행 중'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : () async {
                  final title = titleController.text.trim();
                  if (title.isEmpty || selectedBookId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('제목과 단어장을 입력해주세요.')));
                    return;
                  }
                  if (startDate == null || endDate == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('시작일과 종료일을 확인해주세요.')));
                    return;
                  }
                  final start = startDate!;
                  final end = endDate!;
                  if (end.isBefore(start)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('종료일은 시작일 이후여야 합니다.')));
                    return;
                  }

                  final startDateStr = _formatDate(start);
                  final endDateStr = _formatDate(end);
                  if (startDateStr == null || endDateStr == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('시작일과 종료일을 확인해주세요.')));
                    return;
                  }

                  final payload = {
                    'title': title,
                    'target_book': selectedBookId,
                    'branch': selectedBranchId, // [NEW]
                    'start_date': startDateStr,
                    'end_date': endDateStr,
                    'is_active': isActive,
                  };

                  final eventId = event == null ? null : _asInt(event['id']);
                  if (event != null && eventId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('이벤트 ID를 확인할 수 없습니다.')));
                    return;
                  }

                  setDialogState(() => isSaving = true);

                  try {
                    final saved = event == null
                        ? await _vocabService.createRankingEvent(payload)
                        : await _vocabService.updateRankingEvent(
                            eventId!, payload);
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
      required DateTime? date,
      required VoidCallback onPick}) {
    final dateText = _formatDate(date) ?? '-';
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label)),
        Expanded(
          child: OutlinedButton(
            onPressed: onPick,
            child: Text(dateText),
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
              content: const Text('이 이벤트를 삭제하시겠습니까?'),
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
    final eventId = _asInt(event['id']);
    if (eventId == null) return;
    if (_deletingEventIds.contains(eventId)) return;
    setState(() => _deletingEventIds.add(eventId));
    try {
      await _vocabService.deleteRankingEvent(eventId);
      if (!mounted) return;
      setState(() {
        _events.removeWhere((e) =>
            _asInt(e['id']) == eventId || e['id'] == event['id']);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이벤트가 삭제되었습니다.')));
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 404) {
        setState(() {
          _events.removeWhere((item) =>
              _asInt(item['id']) == eventId || item['id'] == event['id']);
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미 삭제된 이벤트입니다.')));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
    } finally {
      if (mounted) {
        setState(() => _deletingEventIds.remove(eventId));
      }
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
                    final eventId = _asInt(event['id']);
                    final isDeleting = eventId != null &&
                        _deletingEventIds.contains(eventId);
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
                            onPressed:
                                isDeleting ? null : () => _openEventDialog(event: event),
                          ),
                          IconButton(
                            icon: isDeleting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.delete, size: 18),
                            onPressed: isDeleting ? null : () => _deleteEvent(event),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
