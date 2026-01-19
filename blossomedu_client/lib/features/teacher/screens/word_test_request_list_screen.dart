import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/vocab_service.dart';

class WordTestRequestListScreen extends StatefulWidget {
  const WordTestRequestListScreen({super.key});

  @override
  State<WordTestRequestListScreen> createState() =>
      _WordTestRequestListScreenState();
}

class _WordTestRequestListScreenState extends State<WordTestRequestListScreen> {
  final VocabService _vocabService = VocabService();
  List<dynamic> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    try {
      // [FILTER] Show only pending requests
      final data =
          await _vocabService.getTeacherTestRequests(pendingOnly: true);
      setState(() {
        _requests = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로딩 실패: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('단어 채점 대기 목록'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchRequests();
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text("처리할 요청이 없습니다."))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _requests.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final apiItem = _requests[index];
                    // Map API to UI format
                    final total = apiItem['details']?.length ?? 30; // fallback
                    final wrong = apiItem['wrong_count'] ?? 0;
                    final correct = total - wrong;

                    final details = apiItem['details'] as List? ?? [];
                    final pendingCount = details
                        .where((d) =>
                            d['is_correction_requested'] == true &&
                            d['is_resolved'] == false)
                        .length;

                    final item = {
                      'id': apiItem['id'].toString(),
                      'student': apiItem['student_name'] ?? 'Unknown',
                      'book': apiItem['book_title'] ?? 'Unknown',
                      'range': apiItem['test_range'] ?? '',
                      'submittedAt':
                          apiItem['created_at']?.toString().substring(11, 16) ??
                              '', // Extract HH:MM
                      'attempt': 1, // API doesn't have attempt count yet
                      'score': '$correct/$total',
                      'pendingCount': pendingCount,
                      'isPassed': (apiItem['score'] ?? 0) >= 90,
                    };

                    return _buildRequestCard(context, item);
                  },
                ),
    );
  }

  Widget _buildRequestCard(BuildContext context, Map<String, dynamic> item) {
    return InkWell(
      onTap: () async {
        // [REFRESH] Await return and refresh
        await context.push('/teacher/word/review/${item['id']}');
        _fetchRequests();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Name + Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.orange.shade100,
                        child: Text(item['student'][0],
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item['student'],
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '오늘 ${item['submittedAt']}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Body: Book Info + Attempt
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('시도 ${item['attempt']}회차',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${item['book']} - ${item['range']}',
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // Footer: Score + Pending Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('현재 점수: ',
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                    Text(
                      item['score'],
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                // [NEW] Badge Logic
                if (item['isPassed'] == true)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green),
                        SizedBox(width: 4),
                        Text('이미 통과됨',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ],
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.rate_review,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '이의제기 ${item['pendingCount']}건',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
