import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../core/services/vocab_service.dart';

class StudentBookSelectionScreen extends StatefulWidget {
  const StudentBookSelectionScreen({super.key});

  @override
  State<StudentBookSelectionScreen> createState() =>
      _StudentBookSelectionScreenState();
}

class _StudentBookSelectionScreenState
    extends State<StudentBookSelectionScreen> {
  final VocabService _vocabService = VocabService();
  bool _isLoading = true;
  List<dynamic> _books = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableBooks();
  }

  Future<void> _loadAvailableBooks() async {
    try {
      final books = await _vocabService.getAvailableBooks();
      if (mounted) {
        setState(() {
          _books = books;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('단어장 목록 로드 실패: $e')),
        );
      }
    }
  }

  Future<void> _addBook(dynamic book) async {
    try {
      await _vocabService.subscribeToBook(book['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내 단어장에 추가되었습니다! 📚')),
        );
        // Remove from list or mark as added (for now just pop with refresh signal)
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('추가 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('새 교재 추가'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _books.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final book = _books[index];
                    return _buildBookCard(book);
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.library_books_outlined,
              size: 60, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('추가할 수 있는 교재가 없습니다.',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('모든 교재를 이미 추가했거나 등록된 교재가 없습니다.',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBookCard(Map<String, dynamic> book) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.book, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book['title'] ?? '제목 없음',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${book['publisher_name'] ?? 'Unknown'} • 총 ${book['total_days'] ?? book['totalDays'] ?? 0}일차', // totalDays key mismatch potential? Service returns snake_case usually if API serializer uses ModelSerializer.
                    // Wait, serializers usually default to field names. WordBookSerializer has totalDays?
                    // Let's check WordBookSerializer.
                    // Assuming 'totalDays' or 'total_days'. API default is snake_case unless camelCase specified.
                    // I'll check serializer later. Safe fallback.
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _addBook(book),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }
}
