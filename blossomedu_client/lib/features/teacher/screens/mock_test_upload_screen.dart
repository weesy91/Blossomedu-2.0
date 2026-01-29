import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../../../core/services/academy_service.dart';

class MockTestUploadScreen extends StatefulWidget {
  const MockTestUploadScreen({super.key});

  @override
  State<MockTestUploadScreen> createState() => _MockTestUploadScreenState();
}

class _MockTestUploadScreenState extends State<MockTestUploadScreen> {
  final AcademyService _service = AcademyService();

  List<dynamic> _examInfos = [];
  List<dynamic> _students = []; // For manual matching
  dynamic _selectedExam;

  bool _isLoading = false;
  List<dynamic> _scannedResults = [];

  // File data
  String? _fileName;
  Uint8List? _fileBytes;

  // Filters
  int _selectedFilterGrade = 0; // 0: All
  String _selectedFilterInstitution = '전체'; // '전체': All
  List<String> _institutionOptions = ['전체']; // Dynamic options

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final exams = await _service.getMockExamInfos();
      // Fetch active students for manual matching
      final students = await _service.getStudents(scope: 'active');

      setState(() {
        _examInfos = exams;
        _students = students;

        // Populate filter options
        final distinctInst =
            exams.map((e) => e['institution'] as String? ?? '교육청').toSet();
        _institutionOptions = ['전체', ...distinctInst.toList()..sort()];

        // Initial selection logic handled by re-filtering logic
        _updateSelectedExam();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('데이터 로드 실패: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );

    if (result != null) {
      setState(() {
        _fileName = result.files.single.name;
        _fileBytes = result.files.single.bytes;
        _scannedResults = []; // Reset results on new file
      });
    }
  }

  Future<void> _scanOMR() async {
    if (_selectedExam == null || _fileBytes == null) return;

    setState(() => _isLoading = true);
    try {
      final results =
          await _service.scanOMR(_selectedExam['id'], _fileBytes!, _fileName!);
      setState(() {
        _scannedResults = results;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('스캔 실패: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveResults() async {
    // Filter valid results
    // Logic: student should be identified (either auto or manual) AND score data exists.
    final validResults = _scannedResults.where((r) {
      final hasStudent = r['student'] != null;
      final hasScore = r['score_data'] != null;
      return hasStudent && hasScore;
    }).map((r) {
      final sData = r['student'];
      final cData = r['score_data'];
      return {
        'student_id': sData['id'],
        'score': cData['score'],
        'grade': cData['grade'],
        'wrong_counts': cData['wrong_counts'],
        'wrong_type_breakdown':
            cData['wrong_type_breakdown'], // Make sure backend returns this
        'wrong_question_numbers': cData['wrong_question_numbers'],
        'student_answers': cData['student_answers_dict'] ??
            cData['student_answers'], // adjust key if needed
      };
    }).toList();

    if (validResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장할 유효한 결과가 없습니다.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _service.confirmMockExamResults(_selectedExam['id'], validResults);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${validResults.length}건 저장 완료!')),
      );
      Navigator.pop(context); // Close screen on success
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // [NEW] Helper to filter exams
  List<dynamic> get _filteredExams {
    return _examInfos.where((e) {
      final g = e['grade'] as int? ?? 0;
      final i = e['institution'] as String? ?? '교육청';

      bool matchGrade = _selectedFilterGrade == 0 || g == _selectedFilterGrade;
      bool matchInst =
          _selectedFilterInstitution == '전체' || i == _selectedFilterInstitution;

      return matchGrade && matchInst;
    }).toList();
  }

  void _updateSelectedExam() {
    final list = _filteredExams;
    if (list.isNotEmpty) {
      // If current selection is not in list, pick first
      if (_selectedExam == null ||
          !list.any((e) => e['id'] == _selectedExam['id'])) {
        _selectedExam = list.first;
      }
    } else {
      _selectedExam = null;
    }
  }

  // [NEW] Verification Dialog
  void _showVerificationDialog(int index, Map<String, dynamic> item) {
    final imageBase64 = item['omr_image'];
    final rawId = item['student_id_raw'];
    final student = item['student'];
    final scoreData = item['score_data'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('OMR 판독 확인 및 수정'),
            content: SizedBox(
              width: 500,
              height: 600,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. OMR Image
                    if (imageBase64 != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('판독 이미지 (수험번호 영역 확인)',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                            ),
                            child: Image.memory(
                              base64Decode(imageBase64),
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      )
                    else
                      const Text('이미지 데이터가 없습니다.',
                          style: TextStyle(color: Colors.grey)),

                    // 2. Info
                    Text('인식된 수험번호: $rawId',
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    if (scoreData != null)
                      Text(
                          '점수: ${scoreData['score']}점 (등급: ${scoreData['grade']})',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo)),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // 3. Correction
                    const Text('학생 수동 지정 (오류 수정)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      hint: const Text('학생 선택'),
                      value: student?['id'],
                      items: _students.map<DropdownMenuItem<int>>((s) {
                        return DropdownMenuItem(
                          value: s['id'],
                          child: Text(
                              '${s['name']} (${s['school']} ${s['grade']}) [${s['attendance_code'] ?? '코드없음'}]'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        // Update parent state
                        final selectedS =
                            _students.firstWhere((s) => s['id'] == val);

                        // Update local dialog state if needed (though dropdown handles value)
                        setStateDialog(() {});

                        // Update main list state
                        this.setState(() {
                          _scannedResults[index]['student'] = selectedS;
                          _scannedResults[index]['status'] = 'MANUAL';
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('닫기'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('모의고사 채점 및 업로드')),
      body: Column(
        children: [
          // 1. Selector Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Filter Row
                Row(children: [
                  // Grade Filter
                  Expanded(
                      child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                              labelText: '학년 필터',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 0)),
                          value: _selectedFilterGrade,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('전체')),
                            DropdownMenuItem(value: 1, child: Text('고1')),
                            DropdownMenuItem(value: 2, child: Text('고2')),
                            DropdownMenuItem(value: 3, child: Text('고3')),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedFilterGrade = val!;
                              _updateSelectedExam();
                            });
                          })),
                  const SizedBox(width: 10),
                  // Institution Filter
                  Expanded(
                      child: DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                              labelText: '출판사 필터',
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 0)),
                          value: _selectedFilterInstitution,
                          items: _institutionOptions
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s)))
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedFilterInstitution = val!;
                              _updateSelectedExam();
                            });
                          })),
                ]),
                const SizedBox(height: 16),

                DropdownButtonFormField(
                  decoration: const InputDecoration(labelText: '시험지 선택'),
                  value: _selectedExam != null ? _selectedExam['id'] : null,
                  items: _filteredExams.map<DropdownMenuItem<int>>((e) {
                    return DropdownMenuItem(
                      value: e['id'],
                      child:
                          Text('[${e['year']}년 ${e['month']}월] ${e['title']}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedExam =
                          _examInfos.firstWhere((e) => e['id'] == val);
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _fileName ?? '파일을 선택해주세요 (PDF/Image)',
                        style: TextStyle(
                            color:
                                _fileName == null ? Colors.grey : Colors.black),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('파일 찾기'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed:
                          (_fileBytes != null && !_isLoading) ? _scanOMR : null,
                      icon: const Icon(Icons.scanner),
                      label: const Text('스캔 시작'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white),
                    ),
                  ],
                )
              ],
            ),
          ),

          if (_isLoading) const LinearProgressIndicator(),

          // 2. Results List
          Expanded(
            child: _scannedResults.isEmpty
                ? const Center(child: Text('스캔 결과가 여기에 표시됩니다.'))
                : ListView.builder(
                    itemCount: _scannedResults.length,
                    itemBuilder: (context, index) {
                      final item = _scannedResults[index];
                      final student = item['student'];
                      final scoreData = item['score_data'];
                      final errorMsg = item['error_msg'];
                      final rawId = item['student_id_raw'];

                      final bool isSuccess =
                          student != null && scoreData != null;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        color: isSuccess
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        child: InkWell(
                          onTap: () => _showVerificationDialog(index, item),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                        isSuccess
                                            ? Icons.check_circle
                                            : Icons.error,
                                        color: isSuccess
                                            ? Colors.green
                                            : Colors.red),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: student != null
                                          ? Text(
                                              '${student['name']} (${student['school']})',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16))
                                          : Text('학생 미식별 (ID: $rawId)',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.red)),
                                    ),
                                    if (scoreData != null)
                                      Text(
                                          '${scoreData['score']}점 (${scoreData['grade']}등급)',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: Colors.indigo))
                                  ],
                                ),
                                if (errorMsg != null &&
                                    errorMsg.toString().isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 4, left: 32),
                                    child: Text(errorMsg,
                                        style: const TextStyle(
                                            color: Colors.red, fontSize: 12)),
                                  ),

                                // Manual Matching Logic
                                if (student == null)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(top: 8, left: 32),
                                    child: Row(
                                      children: [
                                        const Text('수동 선택: ',
                                            style: TextStyle(fontSize: 12)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: SizedBox(
                                            height: 36,
                                            child: DropdownButtonFormField<int>(
                                              isExpanded: true,
                                              decoration: const InputDecoration(
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          horizontal: 10),
                                                  border: OutlineInputBorder()),
                                              hint: const Text('학생 선택'),
                                              items: _students
                                                  .map<DropdownMenuItem<int>>(
                                                      (s) {
                                                return DropdownMenuItem(
                                                  value: s['id'],
                                                  child: Text(
                                                      '${s['name']} (${s['school']} ${s['grade']})'),
                                                );
                                              }).toList(),
                                              onChanged: (val) {
                                                final selectedS =
                                                    _students.firstWhere(
                                                        (s) => s['id'] == val);
                                                setState(() {
                                                  // Update this item in result list
                                                  _scannedResults[index]
                                                      ['student'] = selectedS;
                                                  _scannedResults[index]
                                                      ['status'] = 'MANUAL';
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // 3. Footer
          if (_scannedResults.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveResults,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white),
                    child: const Text('결과 저장하기',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            )
        ],
      ),
    );
  }
}
