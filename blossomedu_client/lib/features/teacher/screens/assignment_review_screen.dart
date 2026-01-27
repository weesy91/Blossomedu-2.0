import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../core/services/academy_service.dart';

class AssignmentReviewScreen extends StatefulWidget {
  final String assignmentId;

  const AssignmentReviewScreen({
    required this.assignmentId,
    super.key,
  });

  @override
  State<AssignmentReviewScreen> createState() => _AssignmentReviewScreenState();
}

class _AssignmentReviewScreenState extends State<AssignmentReviewScreen> {
  final AcademyService _academyService = AcademyService();
  final TextEditingController _feedbackController = TextEditingController();
  final PageController _pageController = PageController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  int _currentImageIndex = 0;
  Map<String, dynamic>? _assignmentData;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    try {
      final data = await _academyService
          .getAssignmentDetail(int.parse(widget.assignmentId));
      if (mounted) {
        setState(() {
          _assignmentData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: $e')),
      );
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

  List<String> _getSubmissionImageUrls(Map<String, dynamic>? submission) {
    if (submission == null) return [];
    final List<String> urls = [];
    final images = submission['images'];
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
      final raw = submission['image_url'] ?? submission['image'];
      final resolved = _resolveImageUrl(raw?.toString());
      if (resolved.isNotEmpty) urls.add(resolved);
    }
    return urls;
  }

  void _submitReview(bool isApproved) {
    if (isApproved) {
      _processSubmission(true, _feedbackController.text);
      return;
    }

    DateTime selectedDeadline = DateTime.now().add(const Duration(days: 1));
    final dueDateRaw = _assignmentData?['due_date']?.toString();
    if (dueDateRaw != null && dueDateRaw.isNotEmpty) {
      try {
        final parsed = DateTime.parse(dueDateRaw);
        selectedDeadline = DateTime(parsed.year, parsed.month, parsed.day);
      } catch (_) {}
    }
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (selectedDeadline.isBefore(todayDate)) {
      selectedDeadline = todayDate;
    }
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          final reasonController =
              TextEditingController(text: _feedbackController.text);
          return AlertDialog(
            title: const Text('재제출 요청'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '사유와 기한을 입력해주세요.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    hintText: '반려 사유',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text('재제출 기한',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDeadline,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDeadline = date);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${selectedDeadline.year}.${selectedDeadline.month}.${selectedDeadline.day}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.indigo),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () {
                  Navigator.pop(context);
                  _processSubmission(
                    false,
                    reasonController.text,
                    deadline: selectedDeadline,
                  );
                },
                child: const Text('요청 보내기'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _processSubmission(
    bool isApproved,
    String feedback, {
    DateTime? deadline,
  }) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      await _academyService.reviewAssignment(
        int.parse(widget.assignmentId),
        isApproved: isApproved,
        comment: feedback,
        resubmissionDeadline: deadline,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isApproved ? '승인 처리되었습니다.' : '재제출 요청을 보냈습니다.')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('검토 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_assignmentData == null) {
      return const Scaffold(
        body: Center(child: Text('과제를 찾을 수 없습니다.')),
      );
    }

    final submission = _getSubmission();
    final status = submission?['status']?.toString();
    final canReview = status == 'PENDING' && !_isSubmitting;
    final images = _getSubmissionImageUrls(submission);

    final studentName = _assignmentData?['student_name']?.toString() ?? '';
    final title = _assignmentData?['title']?.toString() ?? 'Assignment';
    final submittedAt = submission?['submitted_at']?.toString() ?? '';

    String statusLabel = '미제출';
    Color statusColor = Colors.grey;
    if (status == 'PENDING') {
      statusLabel = '검토중';
      statusColor = Colors.orange;
    } else if (status == 'APPROVED') {
      statusLabel = '승인';
      statusColor = Colors.green;
    } else if (status == 'REJECTED') {
      statusLabel = '반려';
      statusColor = Colors.red;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(studentName.isNotEmpty ? '$studentName 과제 검토' : '과제 검토'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.grey[100],
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                          submittedAt.isNotEmpty
                              ? '제출: $submittedAt'
                              : '제출 내역 없음',
                          style:
                              TextStyle(color: Colors.grey[700], fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: images.isEmpty
                ? const Center(child: Text('제출된 이미지가 없습니다.'))
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      PageView.builder(
                        controller: _pageController,
                        physics: const BouncingScrollPhysics(),
                        itemCount: images.length,
                        onPageChanged: (index) =>
                            setState(() => _currentImageIndex = index),
                        itemBuilder: (context, index) {
                          return InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Image.network(
                              images[index],
                              fit: BoxFit.contain,
                              loadingBuilder: (ctx, child, loading) {
                                if (loading == null) return child;
                                return const Center(
                                    child: CircularProgressIndicator());
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image,
                                          size: 50, color: Colors.grey),
                                      SizedBox(height: 8),
                                      Text('이미지 로딩 실패',
                                          style: TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      if (_currentImageIndex > 0)
                        Positioned(
                          left: 16,
                          child: IconButton(
                            onPressed: () {
                              _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut);
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withOpacity(0.3),
                              hoverColor: Colors.black.withOpacity(0.5),
                              padding: const EdgeInsets.all(12),
                            ),
                            icon: const Icon(Icons.arrow_back_ios_new,
                                color: Colors.white, size: 24),
                          ),
                        ),
                      if (_currentImageIndex < images.length - 1)
                        Positioned(
                          right: 16,
                          child: IconButton(
                            onPressed: () {
                              _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut);
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withOpacity(0.3),
                              hoverColor: Colors.black.withOpacity(0.5),
                              padding: const EdgeInsets.all(12),
                            ),
                            icon: const Icon(Icons.arrow_forward_ios,
                                color: Colors.white, size: 24),
                          ),
                        ),
                      Positioned(
                        bottom: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_currentImageIndex + 1} / ${images.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _feedbackController,
                  decoration: const InputDecoration(
                    labelText: '코멘트(선택)',
                    hintText: '간단한 메모',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.replay, color: Colors.orange),
                        label: const Text('재제출 요청',
                            style: TextStyle(color: Colors.orange)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.orange),
                        ),
                        onPressed:
                            canReview ? () => _submitReview(false) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('승인'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canReview ? Colors.green : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        onPressed: canReview ? () => _submitReview(true) : null,
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
