import 'package:flutter/material.dart';
import '../../../core/services/vocab_service.dart';

class TeacherVocabDetailScreen extends StatefulWidget {
  final int bookId;
  final String bookTitle;

  const TeacherVocabDetailScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  @override
  State<TeacherVocabDetailScreen> createState() =>
      _TeacherVocabDetailScreenState();
}

class _TeacherVocabDetailScreenState extends State<TeacherVocabDetailScreen> {
  final VocabService _vocabService = VocabService();
  List<dynamic> _words = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    setState(() => _isLoading = true);
    try {
      final words = await _vocabService.getWords(widget.bookId);
      setState(() {
        _words = words;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('단어 로딩 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _words.isEmpty
              ? const Center(child: Text('등록된 단어가 없습니다.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _words.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final word = _words[index];
                    return ListTile(
                      title: Text(
                        word['english'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          // New Structured Display (v. meaning / n. meaning)
                          if (word['meaning_groups'] != null &&
                              word['meaning_groups'] is List)
                            ...(word['meaning_groups'] as List)
                                .map<Widget>((group) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width:
                                                24, // Fixed width for alignment
                                            alignment: Alignment.center,
                                            margin: const EdgeInsets.only(
                                                right: 8, top: 1),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              group['pos'].toString(),
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              group['meaning'].toString(),
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList()
                          else
                            // Fallback Legacy Display
                            Row(
                              children: [
                                if (word['pos'] is List)
                                  ...(word['pos'] as List)
                                      .map<Widget>((p) => Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            margin:
                                                const EdgeInsets.only(right: 4),
                                            decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(4)),
                                            child: Text(p.toString(),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ))
                                      .toList(),
                                Expanded(
                                    child: Text(word['korean'] ?? '',
                                        style: const TextStyle(fontSize: 14))),
                              ],
                            ),

                          if (word['example_sentence'] != null &&
                              word['example_sentence'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Ex: ${word['example_sentence']}',
                                style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic),
                              ),
                            ),
                        ],
                      ),
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.withOpacity(0.1),
                        child: Text(
                          '${word['number'] ?? index + 1}',
                          style:
                              const TextStyle(color: Colors.teal, fontSize: 12),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit,
                                size: 20, color: Colors.blue),
                            onPressed: () => _showEditDialog(word),
                          ),
                          // Delete not implemented in backend yet or risky?
                          // Let's hide delete for now or implement if needed. User asked for "correction".
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  void _showEditDialog(Map<String, dynamic> word) {
    final engCtrl = TextEditingController(text: word['english']);
    final korCtrl = TextEditingController(text: word['korean']);
    final exCtrl = TextEditingController(text: word['example_sentence']);
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('단어 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: engCtrl,
                decoration: const InputDecoration(labelText: '영어'),
              ),
              TextField(
                controller: korCtrl,
                decoration: const InputDecoration(labelText: '뜻'),
              ),
              TextField(
                controller: exCtrl,
                decoration: const InputDecoration(labelText: '예문'),
              ),
              if (isSaving) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('💡 품사 수동 지정 (태그 목록)',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue)),
                    SizedBox(height: 4),
                    Text('뜻 앞에 아래 영어 태그를 붙이면 품사가 강제로 적용됩니다.',
                        style: TextStyle(fontSize: 11, color: Colors.black87)),
                    SizedBox(height: 4),
                    Text('한글 태그(명., 동. 등)는 지원하지 않습니다.',
                        style: TextStyle(fontSize: 11, color: Colors.black87)),
                    SizedBox(height: 6),
                    Text('• n.(명사)  v.(동사)  a.(형용사)  ad.(부사)',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    Text('• prep.(전치사)  conj.(접속사)  pron.(대명사)',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    Text('• vi.(자동사)  vt.(타동사)',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    SizedBox(height: 6),
                    Text('예시: "prep. ~을 제외하고"',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
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
                      setDialogState(() => isSaving = true);
                      try {
                        final updatedWord =
                            await _vocabService.updateWord(word['id'], {
                          'english': engCtrl.text,
                          'korean': korCtrl.text,
                          'example_sentence': exCtrl.text,
                        });

                        if (mounted) {
                          // Update local state to prevent scroll reset
                          setState(() {
                            final index =
                                _words.indexWhere((w) => w['id'] == word['id']);
                            if (index != -1) {
                              _words[index] = updatedWord;
                            }
                          });

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('수정되었습니다.')),
                          );
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
        ),
      ),
    );
  }
}
