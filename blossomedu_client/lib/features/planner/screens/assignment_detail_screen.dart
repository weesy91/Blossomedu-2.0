import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/constants.dart';
import '../../../core/services/academy_service.dart';

class AssignmentDetailScreen extends StatefulWidget {
  final String taskId;

  const AssignmentDetailScreen({required this.taskId, super.key});

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  final AcademyService _academyService = AcademyService();
  final ImagePicker _picker = ImagePicker();

  final List<XFile> _selectedImages = [];
  final PageController _previewController = PageController();
  int _currentPreviewIndex = 0;
  bool _isSubmitting = false;
  bool _isLoading = true;
  Map<String, dynamic>? _assignmentData;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    try {
      final data =
          await _academyService.getAssignmentDetail(int.parse(widget.taskId));
      if (mounted) {
        setState(() {
          _assignmentData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print('Detail Fetch Error: $e');
    }
  }

  Map<String, dynamic>? _getSubmission() {
    final data = _assignmentData;
    if (data == null) return null;
    final submission = data['submission'];
    if (submission is Map<String, dynamic>) return submission;
    if (submission is Map) {
      return submission.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  String _resolveImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return '${AppConfig.baseUrl}$url';
  }

  DateTime? _parseDateOnly(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    DateTime? parsed;
    try {
      parsed = DateTime.parse(raw);
    } catch (_) {
      try {
        parsed = DateFormat('yyyy-MM-dd HH:mm:ss').parse(raw);
      } catch (_) {
        return null;
      }
    }
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    return DateTime(local.year, local.month, local.day);
  }

  List<String> _getSubmissionImageUrls() {
    final submission = _getSubmission();
    final List<String> urls = [];
    final images = submission?['images'];
    if (images is List) {
      for (final item in images) {
        if (item is Map) {
          final raw = item['image_url'] ?? item['image'];
          final resolved = _resolveImageUrl(raw?.toString());
          if (resolved.isNotEmpty) urls.add(resolved);
        }
      }
    }
    if (urls.isEmpty) {
      final raw = submission?['image_url'] ?? submission?['image'];
      final resolved = _resolveImageUrl(raw?.toString());
      if (resolved.isNotEmpty) urls.add(resolved);
    }
    return urls;
  }

  void _removeSelectedImage(int index) {
    if (index < 0 || index >= _selectedImages.length) return;
    setState(() {
      _selectedImages.removeAt(index);
      if (_currentPreviewIndex >= _selectedImages.length) {
        _currentPreviewIndex =
            _selectedImages.isEmpty ? 0 : _selectedImages.length - 1;
      }
    });
  }

  Future<void> _pickImages(ImageSource source) async {
    if (source == ImageSource.gallery) {
      // [FIX] Compress: Quality 70, MaxWidth FHD (1920)
      final images =
          await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1920);
      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
          _currentPreviewIndex = 0;
        });
      }
      return;
    }

    // [FIX] Compress: Quality 70, MaxWidth FHD (1920)
    final XFile? image = await _picker.pickImage(
        source: source, imageQuality: 70, maxWidth: 1920);
    if (image != null) {
      setState(() {
        _selectedImages.add(image);
        _currentPreviewIndex = 0;
      });
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('카메라로 촬영하기'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImages(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('갤러리에서 선택하기'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImages(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitManual() async {
    if (_selectedImages.isEmpty) return;
    setState(() => _isSubmitting = true);

    try {
      final bytesList = <List<int>>[];
      final filenames = <String>[];
      for (final image in _selectedImages) {
        final bytes = await image.readAsBytes();
        final filename =
            image.name.isNotEmpty ? image.name : image.path.split('/').last;
        bytesList.add(bytes);
        filenames.add(filename);
      }
      final success = await _academyService.submitAssignment(
        int.parse(widget.taskId),
        fileBytesList: bytesList,
        filenames: filenames,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제출 완료. 검토중입니다.')),
        );
        setState(() => _selectedImages.clear());
        await _fetchDetail();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('제출 실패. 다시 시도해주세요.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오류가 발생했습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _startVocabTest() {
    if (_assignmentData == null) return;

    // N-Split Vocab Logic
    // Need bookId, range("1-5")
    final bookId = _assignmentData!['related_vocab_book'];
    final start = _assignmentData!['vocab_range_start'];
    final end = _assignmentData!['vocab_range_end'];

    if (bookId != null && start != null && end != null) {
      context.push('/student/test/start', extra: {
        'bookId': bookId,
        'range': '$start-$end',
        'assignmentId': widget.taskId,
        'testMode': 'test', // [FIX] Use 'test' mode for timer and results
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('단어장 정보가 올바르지 않습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('과제 수행')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignmentData == null
              ? const Center(child: Text('과제 정보를 불러올 수 없습니다.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    // [NEW] Check if assignment is locked (before start_date)
    DateTime? startDate = _parseDateOnly(_assignmentData!['start_date']);
    if (startDate == null &&
        _assignmentData!['assignment_type'] == 'VOCAB_TEST') {
      final dueDate = _parseDateOnly(_assignmentData!['due_date']);
      if (dueDate != null) {
        startDate = dueDate.subtract(const Duration(days: 1));
      }
    }
    if (startDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (today.isBefore(startDate)) {
        final startDateFormatted = DateFormat('M월 d일').format(startDate);
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                '아직 수행할 수 없는 과제입니다',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                '$startDateFormatted부터 수행 가능합니다',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Header Info
        Text(
          _assignmentData!['title'] ?? '제목 없음',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _assignmentData!['description'] ?? '',
          style: TextStyle(fontSize: 16, color: Colors.grey[700]),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),

        // 2. Logic Branch
        if (_assignmentData!['assignment_type'] == 'VOCAB_TEST') ...[
          _buildVocabTestUI(),
        ] else ...[
          _buildManualUploadUI(),
        ],
      ],
    );
  }

  Widget _buildVocabTestUI() {
    final isCompleted = _assignmentData!['is_completed'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '단어 암기 인증',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: const [
              Icon(Icons.quiz, color: Colors.blue),
              SizedBox(width: 12),
              Expanded(child: Text('앱 내 단어 시험을 통과하면 자동으로 인증됩니다.')),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 54,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isCompleted ? null : _startVocabTest,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(
              isCompleted ? '이미 완료된 과제입니다' : '단어 시험 시작하기',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualUploadUI() {
    final submission = _getSubmission();
    final status = submission?['status']?.toString();
    final isPending = status == 'PENDING';
    final isApproved = status == 'APPROVED';
    final isRejected = status == 'REJECTED';
    final canPick = !isPending && !isApproved;
    final canSubmit = _selectedImages.isNotEmpty && !_isSubmitting && canPick;
    final submissionImageUrls = _getSubmissionImageUrls();
    final teacherComment = submission?['teacher_comment']?.toString();
    final deadline = _assignmentData?['resubmission_deadline']?.toString();

    String statusLabel = '미제출';
    Color statusColor = Colors.grey;
    if (isPending) {
      statusLabel = '검토중';
      statusColor = Colors.orange;
    } else if (isApproved) {
      statusLabel = '승인';
      statusColor = Colors.green;
    } else if (isRejected) {
      statusLabel = '반려';
      statusColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '인증샷 제출',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Text(
                statusLabel,
                style:
                    TextStyle(color: statusColor, fontWeight: FontWeight.bold),
              ),
            ),
            if (deadline != null && deadline.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('재제출 기한: $deadline',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ],
          ],
        ),
        if (isRejected &&
            teacherComment != null &&
            teacherComment.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Text(teacherComment, style: const TextStyle(fontSize: 13)),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _selectedImages.isEmpty && submissionImageUrls.isEmpty
              ? InkWell(
                  onTap: canPick ? _showImageSourceActionSheet : null,
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.add_a_photo, size: 50, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('사진을 선택해 주세요', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    PageView.builder(
                      controller: _previewController,
                      itemCount: _selectedImages.isNotEmpty
                          ? _selectedImages.length
                          : submissionImageUrls.length,
                      onPageChanged: (index) =>
                          setState(() => _currentPreviewIndex = index),
                      itemBuilder: (context, index) {
                        if (_selectedImages.isNotEmpty) {
                          final image = _selectedImages[index];
                          return InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: kIsWeb
                                ? Image.network(image.path, fit: BoxFit.contain)
                                : Image.file(File(image.path),
                                    fit: BoxFit.contain),
                          );
                        }
                        return InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 4.0,
                          child: Image.network(
                            submissionImageUrls[index],
                            fit: BoxFit.contain,
                          ),
                        );
                      },
                    ),
                    if ((_selectedImages.isNotEmpty
                            ? _selectedImages.length
                            : submissionImageUrls.length) >
                        1)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_currentPreviewIndex + 1} / ${_selectedImages.isNotEmpty ? _selectedImages.length : submissionImageUrls.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    if (_selectedImages.isNotEmpty && canPick)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: () =>
                              _removeSelectedImage(_currentPreviewIndex),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.35),
                          ),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedImages.isEmpty
                    ? '선택된 사진 없음'
                    : '선택된 사진 ${_selectedImages.length}장',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
            TextButton.icon(
              onPressed: canPick ? _showImageSourceActionSheet : null,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('사진 추가'),
            ),
          ],
        ),
        // [NEW] Teacher Instructions (Description)
        if (_assignmentData!['description'] != null &&
            _assignmentData!['description'].toString().trim().isNotEmpty) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline,
                        size: 20, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Text(
                      '선생님의 상세 지침',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _assignmentData!['description'],
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: canSubmit ? _submitManual : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isSubmitting
                ? const CircularProgressIndicator(color: Colors.white)
                : Text(isRejected ? '재제출' : '제출',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
