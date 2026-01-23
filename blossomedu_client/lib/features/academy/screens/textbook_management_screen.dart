import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class TextbookManagementScreen extends StatefulWidget {
  const TextbookManagementScreen({super.key});

  @override
  State<TextbookManagementScreen> createState() =>
      _TextbookManagementScreenState();
}

class _TextbookManagementScreenState extends State<TextbookManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // final _academyService = AcademyService(); // Removed unused
  int _refreshKey = 0; // Forces rebuild of child widgets

  final List<String> _categories = [
    'SYNTAX',
    'READING',
    'GRAMMAR',
    'LISTENING',
    'SCHOOL_EXAM'
  ];
  final List<String> _tabLabels = ['구문', '독해', '어법', '듣기', '내신'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('교재 관리'),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _categories.map((category) {
          // Key change forces complete rebuild of the widget, triggering initState -> _loadBooks
          return _TextbookListFunction(
              key: ValueKey('${category}_$_refreshKey'), category: category);
        }).toList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final currentCategory = _categories[_tabController.index];
          await context.push('/academy/textbook/create',
              extra: {'category': currentCategory});
          // Refresh after return
          setState(() {
            _refreshKey++;
          });
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TextbookListFunction extends StatefulWidget {
  final String category;
  const _TextbookListFunction({super.key, required this.category});

  @override
  State<_TextbookListFunction> createState() => _TextbookListFunctionState();
}

class _TextbookListFunctionState extends State<_TextbookListFunction> {
  final _academyService = AcademyService();
  late Future<List<Map<String, dynamic>>> _booksFuture;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void didUpdateWidget(covariant _TextbookListFunction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      _loadBooks();
    }
  }

  void _loadBooks() {
    _booksFuture = _academyService.getTextbooks(category: widget.category);
  }

  Future<void> _refresh() async {
    setState(() {
      _loadBooks();
    });
    await _booksFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _booksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final books = snapshot.data ?? [];

        if (books.isEmpty) {
          return const Center(child: Text('등록된 교재가 없습니다.'));
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return ListTile(
                title: Text(book['title'] ?? 'No Title'),
                subtitle: Text(
                    '${book['publisher'] ?? ''} | ${book['level'] ?? ''} | ${book['total_units'] ?? 0}강'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  await context.push('/academy/textbook/edit/${book['id']}',
                      extra: book);
                  _refresh(); // Internal refresh still useful for edits
                },
              );
            },
          ),
        );
      },
    );
  }
}
