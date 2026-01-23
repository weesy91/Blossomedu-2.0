import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/services/academy_service.dart';

class TeacherClassLogCreateScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String subject; // 'SYNTAX' or 'READING'

  const TeacherClassLogCreateScreen({
    required this.studentId,
    required this.studentName,
    this.subject = 'SYNTAX',
    this.date, // [NEW]
    super.key,
  });

  final String? date; // [NEW]

  @override
  State<TeacherClassLogCreateScreen> createState() =>
      _TeacherClassLogCreateScreenState();
}

class _TeacherClassLogCreateScreenState
    extends State<TeacherClassLogCreateScreen> {
  final AcademyService _academyService = AcademyService();
  bool _isLoading = true;
  bool _isSaving = false;

  List<Map<String, dynamic>> _allBooks = [];

  // 1. Past Info
  Map<String, dynamic>? _prevMyLog;
  Map<String, dynamic>? _prevOtherLog;
  int? _editingLogId;
  final Set<String> _extraVocabPublishers = {};

  // Default Due Date used for initialization
  final DateTime _defaultDueDate = () {
    final now = DateTime.now().add(const Duration(days: 7));
    return DateTime(now.year, now.month, now.day, 22, 0); // Default 10 PM
  }();

  final TextEditingController _commentController = TextEditingController();

  // Rows Data Structure:
  // {
  //   'type': String?,
  //   'publisher': String?,
  //   'bookId': int?,
  //   'range': String,
  //   'score': String (optional),
  //   'startUnit': int?,
  //   'endUnit': int?,
  //   'dueDate': DateTime // [NEW] Individual Due Date
  // }
  final List<Map<String, dynamic>> _teachingRows = [];
  final List<Map<String, dynamic>> _hwVocabRows = [];

  final List<Map<String, dynamic>> _hwMainRows = [];
  final Set<int> _deletedAssignmentIds = {}; // [NEW] Track deleted assignments

  // [REDESIGNED] 과제 목록 방식 - 자유 추가/삭제 가능
  // 각 항목: {'isWrongWords': bool, 'dueDate': DateTime, 'publisher': String?,
  //           'bookId': int?, 'range': String, 'wrongWordsCount': int}
  final List<Map<String, dynamic>> _vocabAssignments = [];

  final Map<String, String> _typeLabels = {
    'VOCAB': '단어',
    'SYNTAX': '구문',
    'READING': '독해',
    'GRAMMAR': '어법',
    'LISTENING': '듣기',
    'SCHOOL_EXAM': '내신',
  };

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    // [NEW] Check Attendance Status
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAttendanceStatus();
    });
  }

  Future<void> _fetchInitialData() async {
    try {
      // Use Real API
      // Note: getTextbooks returns books. Vocab books might not be in Textbooks API based on previous plan.
      // But user wants to connect backend.
      // API `getTextbooks` returns `Textbook` model. `WordBook` is different.
      // For now, let's fetch Textbooks. Vocab might be missing if not in Textbook model.
      // If Vocab is missing, we might need to fetch separately or just mock Vocab for now?
      // User Logic: "Book Metadata Management" covered Textbooks. Vocab was separate.
      // I'll fetch Textbooks. For Vocab, I'll Mock or Leave Empty for now (or fetch if API exists).
      // Assuming WordBook API isn't ready or different.
      // I'll filter _allBooks based on Category.

      final textbooks = await _academyService.getTextbooks();
      final mappedBooks = textbooks.map((b) {
        return {
          ...b,
          'type': b['category'],
          'has_ot': b['has_ot'] ?? false, // [NEW]
        };
      }).toList();

      try {
        final vocabBooks = await _academyService.getVocabBooks();
        final mappedVocab = vocabBooks.map((b) {
          return {
            'id': b['id'],
            'title': b['title'] ?? '',
            'publisher': b['publisher_name'],
            'type': 'VOCAB',
            'units': [],
            'has_ot': false,
          };
        }).toList();
        mappedBooks.addAll(mappedVocab);
      } catch (_) {
        // Ignore vocab load failures and continue with fallback/mock data.
      }

      // [FIX] Restore Mock Vocab Books if none exist (for testing)
      if (!mappedBooks.any((b) => b['type'] == 'VOCAB')) {
        mappedBooks.addAll([
          {
            'id': 901,
            'title': '수능 영단어 2000',
            'publisher': '능률',
            'type': 'VOCAB',
            'units': [],
            'has_ot': false,
            'description': '',
          },
          {
            'id': 902,
            'title': '워드마스터 고등',
            'publisher': '이투스',
            'type': 'VOCAB',
            'units': [],
            'has_ot': false,
            'description': '',
          },
        ]);
      }

      // [FIX] Add Mock SYNTAX/READING Books if none exist (to prevent empty dropdowns)
      if (!mappedBooks.any((b) => b['type'] == 'SYNTAX')) {
        mappedBooks.add({
          'id': 801,
          'title': '천일문 기본',
          'publisher': '쎄듀',
          'type': 'SYNTAX',
          'units': [],
          'has_ot': true
        });
      }
      if (!mappedBooks.any((b) => b['type'] == 'READING')) {
        mappedBooks.add({
          'id': 701,
          'title': '자이스토리 독해',
          'publisher': '수경',
          'type': 'READING',
          'units': [],
          'has_ot': true,
          'description': '',
        });
      }

      // [FIX] Declare log list variables outside try-catch scope
      List<dynamic> targetLogList = [];
      List<dynamic> historyLogs = [];
      List<dynamic> otherLogs = [];

      // Set _allBooks here so it's available even if log fetching fails
      _allBooks = _dedupeBooks(mappedBooks);

      // Fetch Real Logs
      try {
        // 1. Fetch Target Log (for editing)
        if (widget.date != null) {
          targetLogList = await _academyService.getClassLogs(
              studentId: int.parse(widget.studentId),
              subject: widget.subject,
              date: widget.date);
        }

        // 2. Fetch History (for "Previous HW" context)
        // We fetch ALL to find the one right before the target date
        historyLogs = await _academyService.getClassLogs(
            studentId: int.parse(widget.studentId), subject: widget.subject);

        // 3. Fetch Other Subject Logs (for "Cross-check")
        final otherSubject = widget.subject == 'SYNTAX' ? 'READING' : 'SYNTAX';
        otherLogs = await _academyService.getClassLogs(
            studentId: int.parse(widget.studentId), subject: otherSubject);

        // 4. Fetch Student Schedule for Regular/Makeup Distinction
        try {
          final studentData =
              await _academyService.getStudent(int.parse(widget.studentId));
          _studentSchedule = studentData['class_times'] ?? [];
        } catch (e) {
          print('Error fetching student details: $e');
        }
      } catch (e) {
        print('Log fetch failed: $e');
        // Continue even if log fetch fails, just with empty log data
      }

      if (targetLogList.isNotEmpty) {
        final existing = targetLogList.first;

        if (existing != null) {
          // [POPULATE FORM]
          _editingLogId = existing['id'];
          _commentController.text = existing['comment'] ?? '';

          final entries = existing['entries'] as List?;
          if (entries != null && entries.isNotEmpty) {
            _teachingRows.clear();
            for (final entry in entries) {
              if (entry is! Map) continue;
              final textbookId = entry['textbook'];
              final wordbookId = entry['wordbook'];
              String? type;
              String? publisher;
              int? bookId;

              if (wordbookId != null) {
                type = 'VOCAB';
                bookId = wordbookId;
                final book = _findBook(bookId, type: 'VOCAB');
                if (book != null) {
                  publisher =
                      _normalizePublisher(book['publisher']?.toString());
                }
              } else if (textbookId != null) {
                bookId = textbookId;
                final book = _findBook(bookId);
                if (book != null) {
                  type = book['type'];
                }
              }

              _teachingRows.add({
                'type': type,
                'publisher': publisher,
                'bookId': bookId,
                'range': entry['progress_range'] ?? '',
                'score': entry['score'] ?? 'B',
                'isOt': false,
              });
            }
          }

          // [FIX] Populate Assignments using 'generated_assignments' (read-only field)
          final assignments = existing['generated_assignments'] as List? ?? [];
          print('Existing Log Assignments: ${assignments.length}');

          // [SYNC FIX] Even if Log exists, fetch "Pending Assignments" from server to see newly added ones
          if (widget.date != null) {
            try {
              final extraAndPending = await _academyService.getAssignments(
                  studentId: int.parse(widget.studentId));

              if (extraAndPending.isNotEmpty) {
                final classDate = DateTime.parse(widget.date!);
                // Filter: Assignments due ON or AFTER this class date
                final relevant = extraAndPending.where((asm) {
                  // [FIX] Cross-Subject Filtering
                  // If assignment belongs to another subject log, SKIP it.
                  final originSub = asm['origin_log_subject'];
                  if (originSub != null && originSub != widget.subject) {
                    return false;
                  }

                  final dStr = asm['due_date'];
                  if (dStr == null) return false;
                  final d = DateTime.tryParse(dStr);
                  if (d == null) return false;
                  final dDate = DateTime(d.year, d.month, d.day);
                  final cDate =
                      DateTime(classDate.year, classDate.month, classDate.day);
                  return !dDate.isBefore(cDate);
                }).toList();

                // MERGE: Add relevant pending assignments if not already in 'assignments'
                // We check by ID to avoid duplicates
                final existingIds = assignments.map((a) => a['id']).toSet();
                for (var r in relevant) {
                  if (!existingIds.contains(r['id'])) {
                    // Mark as "New" or just add (Backend handles linking on save ideally, or we treat them as Manual for now?)
                    // If it's a real AssignmentTask object from API, it matches the structure.
                    assignments.add(r);
                  }
                }
              }
            } catch (e) {
              print('Sync Pending Assignments Error: $e');
            }
          }

          if (assignments.isNotEmpty) {
            _populateAssignments(assignments);
          }
        }
      } else {
        // [NEW Log Mode]
        if (widget.date != null) {
          try {
            // ... same logic for new log ...
            final extraAndPending = await _academyService.getAssignments(
                studentId: int.parse(widget.studentId));

            if (extraAndPending.isNotEmpty) {
              final classDate = DateTime.parse(widget.date!);
              // Filter: Assignments due ON or AFTER this class date
              final relevant = extraAndPending.where((asm) {
                // [FIX] Cross-Subject Filtering
                final originSub = asm['origin_log_subject'];
                if (originSub != null && originSub != widget.subject) {
                  return false;
                }

                final dStr = asm['due_date'];
                if (dStr == null) return false;
                final d = DateTime.tryParse(dStr);
                if (d == null) return false;
                // Compare YMD
                final dDate = DateTime(d.year, d.month, d.day);
                final cDate =
                    DateTime(classDate.year, classDate.month, classDate.day);
                return !dDate.isBefore(cDate);
              }).toList();

              if (relevant.isNotEmpty) {
                _populateAssignments(relevant);
              }
            }
          } catch (e) {
            print('Pending assignment fetch error: $e');
          }
        }
      }

      // Normalize publisher values before build.
      final vocabPublishers = _getPublishersForType('VOCAB');
      for (final row in _hwVocabRows) {
        final current = _normalizePublisher(row['publisher']?.toString());
        if (current.isEmpty) {
          row['publisher'] = null;
          row['bookId'] = null;
        } else {
          row['publisher'] = current;
          if (!vocabPublishers.contains(current)) {
            _extraVocabPublishers.add(current);
          }
        }
      }

      setState(() {
        _allBooks = _dedupeBooks(mappedBooks);
        _isLoading = false;

        // Init Empty Rows if empty
        if (_teachingRows.isEmpty) {
          _teachingRows.add({
            'type': null,
            'publisher': null,
            'bookId': null,
            'range': '',
            'score': 'B',
            'isOt': false
          });
        }
        if (_hwVocabRows.isEmpty) {
          _hwVocabRows.add({
            'type': 'VOCAB',
            'range': '',
            'isOt': false,
            'dueDate': _defaultDueDate
          });
        }
        if (_hwMainRows.isEmpty) {
          _hwMainRows.add({
            'type': null,
            'range': '',
            'isOt': false,
            'dueDate': _defaultDueDate
          });
        }

        final targetDateStr =
            widget.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

        // Real Past Info (My Log - Aggregation)
        if (historyLogs.isNotEmpty) {
          // Filter strictly for logs BEFORE the target date and sort DESC
          final pastLogs = historyLogs.where((l) {
            final d = l['date'];
            return d != null && d.compareTo(targetDateStr) < 0;
          }).toList()
            ..sort((a, b) => b['date'].compareTo(a['date'])); // ensure desc

          if (pastLogs.isNotEmpty) {
            final aggregated = _aggregatePastAssignments(pastLogs);
            if (aggregated.isNotEmpty) {
              _prevMyLog = {
                'date': aggregated['lastRegularDate'],
                'hw': '', // Not used for display, assignments are used
                'assignments': aggregated['assignments'],
              };
            }
          }
        }

        if (otherLogs.isNotEmpty) {
          // Real Past Info (Cross Log - Single)
          final pastOtherLogs = otherLogs.where((l) {
            final d = l['date'];
            return d != null && d.compareTo(targetDateStr) < 0;
          }).toList()
            ..sort((a, b) => b['date'].compareTo(a['date']));

          if (pastOtherLogs.isNotEmpty) {
            final last = pastOtherLogs.first;

            // Construct Summary Content
            final parts = <String>[];
            final comment = last['comment'];
            if (comment != null && comment.toString().trim().isNotEmpty) {
              parts.add('[T] $comment'); // Teacher Comment
            }

            final entries = last['entries'] as List?;
            if (entries != null) {
              for (var e in entries) {
                final txt = e['textbook_title'] ?? e['wordbook_title'] ?? '';
                final rng = e['progress_range'] ?? '';
                final scr = e['score'] ?? '';
                if (txt.isNotEmpty) {
                  parts.add('• $txt $rng ($scr)');
                }
              }
            }

            _prevOtherLog = {
              'date': last['date'],
              'content': parts.isNotEmpty ? parts.join('\n') : '내용 없음'
            };
          }
        }
      });
    } catch (e) {
      print('Error fetching data: $e');
      setState(() {
        _isLoading = false;
        // Ensure rows exist
        if (_teachingRows.isEmpty) {
          _teachingRows
              .add({'type': null, 'score': 'B', 'range': '', 'isOt': false});
        }
        if (_hwVocabRows.isEmpty) {
          _hwVocabRows.add({
            'type': 'VOCAB',
            'range': '',
            'isOt': false,
            'dueDate': _defaultDueDate
          });
        }
        if (_hwMainRows.isEmpty) {
          _hwMainRows.add({
            'type': null,
            'range': '',
            'isOt': false,
            'dueDate': _defaultDueDate
          });
        }
      });
    }
  }

  Future<void> _submitLog() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      // 1. Construct Payload
      // This sample only saves the MAIN HOMEWORK as ClassLog fields.
      // Complex data (multiple rows) should be saved as entries or separate AssignmentTasks.
      // For Phase 2, we map the first valid HW row to ClassLog fields.

      // 3. Construct Assignments List
      List<Map<String, dynamic>> assignments = [];

      // [SYNC FIX] Explicitly delete "Adopted" assignments and "Deleted" assignments
      // to prevent duplicates (since backend recreates them) and ensure removals persist.
      final Set<int> idsToDelete = {..._deletedAssignmentIds};

      // Add currently displayed assignments to delete list (if they have IDs)
      // because we are about to RE-CREATE them as children of this log.
      for (var row in _hwMainRows) {
        final hasSubmission = row['submissionStatus'] != null;
        final isCompleted = row['isCompleted'] == true;
        if (row['id'] != null && !hasSubmission && !isCompleted) {
          idsToDelete.add(row['id']);
        }
      }
      for (var row in _vocabAssignments) {
        final hasSubmission = row['submissionStatus'] != null;
        final isCompleted = row['isCompleted'] == true;
        if (row['id'] != null && !hasSubmission && !isCompleted) {
          idsToDelete.add(row['id']);
        }
      }

      // Execute Deletions
      for (final id in idsToDelete) {
        try {
          // Check if it's a valid ID (>0)
          if (id > 0) {
            print('Deleting assignment $id before saving log...');
            await _academyService.deleteAssignment(id);
          }
        } catch (e) {
          print('Error deleting assignment $id: $e');
        }
      }

      // Process Main Rows
      for (var row in _hwMainRows) {
        // [FIX] Skip completed/submitted assignments - they are preserved by backend
        final hasSubmission = row['submissionStatus'] != null;
        final isCompleted = row['isCompleted'] == true;
        if (hasSubmission || isCompleted) {
          continue; // Don't re-add, backend keeps these
        }

        if (row['bookId'] != null) {
          String title = '';
          if (row['startUnit'] != null && row['endUnit'] != null) {
            title = '${row['startUnit']}강 ~ ${row['endUnit']}강';
          } else {
            title = row['range'] ?? '과제';
          }

          final book = _findBook(row['bookId'], type: row['type']?.toString());
          if (book != null) {
            title = '[${book['title']}] $title';
          }

          assignments.add({
            if (row['id'] != null) 'id': row['id'],
            'title': title,
            'assignment_type': 'MANUAL', // Type A
            'due_date': row['dueDate']?.toIso8601String() ??
                _defaultDueDate.toIso8601String(),
            'description': row['description'] ?? '',
            // [FIX] Support Textbook Links
            'related_textbook': row['bookId'],
            // [FIX] Save startUnit/endUnit as textbook_range if available
            'textbook_range':
                (row['startUnit'] != null && row['endUnit'] != null)
                    ? '${row['startUnit']}-${row['endUnit']}'
                    : (row['range'] ?? ''),
          });
        }
      }

      // [DEPRECATED] Legacy Vocab Rows logic removed to prevent ghost assignments
      // _hwVocabRows are no longer used in UI, but were causing invisible assignments to be saved.

      // [REDESIGNED] 과제 목록 방식으로 처리
      for (var assignment in _vocabAssignments) {
        // [FIX] Skip completed/submitted assignments - they are preserved by backend
        final hasSubmission = assignment['submissionStatus'] != null;
        final isCompleted = assignment['isCompleted'] == true;
        if (hasSubmission || isCompleted) {
          continue; // Don't re-add, backend keeps these
        }

        final isWrongWords = assignment['isWrongWords'] ?? false;
        final dueDate = assignment['dueDate'] as DateTime? ?? _defaultDueDate;

        if (isWrongWords) {
          // 오답 단어장 과제
          final count = assignment['wrongWordsCount'] ?? 30;
          assignments.add({
            if (assignment['id'] != null) 'id': assignment['id'],
            'title': '🔥 오답 단어 복습 ($count개)',
            'assignment_type': 'VOCAB_TEST',
            'due_date': dueDate.toIso8601String(),
            'related_vocab_book': null,
            'vocab_range_start': 0,
            'vocab_range_end': count,
            'is_cumulative': true, // [FIX] 오답 과제는 항상 누적=true
          });
        } else {
          // 일반 단어장 과제
          final bookId = assignment['bookId'];
          String range =
              assignment['range']?.toString().trim() ?? ''; // [FIX] Mutable
          if (bookId == null || range.isEmpty) continue;

          // [FIX] Sanitize "Day Day" or "암기 암기"
          // Case 1: "Day Day" -> "Day"
          range = range.replaceAll(
              RegExp(r'(Day\s*){2,}', caseSensitive: false), 'Day ');
          // Case 2: "암기 암기" -> "암기"
          range = range.replaceAll(RegExp(r'(암기\s*){2,}'), '암기');
          // Case 3: Trim spaces
          range = range.replaceAll(RegExp(r'\s+'), ' ').trim();

          int? rangeStart;
          int? rangeEnd;
          // [FIX] Support single number ("10") or range ("10-12")
          final match = RegExp(r'^(\d+)(\s*-\s*(\d+))?$').firstMatch(range);
          if (match != null) {
            final first = int.tryParse(match.group(1) ?? '');
            final second = int.tryParse(match.group(3) ?? '');
            if (first != null) {
              rangeStart = first;
              rangeEnd = second ??
                  first; // If "10", treat as 10-10 so test can be generated?
              // Or if user meant "Day 10", it usually means chapter 10.
            }
          }

          final selectedBook = _findBook(bookId, type: 'VOCAB');
          final bookTitle = selectedBook?['title'] ?? '단어 과제';

          assignments.add({
            if (assignment['id'] != null) 'id': assignment['id'],
            'title':
                '[$bookTitle] $range', // [FIX] Remove "Day... 암기" to avoid duplication
            'assignment_type': 'VOCAB_TEST',
            'due_date': dueDate.toIso8601String(),
            'related_vocab_book': bookId,
            if (rangeStart != null) 'vocab_range_start': rangeStart,
            if (rangeEnd != null) 'vocab_range_end': rangeEnd,
            'is_cumulative': false,
          });
        }
      }

      final payload = {
        'student': int.tryParse(widget.studentId),
        'subject': widget.subject,
        'date': widget.date ??
            DateFormat('yyyy-MM-dd')
                .format(DateTime.now()), // [FIX] Use selected date
        'comment': _commentController.text,
        // Legacy Fields (Optional, or empty)
        'hw_due_date': _defaultDueDate.toIso8601String(),
        'assignments': assignments, // [NEW] List
        'entries_input': _teachingRows
            .where((row) => row['bookId'] != null && row['range'] != null)
            .map((row) {
          final isVocab = row['type'] == 'VOCAB';
          return {
            if (isVocab) 'wordbook': row['bookId'],
            if (!isVocab) 'textbook': row['bookId'],
            'progress_range': row['range'],
            'score': row['score'] ?? '',
          };
        }).toList(),
      };

      if (_editingLogId != null) {
        await _academyService.updateClassLog(_editingLogId!, payload);
      } else {
        await _academyService.createClassLog(payload);
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('수업 일지 저장 완료! 🚀')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // --- Helper Methods ---

  List<String> _getAvailableTypes({List<String>? allowedTypes}) {
    if (allowedTypes != null) return allowedTypes;
    return [
      'VOCAB',
      'SYNTAX',
      'READING',
      'GRAMMAR',
      'LISTENING',
      'SCHOOL_EXAM'
    ];
  }

  List<String> _getPublishersForType(String type) {
    final books = _allBooks.where((b) => b['type'] == type).toList();
    final unique = <String, String>{};
    for (final book in books) {
      final raw = book['publisher'];
      final normalized = _normalizePublisher(raw?.toString());
      if (normalized.isEmpty) continue;
      unique.putIfAbsent(normalized, () => normalized);
    }
    if (type == 'VOCAB' && _extraVocabPublishers.isNotEmpty) {
      for (final extra in _extraVocabPublishers) {
        if (extra.isEmpty) continue;
        unique.putIfAbsent(extra, () => extra);
      }
    }
    return unique.values.toList();
  }

  List<Map<String, dynamic>> _getBooksFiltered(
      String? type, String? publisher) {
    if (type == null) return [];
    final filtered = _allBooks.where((b) {
      if (b['type'] != type) return false;
      // Only filter by publisher if type is VOCAB and publisher is selected
      if (type == 'VOCAB' && publisher != null) {
        final bookPublisher = _normalizePublisher(b['publisher']?.toString());
        final selectedPublisher = _normalizePublisher(publisher.toString());
        return bookPublisher == selectedPublisher;
      }
      return true;
    }).toList();
    return _dedupeBooks(filtered);
  }

  List<Map<String, dynamic>> _dedupeBooks(List<Map<String, dynamic>> books) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final book in books) {
      final id = book['id'];
      final type = book['type'];
      final key = '${type ?? ''}#${id ?? ''}';
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(book);
    }
    return result;
  }

  String _normalizePublisher(String? value) {
    if (value == null) return '';
    return value.trim();
  }

  // Find book by ID (optionally scoped by type to avoid ID collisions)
  Map<String, dynamic>? _findBook(int? id, {String? type}) {
    if (id == null) return null;
    try {
      final matches = _allBooks.where((b) => b['id'] == id).toList();
      if (matches.isEmpty) return null;
      if (type != null && type.isNotEmpty) {
        final targetType = type.toUpperCase();
        for (final b in matches) {
          final bType = (b['type']?.toString() ?? '').toUpperCase();
          if (bType == targetType) return b;
        }
      }
      if (matches.length == 1) return matches.first;
      for (final b in matches) {
        if ((b['type']?.toString() ?? '').toUpperCase() != 'VOCAB') {
          return b;
        }
      }
      return matches.first;
    } catch (_) {
      return null;
    }
  }

  // State variables
  List<dynamic> _studentSchedule = []; // [NEW] For Regular/Makeup Check

  // Helper: Check if a date corresponds to a "Regular Class" day
  bool _isRegularClass(String dateStr) {
    if (_studentSchedule.isEmpty) {
      return true; // Default to Regular if unknown? Or Makeup? Let's assume Regular to include everything if no schedule.
    }
    try {
      final date = DateTime.parse(dateStr);
      // Weekday: 1=Mon, ..., 7=Sun
      // Backend 'class_times' format expected: List of objects or strings?
      // Based on typical Blossomedu: [{'day': 'Mon', 'subject': 'SYNTAX'}, ...]
      // OR ['Mon', 'Tue']?
      // Need to check getStudent response structure.
      // Based on previous view of academy_service.dart:
      // 'class_times': s['class_times'] ?? [],

      // Let's assume it matches the day of week.
      // DateFormat('E').format(date) -> "Mon", "Tue"
      final dayStr = DateFormat('E').format(date); // "Mon", "Tue"...

      // Check if ANY schedule entry matches this day AND subject
      // class_times entries usually have 'day' and 'subject'
      return _studentSchedule.any((s) {
        if (s is Map) {
          final sDay = s['day']; // 'Mon'
          final sSub = s['subject']; // 'SYNTAX'
          return sDay == dayStr && sSub == widget.subject;
        }
        return false;
      });
    } catch (_) {
      return false;
    }
  }

  // Helper: Aggregate assignments from Last Regular Class + Makeups
  Map<String, dynamic> _aggregatePastAssignments(List<dynamic> historyLogs) {
    // historyLogs is sorted DESC (newest first)
    // Find the INDEX of the most recent "Regular Class"
    int? lastRegularIndex;

    for (int i = 0; i < historyLogs.length; i++) {
      final log = historyLogs[i];
      if (_isRegularClass(log['date'])) {
        lastRegularIndex = i;
        break;
      }
    }

    if (lastRegularIndex == null) return {};

    // Collect logs from 0 to lastRegularIndex (Inclusive)
    // These are: [Recent Makeup, ..., Recent Makeup, Last Regular]
    // Since historyLogs is DESC, taking 0..lastRegularIndex gives us the target range.
    final targetLogs = historyLogs.sublist(0, lastRegularIndex + 1);

    // We want to display assignments from ALL these logs.
    List<Map<String, dynamic>> allAssignments = [];

    for (final log in targetLogs) {
      final generated = log['generated_assignments'] as List? ?? [];
      for (final asm in generated) {
        if (asm is Map) {
          allAssignments.add(Map<String, dynamic>.from(asm));
        }
      }

      // Also check if legacy 'hw_main_range' exists and convert to simpler display if generated is empty?
      // But the requirement specifically asked for aggregation.
      // If legacy log has no generated_assignments, we might miss it.
      // For now, assume modern logs.
    }

    if (allAssignments.isEmpty) return {};

    return {
      'lastRegularDate': historyLogs[lastRegularIndex]['date'],
      'assignments': allAssignments,
    };
  }

  /// [NEW] Parse numeric range from various formats
  /// Supports: "1-10", "1~10", "Day 1-10", "1강-3강", "1", etc.
  (int?, int?) _parseRange(String? rangeStr) {
    if (rangeStr == null || rangeStr.isEmpty) return (null, null);

    // Extract all numbers from the string
    final numbers = RegExp(r'\d+')
        .allMatches(rangeStr)
        .map((m) => int.parse(m.group(0)!))
        .toList();

    if (numbers.isEmpty) return (null, null);
    if (numbers.length == 1) return (numbers[0], numbers[0]);

    // Take first and last numbers as range
    return (numbers.first, numbers.last);
  }

  /// [NEW] Merge assignment ranges by book for convenient auto-fill
  /// Groups assignments by bookId/title and merges ranges to min~max
  Map<String, Map<String, dynamic>> _mergeAssignmentRanges(
      List<dynamic> assignments) {
    // Structure: { 'bookKey': { 'bookId': id, 'title': title, 'type': type, 'minRange': min, 'maxRange': max } }
    final Map<String, Map<String, dynamic>> merged = {};

    for (final asm in assignments) {
      if (asm is! Map) continue;

      // Try to identify book by related_textbook, related_vocab_book, or title
      final textbookId = asm['related_textbook'];
      final vocabBookId = asm['related_vocab_book'];
      final title = asm['title']?.toString() ?? '';

      String bookKey;
      String bookType;
      int? bookId;
      String displayTitle = title;

      if (vocabBookId != null) {
        bookKey = 'VOCAB_$vocabBookId';
        bookType = 'VOCAB';
        bookId = vocabBookId;
        // Extract book title from assignment title (e.g., "[단어장명] Day 1-10" → "단어장명")
        final match = RegExp(r'\[(.+?)\]').firstMatch(title);
        if (match != null) displayTitle = match.group(1) ?? title;
      } else if (textbookId != null) {
        bookKey = 'TEXTBOOK_$textbookId';
        bookType = 'TEXTBOOK';
        bookId = textbookId;
        final match = RegExp(r'\[(.+?)\]').firstMatch(title);
        if (match != null) displayTitle = match.group(1) ?? title;
      } else {
        // Fallback: use title as key
        bookKey = 'TITLE_$title';
        bookType = 'UNKNOWN';
        displayTitle = title;
      }

      // Parse the range from title or dedicated fields
      int? rangeStart, rangeEnd;

      // First try vocab_range fields
      if (asm['vocab_range_start'] != null && asm['vocab_range_end'] != null) {
        rangeStart = asm['vocab_range_start'];
        rangeEnd = asm['vocab_range_end'];
      } else if (asm['textbook_range'] != null) {
        final parsed = _parseRange(asm['textbook_range'].toString());
        rangeStart = parsed.$1;
        rangeEnd = parsed.$2;
      } else {
        // Parse from title
        final parsed = _parseRange(title);
        rangeStart = parsed.$1;
        rangeEnd = parsed.$2;
      }

      if (rangeStart == null || rangeEnd == null) continue;

      // Merge into existing or create new entry
      if (merged.containsKey(bookKey)) {
        final existing = merged[bookKey]!;
        final existingMin = existing['minRange'] as int? ?? rangeStart;
        final existingMax = existing['maxRange'] as int? ?? rangeEnd;
        existing['minRange'] =
            rangeStart < existingMin ? rangeStart : existingMin;
        existing['maxRange'] = rangeEnd > existingMax ? rangeEnd : existingMax;
      } else {
        merged[bookKey] = {
          'bookId': bookId,
          'title': displayTitle,
          'type': bookType,
          'minRange': rangeStart,
          'maxRange': rangeEnd,
        };
      }
    }

    return merged;
  }

  /// [NEW] Load merged past assignments into form fields
  void _loadMergedAssignmentsToForm() {
    if (_prevMyLog == null) return;

    final assignments = _prevMyLog!['assignments'] as List?;
    if (assignments == null || assignments.isEmpty) return;

    final merged = _mergeAssignmentRanges(assignments);
    if (merged.isEmpty) return;

    // Separate by type: VOCAB → _vocabAssignments, TEXTBOOK → _hwMainRows
    for (final entry in merged.entries) {
      final data = entry.value;
      final bookId = data['bookId'];
      final minR = data['minRange'];
      final maxR = data['maxRange'];
      final type = data['type'];
      final rangeStr = minR == maxR ? '$minR' : '$minR-$maxR';

      if (type == 'VOCAB' && bookId != null) {
        // Add to vocab assignments
        _vocabAssignments.add({
          'isWrongWords': false,
          'dueDate': _defaultDueDate,
          'publisher': null,
          'bookId': bookId,
          'range': rangeStr,
        });
      } else if (bookId != null) {
        // Add to main homework rows
        // Find the book to get its type
        final book = _findBook(bookId);
        _hwMainRows.add({
          'type': book?['type'],
          'publisher': book?['publisher'],
          'bookId': bookId,
          'range': rangeStr,
          'startUnit': minR,
          'endUnit': maxR,
          'dueDate': _defaultDueDate,
          'isOt': false,
        });
      }
    }

    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📋 ${merged.length}개 과제 범위를 불러왔습니다'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// [NEW] Build summary text of merged ranges for display
  String _buildMergedRangesSummary() {
    if (_prevMyLog == null) return '';

    final assignments = _prevMyLog!['assignments'] as List?;
    if (assignments == null || assignments.isEmpty) return '';

    final merged = _mergeAssignmentRanges(assignments);
    if (merged.isEmpty) return '';

    final parts = merged.values.map((data) {
      final title = data['title'] ?? '과제';
      final minR = data['minRange'];
      final maxR = data['maxRange'];
      final rangeStr = minR == maxR ? '$minR' : '$minR-$maxR';
      return '$title $rangeStr';
    }).toList();

    return parts.join(', ');
  }

  @override // Lines 1675-1680 usually correspond to end of State class or build methods. Assumed end of class.
  Widget build(BuildContext context) {
    final isSyntax = widget.subject == 'SYNTAX';

    return Scaffold(
      appBar: AppBar(
        title: Text(
            '${widget.studentName} 일지 (${isSyntax ? '구문' : '독해'}) - ${widget.date ?? ""}'),
        backgroundColor: isSyntax ? Colors.indigo : Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check),
            onPressed: _submitLog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Info Cards (Same as before)
                  _buildInfoSection(isSyntax),
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(thickness: 1)),

                  // 2. Today's Lesson
                  const Text('2. 당일 수업 일지',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  _buildDynamicSection(
                    title: '진도 및 수행',
                    color: Colors.green,
                    rows: _teachingRows,
                    allowedTypes: null,
                    rangeHint: '진도 입력 (예: 1-3)',
                    hasScore: true,
                    onAdd: () => setState(() => _teachingRows.add({
                          'type': null,
                          'publisher': null,
                          'bookId': null,
                          'range': '',
                          'score': 'B',
                          'isOt': false,
                          'description': '',
                        })),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _commentController,
                    maxLines: null,
                    minLines: 3, // [FIX] Start with 3 lines
                    textInputAction: TextInputAction
                        .newline, // [FIX] Force Enter key behavior
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                        labelText: '선생님 코멘트',
                        hintText: '수업 태도 및 특이사항',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white),
                  ),
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(thickness: 1)),

                  // 3. Next Homework
                  const Text('3. 다음 과제 부여',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),

                  // [REMOVED] Default Date Picker as per user request
                  // _buildDatePicker(
                  //     label: '기본 마감일 (새 항목 기본값)',
                  //     date: _defaultDueDate,
                  //     onChanged: (d) => setState(() => _defaultDueDate = d)),
                  const SizedBox(height: 16),

                  // [REDESIGNED] 주간 단어 과제 (N-Split 통합)
                  _buildVocabWeeklySchedule(),
                  const SizedBox(height: 16),

                  _buildDynamicSection(
                    title: '유형 A: 교재 (사진제출)',
                    color: Colors.blueAccent,
                    rows: _hwMainRows,
                    allowedTypes: [
                      'SYNTAX',
                      'READING',
                      'GRAMMAR',
                      'SCHOOL_EXAM'
                    ],
                    rangeHint: '범위 (예: 1~3)',
                    onAdd: () => setState(() => _hwMainRows.add({
                          'type': null,
                          'publisher': null,
                          'bookId': null,
                          'range': '',
                          'dueDate': _defaultDueDate,
                          'isOt': false,
                          'description': '',
                        })),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // [NEW] Attendance Logic
  Future<void> _checkAttendanceStatus() async {
    if (widget.date == null) return;
    final targetDate = DateTime.parse(widget.date!);

    try {
      final student =
          await _academyService.getStudent(int.parse(widget.studentId));
      final times = student['class_times'] as List? ?? [];

      final weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final dayStr = weekDays[targetDate.weekday - 1];

      dynamic classTime;
      try {
        // 1. Strict Search
        classTime = times.firstWhere(
          (t) =>
              t['day'] == dayStr &&
              (t['type'] == widget.subject ||
                  t['subject'] == (widget.subject == 'SYNTAX' ? '구문' : '독해')),
        );
      } catch (_) {
        // 2. Fallback Search (Day Only)
        try {
          classTime = times.firstWhere((t) => t['day'] == dayStr);
        } catch (e) {
          return;
        }
      }

      final attendance = await _academyService.checkAttendance(
          int.parse(widget.studentId), targetDate);

      // Pass if Present/Late
      if (attendance != null &&
          (attendance['status'] == 'PRESENT' ||
              attendance['status'] == 'LATE')) {
        return;
      }

      // Check Time Diff (For Message Context)
      bool isVeryLate = false;
      final startTimeStr = classTime['start_time'];
      if (startTimeStr != null) {
        final startParts = startTimeStr.split(':');
        final startH = int.parse(startParts[0]);
        final startM = int.parse(startParts[1]);
        final classStart = DateTime(
            targetDate.year, targetDate.month, targetDate.day, startH, startM);

        final now = DateTime.now();
        final limit = classStart.add(const Duration(minutes: 40));
        isVeryLate = now.isAfter(limit);
      }

      // Show Warning for ALL other cases (Absent, Unmarked-Early, Unmarked-Late)
      if (!mounted) return;
      _showAttendanceWarningDialog(isVeryLate, attendance?['status']);
    } catch (e) {
      print('Attendance Check Error: $e');
    }
  }

  void _showAttendanceWarningDialog(bool isVeryLate, String? status) {
    String message = '학생의 등원 기록이 없습니다.\n\n출석으로 처리하고 일지를 작성하시겠습니까?';

    if (status == 'ABSENT') {
      message = '현재 "결석" 상태입니다.\n\n출석으로 처리하고 일지를 작성하시겠습니까?';
    } else if (isVeryLate) {
      message = '수업 시작 후 40분이 지났습니다.\n(등원 기록 없음)\n\n출석으로 처리하고 일지를 작성하시겠습니까?';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 출석 확인 필요'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              context.pop();
              context.pop();
            },
            child: const Text('취소 (나가기)', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _academyService.createAttendance(
                  int.parse(widget.studentId),
                  'PRESENT',
                  DateTime.parse(widget.date!),
                );
                if (context.mounted) {
                  context.pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ 출석 처리되었습니다.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('출석 처리 및 작성'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(bool isSyntax) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('1. 과거 기록 확인',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 18, color: Colors.grey)),
        const SizedBox(height: 12),
        // 1. My Past Log (Review) - Aggregated Assignments
        if (_prevMyLog != null)
          _buildInfoCard(
            title: '지난 내 과제 (${isSyntax ? '구문' : '독해'})',
            date: _prevMyLog!['date'],
            content: '', // Use child instead
            icon: Icons.history,
            color: Colors.blue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPastAssignmentsList(), // [NEW] Render Aggregated List
                // [NEW] Merged Range Summary
                if (_buildMergedRangesSummary().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.summarize,
                            size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '📋 합산 범위: ${_buildMergedRangesSummary()}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // [NEW] Load Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loadMergedAssignmentsToForm,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('범위 불러오기'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          )
        else
          _buildInfoCard(
            title: '지난 내 과제 (${isSyntax ? '구문' : '독해'})',
            date: null,
            content: '기록 없음',
            icon: Icons.history,
            color: Colors.blue,
          ),
        const SizedBox(height: 8),

        // 2. Cross Log (Preview) - Single Log Summary
        if (_prevOtherLog != null)
          _buildInfoCard(
            title: '직전 교차 수업 (${!isSyntax ? '구문' : '독해'})',
            date: _prevOtherLog!['date'],
            content: _prevOtherLog!['content'],
            icon: Icons.swap_horiz,
            color: Colors.purple,
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, size: 16, color: Colors.purple),
                const SizedBox(width: 8),
                Text('직전 교차 수업 (${!isSyntax ? '구문' : '독해'}): 기록 없음',
                    style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
      ],
    );
  }

  // [NEW] Helper to render the aggregated assignment list
  Widget _buildPastAssignmentsList() {
    final assignments = _prevMyLog!['assignments'] as List?;
    if (assignments == null || assignments.isEmpty) {
      // Fallback to legacy content if available
      final legacyContent = _prevMyLog!['hw'];
      if (legacyContent != null && legacyContent.toString().isNotEmpty) {
        return Text(legacyContent, style: const TextStyle(fontSize: 14));
      }
      return const Text('과제 없음', style: TextStyle(color: Colors.grey));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var asm in assignments) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Badge
                _buildSubmissionStatusBadge(asm),
                const SizedBox(width: 8),
                // Title
                Expanded(
                  child: Text(
                    asm['title'] ?? '과제',
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ]
      ],
    );
  }

  Widget _buildSubmissionStatusBadge(Map<String, dynamic> assignment) {
    // Check submission & completion status
    // 'submission' might be null if not submitted
    // 'is_completed' might be true if teacher verified
    final isCompleted = assignment['is_completed'] == true;
    final submission = assignment['submission'];
    final bool hasSubmission = submission != null;

    // Logic:
    // 1. Completed (Verified) -> Green "완료"
    // 2. Submitted (Pending) -> Orange "검토중" (or "제출됨")
    // 3. Not Submitted -> Red "미완료"

    String label;
    Color color;

    if (isCompleted) {
      label = '완료';
      color = Colors.green;
    } else if (hasSubmission) {
      label = '제출됨';
      color = Colors.orange;
    } else {
      label = '미완료';
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildInfoCard(
      {required String title,
      required String? date,
      required String content,
      Widget? child, // [NEW] Support custom child content
      required IconData icon,
      required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          if (date != null)
            Text('$date :',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          if (child != null)
            child
          else
            Text(content, style: const TextStyle(fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }

  Widget _buildDynamicSection({
    required String title,
    required Color color,
    required List<Map<String, dynamic>> rows,
    required List<String>? allowedTypes,
    required String rangeHint,
    bool hasScore = false,
    required VoidCallback onAdd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            InkWell(
              onTap: onAdd,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    Icon(Icons.add_circle, size: 16, color: color),
                    const SizedBox(width: 4),
                    Text('추가',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold))
                  ])),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 24),
                _buildRowItem(rows[i], allowedTypes, rangeHint, hasScore, () {
                  // [FIX] Allow removing even if only 1 item?
                  // User asked to "basically create 1 slot".
                  // If we allow removing the last one, it becomes empty.
                  // Implication: Don't allow removing if it's the last one?
                  // Or if removed, add a fresh one?
                  // Let's keep existing logic: Only remove if > 1.
                  if (rows.length > 1) {
                    setState(() {
                      final hasSubmission = rows[i]['submissionStatus'] != null;
                      final isCompleted = rows[i]['isCompleted'] == true;
                      if (rows[i]['id'] != null &&
                          !hasSubmission &&
                          !isCompleted) {
                        _deletedAssignmentIds.add(rows[i]['id']);
                      }
                      rows.removeAt(i);
                    });
                  } else {
                    // Optional: Clear the row instead of removing?
                    setState(() {
                      // [FIX] Even when clearing the row, we must track the ID to delete the backend assignment
                      final hasSubmission = rows[i]['submissionStatus'] != null;
                      final isCompleted = rows[i]['isCompleted'] == true;
                      if (rows[i]['id'] != null &&
                          !hasSubmission &&
                          !isCompleted) {
                        _deletedAssignmentIds.add(rows[i]['id']);
                      }

                      rows[i] = {
                        'type': allowedTypes?.length == 1
                            ? allowedTypes!.first
                            : null,
                        'publisher': null,
                        'bookId': null,
                        'range': '',
                        'score': hasScore ? 'B' : null,
                        'dueDate': _defaultDueDate,
                        'isOt': false,
                        'description': '',
                      };
                    });
                  }
                }),
              ]
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRowItem(Map<String, dynamic> row, List<String>? allowedTypes,
      String rangeHint, bool hasScore, VoidCallback onRemove) {
    final types = _getAvailableTypes(allowedTypes: allowedTypes);

    // [FIX] Auto-select type if only one available
    if (types.length == 1 && row['type'] == null) {
      row['type'] = types.first;
    }

    final bool isVocab = row['type'] == 'VOCAB';

    // Check if selected book has units
    final selectedBook =
        _findBook(row['bookId'], type: row['type']?.toString());
    final List<dynamic> units = selectedBook?['units'] ?? [];
    final bool hasUnits = units.isNotEmpty;
    // [NEW] OT Logic
    final bool hasOt = selectedBook?['has_ot'] == true;
    final bool isOtSelected = row['isOt'] == true; // [FIX] Use boolean flag

    const decoration = InputDecoration(
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      border: OutlineInputBorder(),
      isDense: true,
      fillColor: Colors.white,
      filled: true,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Type dropdown
            if (types.length > 1)
              Container(
                width: 90,
                margin: const EdgeInsets.only(right: 8),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  isDense: true,
                  decoration: decoration.copyWith(hintText: '종류'),
                  value: row['type'],
                  items: types
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(_typeLabels[t] ?? t,
                              style: const TextStyle(fontSize: 13))))
                      .toList(),
                  onChanged: (val) => setState(() {
                    row['type'] = val;
                    row['publisher'] = null;
                    row['bookId'] = null;
                    row['startUnit'] = null;
                    row['endUnit'] = null;
                  }),
                ),
              ),
            // Publisher dropdown (only for Vocab)
            if (isVocab)
              Container(
                width: 140,
                margin: const EdgeInsets.only(right: 8),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  isDense: true,
                  decoration: decoration.copyWith(hintText: '출판사'),
                  value: row['publisher'],
                  items: () {
                    final publishers = _getPublishersForType('VOCAB');
                    final current = row['publisher'];
                    if (current != null &&
                        !publishers.any((p) => p == current)) {
                      row['publisher'] = null;
                    }
                    return publishers
                        .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis)))
                        .toList();
                  }(),
                  onChanged: (val) => setState(() {
                    row['publisher'] = _normalizePublisher(val);
                    row['bookId'] = null;
                  }),
                ),
              ),
            const Spacer(),
            // [MOVED] Date Picker in Header Row
            if (allowedTypes != null) ...[
              InkWell(
                onTap: () async {
                  final current = row['dueDate'] as DateTime? ?? DateTime.now();
                  final date = await showDatePicker(
                      context: context,
                      initialDate: current,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 60)));
                  if (date != null) {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(current),
                    );
                    if (time != null) {
                      setState(() {
                        row['dueDate'] = DateTime(date.year, date.month,
                            date.day, time.hour, time.minute);
                      });
                    }
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time,
                          size: 12, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('MM/dd(E) HH:mm', 'ko_KR')
                            .format(row['dueDate'] ?? _defaultDueDate),
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.grey, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onRemove),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Book Dropdown
            Expanded(
              flex: hasUnits ? 4 : 4,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                isDense: true,
                decoration: decoration.copyWith(hintText: '교재 선택'),
                value: row['bookId'],
                items: () {
                  if (row['type'] == null) return <DropdownMenuItem<int>>[];
                  final books =
                      _getBooksFiltered(row['type'], row['publisher']);
                  if (row['bookId'] != null &&
                      !books.any((b) => b['id'] == row['bookId'])) {
                    row['bookId'] = null;
                  }
                  return books.map((book) {
                    return DropdownMenuItem(
                        value: book['id'] as int,
                        child: Text(book['title'],
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)));
                  }).toList();
                }(),
                onChanged: (val) => setState(() {
                  row['bookId'] = val;
                  row['startUnit'] = null;
                  row['endUnit'] = null;
                }),
              ),
            ),
            const SizedBox(width: 8),

            // [NEW] OT Toggle Checkbox (if applicable)
            if (hasOt) ...[
              InkWell(
                onTap: () {
                  setState(() {
                    row['isOt'] = !(row['isOt'] ?? false);
                    if (row['isOt']) {
                      row['range'] = 'OT';
                      row['startUnit'] = null;
                      row['endUnit'] = null;
                    } else {
                      if (row['range'] == 'OT') row['range'] = '';
                    }
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOtSelected ? Colors.indigo.shade50 : Colors.white,
                    border: Border.all(
                        color: isOtSelected
                            ? Colors.indigo
                            : Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOtSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: isOtSelected ? Colors.indigo : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text('OT',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  isOtSelected ? Colors.indigo : Colors.grey)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Range Input: Dynamic (Units Dropdown or Text)
            if (hasUnits && !isVocab && !isOtSelected) ...[
              // Start Unit
              Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    isDense: true,
                    decoration: decoration.copyWith(hintText: '시작 강'),
                    value: row['startUnit'],
                    items: units
                        .map((u) => DropdownMenuItem(
                            value: u['unit_number'] as int,
                            child: Text('${u['unit_number']}강',
                                style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (val) => setState(() => row['startUnit'] = val),
                  )),
              const SizedBox(width: 4),
              const Text('~',
                  style: TextStyle(height: 3)), // Vertically align approx
              const SizedBox(width: 4),
              // End Unit
              Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    isDense: true,
                    decoration: decoration.copyWith(hintText: '끝 강'),
                    value: row['endUnit'],
                    items: units
                        .map((u) => DropdownMenuItem(
                            value: u['unit_number'] as int,
                            child: Text('${u['unit_number']}강',
                                style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (val) => setState(() => row['endUnit'] = val),
                  )),
            ] else if (!isOtSelected) ...[
              // Text Input
              Expanded(
                flex: 4,
                child: TextField(
                  style: const TextStyle(fontSize: 13),
                  decoration: decoration.copyWith(
                      hintText: rangeHint,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 14.5)),
                  controller: TextEditingController(text: row['range'])
                    ..selection = TextSelection.fromPosition(
                        TextPosition(offset: row['range'].length)),
                  onChanged: (val) => row['range'] = val,
                ),
              ),
            ],

            if (hasScore) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  isDense: true,
                  decoration: decoration.copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 11)),
                  value: row['score'],
                  items: ['A', 'B', 'C', 'F']
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Center(
                              child: Text(s,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold)))))
                      .toList(),
                  onChanged: (val) => setState(() => row['score'] = val),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (allowedTypes != null) ...[
          const SizedBox(height: 8),
          TextField(
            style: const TextStyle(fontSize: 13),
            maxLines: null,
            decoration: decoration.copyWith(
              hintText: '상세 지침 (예: 42p 날짜 보이게 업로드)',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon:
                  const Icon(Icons.edit_note, size: 20, color: Colors.blue),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            controller: TextEditingController(text: row['description'] ?? '')
              ..selection = TextSelection.fromPosition(
                TextPosition(offset: (row['description'] ?? '').length),
              ),
            onChanged: (val) => row['description'] = val,
          ),
        ],
      ],
    );
  }

  /// [REDESIGNED] 과제 목록 방식 위젯 - 자유 추가/삭제 가능
  Widget _buildVocabWeeklySchedule() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Add Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '📅 단어 과제',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.redAccent,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _vocabAssignments.add({
                    'isWrongWords': false,
                    'dueDate': _defaultDueDate,
                    'publisher': null,
                    'bookId': null,
                    'range': '',
                    'wrongWordsCount': 30,
                  });
                }),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('과제 추가', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
              ),
            ],
          ),

          // Empty State
          if (_vocabAssignments.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                children: [
                  Icon(Icons.assignment_outlined, size: 32, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('등록된 단어 과제가 없습니다',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  Text('위의 "과제 추가" 버튼을 눌러 추가하세요',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          ],

          // Assignment List
          ...List.generate(_vocabAssignments.length, (idx) {
            final item = _vocabAssignments[idx];
            final isWrongWords = item['isWrongWords'] ?? false;
            final dueDate = item['dueDate'] as DateTime? ?? _defaultDueDate;

            return Container(
              margin: EdgeInsets.only(top: idx == 0 ? 12 : 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isWrongWords
                      ? Colors.orange.shade200
                      : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row: Type Toggle + Delete
                  Row(
                    children: [
                      // Type Toggle Chips
                      _buildTypeChip('📚 일반', !isWrongWords, () {
                        setState(() => item['isWrongWords'] = false);
                      }),
                      const SizedBox(width: 6),
                      _buildTypeChip('🔥 오답', isWrongWords, () {
                        setState(() => item['isWrongWords'] = true);
                      }),
                      const Spacer(),
                      // Due Date
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: dueDate,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 60)),
                          );
                          if (date != null) {
                            if (context.mounted) {
                              // [FIX] Add Time Picker for Word Assignments too
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(dueDate),
                              );
                              if (time != null) {
                                setState(() {
                                  item['dueDate'] = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      time.hour,
                                      time.minute);
                                });
                              }
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 12, color: Colors.blue),
                              const SizedBox(width: 4),
                              Text(
                                // [FIX] Show Time in format
                                DateFormat('M/d(E) HH:mm', 'ko_KR')
                                    .format(dueDate),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.blue),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Delete Button
                      InkWell(
                        onTap: () => setState(() {
                          final hasSubmission =
                              item['submissionStatus'] != null;
                          final isCompleted = item['isCompleted'] == true;
                          if (item['id'] != null &&
                              !hasSubmission &&
                              !isCompleted) {
                            _deletedAssignmentIds.add(item['id']);
                          }
                          _vocabAssignments.removeAt(idx);
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.close,
                              size: 16, color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Content based on type
                  if (!isWrongWords) ...[
                    // 일반 단어장: 출판사, 교재, 범위
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            isDense: true,
                            decoration: const InputDecoration(
                              hintText: '출판사',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            value: item['publisher'],
                            items: _getPublishersForType('VOCAB')
                                .map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p,
                                        style: const TextStyle(fontSize: 12))))
                                .toList(),
                            onChanged: (val) => setState(() {
                              item['publisher'] = val;
                              item['bookId'] = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            isDense: true,
                            decoration: const InputDecoration(
                              hintText: '교재',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            value: item['bookId'],
                            items: _getBooksFiltered('VOCAB', item['publisher'])
                                .map((b) => DropdownMenuItem(
                                    value: b['id'] as int,
                                    child: Text(b['title'],
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (val) =>
                                setState(() => item['bookId'] = val),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: '범위 예:1-10',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (val) => item['range'] = val,
                            controller: TextEditingController(
                                text: item['range'] ?? ''),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // 오답 단어장
                    Row(
                      children: [
                        const Text('오답 단어 개수:', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: item['wrongWordsCount'] ?? 30,
                          items: [20, 30, 50, 100]
                              .map((n) => DropdownMenuItem(
                                  value: n,
                                  child: Text('$n개',
                                      style: const TextStyle(fontSize: 12))))
                              .toList(),
                          onChanged: (val) => setState(
                              () => item['wrongWordsCount'] = val ?? 30),
                        ),
                        const Spacer(),
                        const Text('💡 3-Strike 미졸업 단어',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.redAccent.withOpacity(0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.redAccent : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.redAccent : Colors.grey,
          ),
        ),
      ),
    );
  }

  void _populateAssignments(List<dynamic> assignments) {
    _hwMainRows.clear();
    _hwVocabRows.clear();
    _vocabAssignments.clear();

    for (var asm in assignments) {
      if (asm is! Map) continue;

      final submission = asm['submission'];
      final submissionStatus =
          submission is Map ? submission['status']?.toString() : null;
      final isCompleted =
          asm['is_completed'] == true || submissionStatus == 'APPROVED';

      final type = asm['assignment_type'];
      final relatedVocabBook = asm['related_vocab_book'];

      // 1. Handle Vocab Assignments
      if (relatedVocabBook != null || type == 'VOCAB_TEST') {
        int? bookId = relatedVocabBook as int?;
        String? publisher;

        if (bookId != null) {
          final book = _findBook(bookId, type: 'VOCAB');
          if (book != null) {
            publisher = _normalizePublisher(book['publisher']?.toString());
          }
        }

        final dueDateStr = asm['due_date'];
        if (dueDateStr != null) {
          try {
            final dueDate = DateTime.parse(dueDateStr);
            String range = asm['title'] ?? '';
            final start = asm['vocab_range_start'];
            final end = asm['vocab_range_end'];
            final isCumulative = asm['is_cumulative'] == true;

            if (start != null && end != null && (start > 0 || end > 0)) {
              range = '$start-$end';
            } else {
              final regex = RegExp(r'^\[.*?\]\s?(.*)$');
              final match = regex.firstMatch(range);
              if (match != null) range = match.group(1) ?? range;
            }

            _vocabAssignments.add({
              'id': asm['id'], // [NEW] Track ID
              'submissionStatus': submissionStatus,
              'isCompleted': isCompleted,
              'isWrongWords': isCumulative,
              'dueDate': dueDate,
              'publisher': publisher,
              'bookId': bookId,
              'range': range,
              'wrongWordsCount': isCumulative ? (end ?? 30) : 30,
            });
          } catch (e) {
            print('Error parsing vocab assignment: $e');
          }
        }
        continue;
      }

      // 2. Handle Manual Assignments
      String title = asm['title'] ?? '';
      final dueDateStr = asm['due_date'];
      DateTime? dueDate;
      if (dueDateStr != null) {
        try {
          dueDate = DateTime.parse(dueDateStr);
        } catch (_) {}
      }

      String range = title;
      int? bookId;
      String? publisher;

      final regex = RegExp(r'^\[(.*?)\]\s?(.*)$');
      final match = regex.firstMatch(title);

      if (match != null) {
        final bracketContent = match.group(1) ?? '';
        final remainder = match.group(2) ?? '';
        range = remainder;

        // Manual Book
        try {
          final book = _allBooks.firstWhere((b) => b['title'] == bracketContent,
              orElse: () => <String, dynamic>{});
          if (book.isNotEmpty) {
            bookId = book['id'];
          }
        } catch (_) {}
      }

      final rowData = {
        'id': asm['id'], // [NEW] Track ID
        'submissionStatus': submissionStatus,
        'isCompleted': isCompleted,
        'range': range,
        'dueDate': dueDate ?? _defaultDueDate,
        'isOt': false,
        'type': null,
        'publisher': publisher,
        'bookId': bookId,
        'description': asm['description'] ?? '',
        // [FIX] Parse startUnit/endUnit from textbook_range (e.g., '5-10' or title)
        'startUnit': null,
        'endUnit': null,
      };

      // [FIX] Parse unit range from title or textbook_range
      final textbookRange = asm['textbook_range']?.toString() ?? '';
      final unitMatch = RegExp(r'(\d+)\s*[-~]\s*(\d+)')
          .firstMatch(textbookRange.isNotEmpty ? textbookRange : range);
      if (unitMatch != null) {
        rowData['startUnit'] = int.tryParse(unitMatch.group(1) ?? '');
        rowData['endUnit'] = int.tryParse(unitMatch.group(2) ?? '');
      }

      if (rowData['type'] == null && bookId != null) {
        final book = _findBook(bookId);
        if (book != null) {
          rowData['type'] = book['type'];
        }
      }

      _hwMainRows.add(rowData);
    }
  }
}
