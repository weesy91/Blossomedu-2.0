import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/vocab_service.dart';
import '../../../core/services/academy_service.dart'; // [NEW]
import 'teacher_vocab_detail_screen.dart';

class TeacherVocabManageScreen extends StatefulWidget {
  const TeacherVocabManageScreen({super.key});

  @override
  State<TeacherVocabManageScreen> createState() =>
      _TeacherVocabManageScreenState();
}

class _TeacherVocabManageScreenState extends State<TeacherVocabManageScreen> {
  final VocabService _vocabService = VocabService();
  final AcademyService _academyService = AcademyService(); // [NEW]
  List<dynamic> _books = [];
  List<dynamic> _filteredSchools = []; // [NEW] Schools filtered by branch
  List<dynamic> _branches = []; // [NEW]
  List<dynamic> _publishers = [];
  bool _isLoading = true;
  final Set<String> _excludedBookTitles = {'내 단어장', 'Wrong Only'};

  @override
  void initState() {
    super.initState();
    _loadBooks();
    _loadPublishers();
    _loadBranches(); // [NEW]
  }

  Future<void> _loadBooks() async {
    setState(() => _isLoading = true);
    try {
      final books = await _vocabService.getVocabBooks();
      final filtered = books.where((book) {
        final title = (book['title'] ?? '').toString().trim();
        final publisher =
            (book['publisher_name'] ?? '').toString().trim().toLowerCase();
        if (_excludedBookTitles.contains(title)) return false;
        if (publisher == '개인단어장') return false;
        if (publisher == 'system') return false;
        return true;
      }).toList();
      setState(() {
        _books = filtered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('단어장 로딩 실패: $e')),
      );
    }
  }

  Future<void> _loadPublishers() async {
    try {
      final publishers = await _vocabService.getPublishers();
      if (mounted) {
        setState(() => _publishers = publishers);
      }
    } catch (e) {
      print('출판사 목록 로딩 실패: $e');
    }
  }

  // [NEW] Load Branches
  Future<void> _loadBranches() async {
    try {
      final branches = await _academyService.getBranches();
      if (mounted) {
        setState(() => _branches = branches);
      }
    } catch (e) {
      print('분원 목록 로딩 실패: $e');
    }
  }

  Future<void> _pickAndUploadCsv() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result != null) {
        final platformFile = result.files.first;
        final fileBytes = platformFile.bytes;
        final fileName = platformFile.name;

        if (fileBytes == null) {
          throw Exception('파일 데이터를 읽을 수 없습니다.');
        }

        if (mounted) {
          _showUploadDialog(fileBytes, fileName);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일 선택 오류: $e')),
      );
    }
  }

  void _showUploadDialog(List<int> fileBytes, String fileName) {
    final titleController =
        TextEditingController(text: fileName.replaceAll('.csv', ''));
    final descController = TextEditingController();
    bool isUploading = false;
    int? selectedBranchId; // [NEW]
    int? selectedSchoolId;
    int? selectedGrade;
    int? selectedPublisherId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('단어장 업로드'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('선택된 파일: $fileName'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '단어장 이름'),
                      enabled: !isUploading,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(labelText: '설명 (선택)'),
                      enabled: !isUploading,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                          labelText: '출판사',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                      value: selectedPublisherId,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('선택')),
                        ..._publishers.map((p) => DropdownMenuItem<int>(
                              value: p['id'],
                              child: Text(p['name']),
                            ))
                      ],
                      onChanged: isUploading
                          ? null
                          : (val) {
                              setDialogState(() => selectedPublisherId = val);
                            },
                    ),
                    const SizedBox(height: 12),
                    // [NEW] Branch Dropdown
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                          labelText: '대상 분원',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                      value: selectedBranchId,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text("전체 분원 (본사)")),
                        ..._branches.map((b) => DropdownMenuItem<int>(
                              value: b['id'],
                              child: Text(b['name']),
                            ))
                      ],
                      onChanged: isUploading
                          ? null
                          : (val) async {
                              setDialogState(() {
                                selectedBranchId = val;
                                selectedSchoolId = null;
                                _filteredSchools = []; // Clear while loading
                              });
                              // Fetch schools for selected branch
                              final schools =
                                  await _vocabService.getSchools(branchId: val);
                              setDialogState(() => _filteredSchools = schools);
                            },
                    ),
                    const SizedBox(height: 12),
                    // School Dropdown (Filtered by Branch)
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                          labelText: '대상 학교 (선택)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                      value: selectedSchoolId,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text("전체 학교")),
                        ..._filteredSchools.map((s) => DropdownMenuItem<int>(
                              value: s['id'],
                              child: Text(s['name']),
                            ))
                      ],
                      onChanged: isUploading
                          ? null
                          : (val) {
                              setDialogState(() => selectedSchoolId = val);
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                          labelText: '대상 학년 (선택)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                      value: selectedGrade,
                      items: const [
                        DropdownMenuItem(value: null, child: Text("전체 학년")),
                        DropdownMenuItem(value: 1, child: Text("1학년")),
                        DropdownMenuItem(value: 2, child: Text("2학년")),
                        DropdownMenuItem(value: 3, child: Text("3학년")),
                      ],
                      onChanged: isUploading
                          ? null
                          : (val) {
                              setDialogState(() => selectedGrade = val);
                            },
                    ),
                    if (isUploading) ...[
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('업로드 및 처리 중... (시간이 걸릴 수 있습니다)'),
                    ],
                  ],
                ),
              ),
              actions: isUploading
                  ? []
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          if (titleController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('단어장 이름을 입력해주세요.')),
                            );
                            return;
                          }
                          if (selectedPublisherId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('출판사를 선택해주세요.')),
                            );
                            return;
                          }

                          setDialogState(() => isUploading = true);

                          try {
                            await _vocabService.uploadVocabBook(
                              title: titleController.text,
                              description: descController.text,
                              fileBytes: fileBytes,
                              filename: fileName,
                              publisherId: selectedPublisherId,
                              targetBranchId: selectedBranchId, // [NEW]
                              targetSchoolId: selectedSchoolId,
                              targetGrade: selectedGrade,
                            );

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('업로드 성공!')),
                              );
                              _loadBooks();
                            }
                          } catch (e) {
                            setDialogState(() => isUploading = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('업로드 실패: $e')),
                              );
                            }
                          }
                        },
                        child: const Text('업로드'),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteBook(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('단어장 삭제'),
        content: const Text('정말로 이 단어장을 삭제하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _vocabService.deleteVocabBook(id);
        _loadBooks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
        }
      }
    }
  }

  // Edit vocab book dialog
  void _showEditDialog(Map<String, dynamic> book) {
    final titleController = TextEditingController(text: book['title'] ?? '');
    final descController =
        TextEditingController(text: book['description'] ?? '');
    int? selectedPublisherId = book['publisher'];
    int? selectedBranchId = book['target_branch']; // [NEW]
    int? selectedSchoolId = book['target_school'];
    int? selectedGrade = book['target_grade'];
    bool isSaving = false;
    List<dynamic> editFilteredSchools = []; // Local state for edit dialog

    // Preload schools if branch is already selected
    if (selectedBranchId != null) {
      _vocabService.getSchools(branchId: selectedBranchId).then((schools) {
        // Will update in dialog
      });
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Load schools when dialog opens if branch is selected
            if (selectedBranchId != null && editFilteredSchools.isEmpty) {
              _vocabService
                  .getSchools(branchId: selectedBranchId)
                  .then((schools) {
                setDialogState(() => editFilteredSchools = schools);
              });
            }

            return AlertDialog(
              title: const Text('단어장 정보 수정'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: '단어장 이름'),
                      enabled: !isSaving,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(labelText: '설명 (선택)'),
                      enabled: !isSaving,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                          labelText: '출판사',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                      value: selectedPublisherId,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('선택안함')),
                        ..._publishers.map((p) => DropdownMenuItem<int>(
                              value: p['id'],
                              child: Text(p['name']),
                            ))
                      ],
                      onChanged: isSaving
                          ? null
                          : (val) =>
                              setDialogState(() => selectedPublisherId = val),
                    ),
                    const SizedBox(height: 12),
                    // [NEW] Branch Dropdown
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                          labelText: '대상 분원',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                      value: selectedBranchId,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('전체 분원 (본사)')),
                        ..._branches.map((b) => DropdownMenuItem<int>(
                              value: b['id'],
                              child: Text(b['name']),
                            ))
                      ],
                      onChanged: isSaving
                          ? null
                          : (val) async {
                              setDialogState(() {
                                selectedBranchId = val;
                                selectedSchoolId = null;
                                editFilteredSchools = [];
                              });
                              if (val != null) {
                                final schools = await _vocabService.getSchools(
                                    branchId: val);
                                setDialogState(
                                    () => editFilteredSchools = schools);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                          labelText: '대상 학교 (선택)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                      value: selectedSchoolId,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('전체 학교')),
                        ...editFilteredSchools.map((s) => DropdownMenuItem<int>(
                              value: s['id'],
                              child: Text(s['name']),
                            ))
                      ],
                      onChanged: isSaving
                          ? null
                          : (val) =>
                              setDialogState(() => selectedSchoolId = val),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                          labelText: '대상 학년 (선택)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8)),
                      value: selectedGrade,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('전체 학년')),
                        DropdownMenuItem(value: 1, child: Text('1학년')),
                        DropdownMenuItem(value: 2, child: Text('2학년')),
                        DropdownMenuItem(value: 3, child: Text('3학년')),
                      ],
                      onChanged: isSaving
                          ? null
                          : (val) => setDialogState(() => selectedGrade = val),
                    ),
                    if (isSaving) ...[
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
              actions: isSaving
                  ? []
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          if (titleController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('단어장 이름을 입력해주세요.')),
                            );
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            await _vocabService.updateVocabBook(book['id'], {
                              'title': titleController.text,
                              'description': descController.text,
                              'publisher': selectedPublisherId,
                              'target_branch': selectedBranchId, // [NEW]
                              'target_school': selectedSchoolId,
                              'target_grade': selectedGrade,
                            });
                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('수정 완료!')),
                              );
                              _loadBooks();
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('수정 실패: $e')),
                              );
                            }
                          }
                        },
                        child: const Text('저장'),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('단어장 관리'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? const Center(
                  child: Text('등록된 단어장이 없습니다.\n+ 버튼을 눌러 엑셀 파일을 업로드하세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey)))
              : RefreshIndicator(
                  onRefresh: _loadBooks,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _books.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final book = _books[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.grey.withOpacity(0.05),
                                blurRadius: 5,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TeacherVocabDetailScreen(
                                  bookId: book['id'],
                                  bookTitle: book['title'] ?? '제목 없음',
                                ),
                              ),
                            );
                          },
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.teal.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.book, color: Colors.teal),
                          ),
                          title: Text(book['title'] ?? '제목 없음',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(book['description'] ?? '설명 없음'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    color: Colors.teal),
                                onPressed: () => _showEditDialog(book),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.grey),
                                onPressed: () => _deleteBook(book['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndUploadCsv,
        label: const Text('CSV 업로드'),
        icon: const Icon(Icons.upload_file),
        backgroundColor: Colors.teal,
      ),
    );
  }
}
