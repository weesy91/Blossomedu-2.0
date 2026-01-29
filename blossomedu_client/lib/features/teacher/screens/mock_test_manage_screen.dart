import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:blossomedu_client/core/services/academy_service.dart';

class MockTestManageScreen extends StatefulWidget {
  const MockTestManageScreen({Key? key}) : super(key: key);

  @override
  State<MockTestManageScreen> createState() => _MockTestManageScreenState();
}

class _MockTestManageScreenState extends State<MockTestManageScreen> {
  final _academyService = AcademyService();
  bool _isLoading = false;
  List<dynamic> _examInfos = [];

  @override
  void initState() {
    super.initState();
    _fetchExamInfos();
  }

  Future<void> _fetchExamInfos() async {
    setState(() => _isLoading = true);
    try {
      final data = await _academyService.getMockExamInfos();
      setState(() {
        _examInfos = data;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load exams: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showEditDialog({Map<String, dynamic>? exam}) async {
    final isEditing = exam != null;
    final titleController = TextEditingController(text: exam?['title'] ?? '');
    int selectedGrade = exam?['grade'] ?? 1; // 1, 2, 3
    final isEditingId = exam?['id'];

    // [NEW] Institution Logic (Dynamic)
    String selectedInstitution = exam?['institution'] ?? '교육청';

    // 1. Default options (Immutable base)
    final Set<String> defaultOptions = {
      '교육청',
      '평가원',
      '대성',
      '이투스',
      '메가스터디',
      '종로',
      '비상',
      '기타'
    };

    // 2. Extract existing institutions from loaded exams
    final Set<String> existingInstitutions = _examInfos
        .map((e) => e['institution'] as String?)
        .where((e) => e != null && e.isNotEmpty)
        .cast<String>()
        .toSet();

    // 3. Combine and sort
    // We want defaults + existing, but '기타' should always be last.
    // Let's make a combined set, remove '기타', sort, then add '기타' back.
    final Set<String> combinedSet = {
      ...defaultOptions,
      ...existingInstitutions
    };
    combinedSet.remove('기타');

    final List<String> institutionOptions = combinedSet.toList()..sort();
    institutionOptions.add('기타'); // Ensure '기타' is at the end

    final institutionController =
        TextEditingController(text: selectedInstitution);

    // Check if initial value is in options, if not set to '기타' and fill text controller
    // But now, since we dynamically added it, it SHOULD be in options unless it's a brand new one entered right now?
    // Actually, if we just added all existing ones to options, selectedInstitution IS in options (unless it's null).
    // So distinct 'custom' check is only needed if the user wants to enter a NEW one not in list.

    if (!institutionOptions.contains(selectedInstitution) &&
        selectedInstitution.isNotEmpty) {
      // This theoretically shouldn't happen for existing exams if we rebuilt the list correctly,
      // unless _examInfos hasn't refreshed yet or something.
      // But for safety, treat as custom.
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? '모의고사 수정' : '새 모의고사 등록'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '시험명 (예: 3월 학평)'),
              ),
              const SizedBox(height: 16),
              // [MODIFIED] Year/Month hidden, extracted from title
              // TextField(controller: yearController, ...),
              // TextField(controller: monthController, ...),

              DropdownButtonFormField<int>(
                value: selectedGrade,
                decoration: const InputDecoration(labelText: '대상 학년'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('고1')),
                  DropdownMenuItem(value: 2, child: Text('고2')),
                  DropdownMenuItem(value: 3, child: Text('고3')),
                ],
                onChanged: (v) => selectedGrade = v!,
              ),
              const SizedBox(height: 16),
              // [NEW] Institution Dropdown
              DropdownButtonFormField<String>(
                value: institutionOptions.contains(selectedInstitution)
                    ? selectedInstitution
                    : '기타',
                decoration: const InputDecoration(labelText: '주관/출판사'),
                items: institutionOptions
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) {
                  selectedInstitution = v!;
                  if (v != '기타') {
                    institutionController.text = v;
                  } else {
                    institutionController.text = '';
                  }
                  (context as Element)
                      .markNeedsBuild(); // Force rebuild to show/hide text field if needed
                },
              ),
              if (selectedInstitution == '기타' ||
                  !institutionOptions.contains(selectedInstitution))
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextField(
                    controller: institutionController,
                    decoration: const InputDecoration(labelText: '기관명 직접 입력'),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('시험명을 입력해주세요')));
                return;
              }

              // [NEW] Auto-extract Year/Month
              int year = DateTime.now().year;
              int month = DateTime.now().month;

              // Regex for Year (20xx)
              final yearMatch = RegExp(r'(20\d{2})').firstMatch(title);
              if (yearMatch != null) {
                year = int.parse(yearMatch.group(1)!);
              }

              // Regex for Month (1~12월 or just 1~12 followed by separator?)
              // Common pattern: "3월", "03월", "3mo", "March"
              // Let's stick to "N월" pattern for Korean context
              final monthMatch = RegExp(r'(\d{1,2})월').firstMatch(title);
              if (monthMatch != null) {
                month = int.parse(monthMatch.group(1)!);
              }

              final institution = institutionController.text.trim().isEmpty
                  ? selectedInstitution
                  : institutionController.text.trim();

              final data = {
                'title': title,
                'year': year,
                'month': month,
                'grade': selectedGrade,
                'institution': institution,
                'is_active': true,
              };

              try {
                if (isEditing) {
                  await _academyService.updateMockExamInfo(isEditingId, data);
                } else {
                  await _academyService.createMockExamInfo(data);
                }
                Navigator.pop(context);
                _fetchExamInfos();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  // [NEW] Question Edit Dialog
  Future<void> _showQuestionEditDialog(Map<String, dynamic> question) async {
    final int questionId = question['id'];
    int correctAnswer = question['correct_answer'] ?? 1;
    int score = question['score'] ?? 2;
    String category = question['category'] ?? 'TOPIC';

    // Category Options (Simplified)
    final categories = {
      'LISTENING': '듣기',
      'PURPOSE': '목적/심경',
      'TOPIC': '주제/제목',
      'DATA': '도표/일치',
      'MEANING': '함축의미',
      'GRAMMAR': '어법',
      'VOCAB': '어휘',
      'BLANK': '빈칸',
      'FLOW': '무관한문장',
      'ORDER': '순서',
      'INSERT': '삽입',
      'SUMMARY': '요약',
      'LONG': '장문'
    };

    await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                title: Text('${question['number']}번 문항 수정'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: '정답'),
                      value: correctAnswer,
                      items: [1, 2, 3, 4, 5]
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text('$e번')))
                          .toList(),
                      onChanged: (v) => setState(() => correctAnswer = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(labelText: '배점'),
                      value: score,
                      items: [2, 3]
                          .map((e) =>
                              DropdownMenuItem(value: e, child: Text('${e}점')))
                          .toList(),
                      onChanged: (v) => setState(() => score = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: '유형'),
                      value:
                          categories.containsKey(category) ? category : 'TOPIC',
                      items: categories.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => setState(() => category = v!),
                    )
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소')),
                  ElevatedButton(
                      onPressed: () async {
                        final data = {
                          'correct_answer': correctAnswer,
                          'score': score,
                          'category': category
                        };
                        try {
                          await _academyService.updateMockExamQuestion(
                              questionId, data);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('수정되었습니다.')));
                          _fetchExamInfos(); // Refresh full list to update UI
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')));
                        }
                      },
                      child: const Text('저장')),
                ],
              );
            }));
  }

  Future<void> _uploadAnswerKey(int id) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result != null) {
        final file = result.files.first;
        if (file.bytes == null) {
          // Web environment usually has bytes. Mobile might need path handling but we focus on web for admin tasks usually.
          // If bytes are null (e.g. mobile path), need io.File. But standard FilePicker usually gives bytes or path.
          // AcademyService expects bytes.
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('파일 데이터를 읽을 수 없습니다.')));
          return;
        }

        await _academyService.uploadMockExamAnswers(
          id,
          file.bytes!, // Uint8List to List<int>
          file.name,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정답지 업로드 완료!')),
        );
        _fetchExamInfos();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload Failed: $e')),
      );
    }
  }

  Future<void> _deleteExam(int id) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('삭제 확인'),
              content: const Text('정말로 이 모의고사를 삭제하시겠습니까?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child:
                        const Text('삭제', style: TextStyle(color: Colors.red))),
              ],
            ));

    if (confirmed == true) {
      try {
        await _academyService.deleteMockExamInfo(id);
        _fetchExamInfos();
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showDetail(Map<String, dynamic> exam) {
    final questions = (exam['questions'] as List?) ?? [];
    questions
        .sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${exam['year']}년 ${exam['month']}월 ${exam['title']} 상세'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400, // Limit height
          child: questions.isEmpty
              ? const Center(child: Text('등록된 문항이 없습니다.\n엑셀을 업로드해주세요.'))
              : ListView.builder(
                  itemCount: questions.length,
                  itemBuilder: (context, index) {
                    final q = questions[index];
                    final score = q['score'] ?? 2;
                    final isThreePoint = score == 3;
                    return ListTile(
                      onTap: () {
                        Navigator.pop(
                            context); // Close detail list first? Or keep it open?
                        // Better to keep it open, but simple refresh might be tricky.
                        // Let's close detail dialog, open edit, then reopen? No, that's bad UX.
                        // Just show edit dialog on top. Refreshing 'exam' map locally is hard because it's passed by value.
                        // We will rely on _fetchExamInfos() refreshing the background list.
                        // But the currently open Dialog won't refresh unless we rebuild it.
                        // For now: Close detail -> Open Edit -> Save -> Re-open detail?
                        // Or: Open Edit -> Save -> Update local 'questions' list -> setState.
                        // But 'questions' is local variable in _showDetail.
                        // Let's convert _showDetail to a proper Stateful Widget dialog or just re-fetch inside.
                        // Simple approach: Edit, then user requests "Refresh" or close/reopen.

                        // Better: _showQuestionEditDialog triggers _fetchExamInfos.
                        // The detail dialog holds a reference to 'exam' map which is from '_examInfos'.
                        // If '_examInfos' updates, we need the dialog to rebuild.

                        _showQuestionEditDialog(q).then((_) {
                          // After edit, we might want to refresh this view.
                          // Since this is just a static view of 'exam' map passed in...
                          // We need to re-find this exam from the updated _examInfos and update 'questions'.
                          // But we are inside a function, not a persistent widget state for the dialog.
                          // The simplest UX: Close detail dialog on tap, show edit, then user opens detail again.
                          // Or, just show edit, and tell user to reopen to see changes.
                          // Let's allow editing, and if successful, we manually update the 'q' object in place so UI updates?
                          // 'q' is a reference to a map in 'questions' list. If we update 'q', UI might update if we call setState?
                          // But we are in showDialog builder... need StatefulBuilder there too.
                        });
                      },
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: isThreePoint
                            ? Colors.redAccent.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                        child: Text('${q['number']}',
                            style: TextStyle(
                                color: isThreePoint ? Colors.red : Colors.black,
                                fontWeight: isThreePoint
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                      ),
                      title: Text('정답: ${q['correct_answer'] ?? '-'}'),
                      subtitle:
                          Text('배점: ${score}점 | 유형: ${q['category'] ?? '-'}'),
                      trailing: isThreePoint
                          ? const Chip(
                              label: Text('3점', style: TextStyle(fontSize: 10)))
                          : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('모의고사 정답 관리')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _examInfos.length,
              itemBuilder: (context, index) {
                final exam = _examInfos[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    onTap: () => _showDetail(exam), // [NEW] Link Tap
                    title: Text(
                        '[${exam['institution'] ?? '교육청'}] ${exam['year']}년 ${exam['month']}월 고${exam['grade']} ${exam['title']}'),

                    subtitle: Text(
                        '문항 수: ${exam['questions'] != null ? (exam['questions'] as List).length : 0}개 (탭하여 상세 보기)'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.upload_file,
                              color: Colors.green),
                          tooltip: '정답 엑셀 업로드',
                          onPressed: () => _uploadAnswerKey(exam['id']),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditDialog(exam: exam),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteExam(exam['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
