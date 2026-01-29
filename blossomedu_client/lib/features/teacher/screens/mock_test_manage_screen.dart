import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:blossomedu_client/core/services/academy_service.dart';
import 'package:blossomedu_client/features/teacher/screens/mock_test_detail_screen.dart';

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

              // [NEW] Auto-extract Year/Month (Strict)
              int year = 0;
              int month = 0;

              // Regex: 20xx
              final yearMatch = RegExp(r'(20\d{2})').firstMatch(title);
              // Regex: 1~12월
              final monthMatch = RegExp(r'(\d{1,2})월').firstMatch(title);

              if (yearMatch == null || monthMatch == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      '제목에 연도(20xx)와 월(x월)을 반드시 포함해주세요.\n예: 2026년 3월 모의고사'),
                  duration: Duration(seconds: 3),
                ));
                return;
              }

              year = int.parse(yearMatch.group(1)!);
              month = int.parse(monthMatch.group(1)!);

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

  // _showQuestionEditDialog removed (moved to detail screen)

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
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('파일 데이터를 읽을 수 없습니다.')));
          return;
        }

        await _academyService.uploadMockExamAnswers(
          id,
          file.bytes!,
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
    Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MockTestDetailScreen(
                    examId: exam['id'],
                    title:
                        '${exam['year']}년 ${exam['month']}월 ${exam['title']}')))
        .then((_) => _fetchExamInfos()); // Refresh list on return
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
