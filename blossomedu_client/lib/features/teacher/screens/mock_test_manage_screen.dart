import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/academy_service.dart';

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
    final yearController = TextEditingController(
        text: exam?['year']?.toString() ?? DateTime.now().year.toString());
    final monthController = TextEditingController(
        text: exam?['month']?.toString() ?? DateTime.now().month.toString());
    int selectedGrade = exam?['grade'] ?? 1; // 1, 2, 3
    final isEditingId = exam?['id'];

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
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: yearController,
                      decoration: const InputDecoration(labelText: '연도'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: monthController,
                      decoration: const InputDecoration(labelText: '월'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: selectedGrade,
                decoration: const InputDecoration(labelText: '학년'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('고1')),
                  DropdownMenuItem(value: 2, child: Text('고2')),
                  DropdownMenuItem(value: 3, child: Text('고3')),
                ],
                onChanged: (v) => selectedGrade = v!,
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
              final year = int.tryParse(yearController.text) ?? 2024;
              final month = int.tryParse(monthController.text) ?? 3;

              if (title.isEmpty) return;

              final data = {
                'title': title,
                'year': year,
                'month': month,
                'grade': selectedGrade,
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
                        '${exam['year']}년 ${exam['month']}월 고${exam['grade']} ${exam['title']}'),
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
