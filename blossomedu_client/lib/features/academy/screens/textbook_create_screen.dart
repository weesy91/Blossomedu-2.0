import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class TextbookCreateScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final String? initialCategory;

  const TextbookCreateScreen(
      {super.key, this.initialData, this.initialCategory});

  @override
  State<TextbookCreateScreen> createState() => _TextbookCreateScreenState();
}

class _TextbookCreateScreenState extends State<TextbookCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _academyService = AcademyService();

  late TextEditingController _titleController;
  late TextEditingController _publisherController;
  late TextEditingController _levelController;
  late TextEditingController _totalUnitsController; // [NEW]
  late TextEditingController _otLinkController; // [NEW] OT Link
  late String _selectedCategory;
  bool _hasOt = false; // [NEW]

  // Units
  List<Map<String, dynamic>> _units = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    _titleController = TextEditingController(text: data?['title'] ?? '');
    _publisherController =
        TextEditingController(text: data?['publisher'] ?? '');
    _levelController = TextEditingController(text: data?['level'] ?? '');
    _totalUnitsController = TextEditingController(
        text: (data?['total_units'] ?? '0').toString()); // [NEW]
    _selectedCategory = data?['category'] ?? widget.initialCategory ?? 'SYNTAX';
    _hasOt = data?['has_ot'] ?? false; // [NEW]

    _otLinkController = TextEditingController(); // Top-level init

    if (data != null && data['units'] != null) {
      final uList = List<Map<String, dynamic>>.from(data['units']);
      // [NEW] Extract OT (Unit 0)
      final otIndex = uList.indexWhere((u) => u['unit_number'] == 0);
      if (otIndex != -1) {
        _otLinkController.text = uList[otIndex]['link_url'] ?? '';
        uList.removeAt(otIndex);
        // Force sync has_ot if unit exists
        if (!_hasOt) _hasOt = true;
      }
      _units = uList;
    } else {
      // Initialize with 0 units or maybe 1?
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _publisherController.dispose();
    _levelController.dispose();
    _totalUnitsController.dispose(); // [NEW]
    _otLinkController.dispose(); // [NEW]
    super.dispose();
  }

  void _addUnit() {
    setState(() {
      _units.add({
        'unit_number': _units.length + 1,
        'link_url': '',
      });
    });
  }

  void _removeUnit(int index) {
    setState(() {
      _units.removeAt(index);
      for (int i = 0; i < _units.length; i++) {
        _units[i]['unit_number'] = i + 1;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final payload = {
        'title': _titleController.text,
        'publisher': _publisherController.text,
        'level': _levelController.text,
        'category': _selectedCategory,
        'total_units': int.tryParse(_totalUnitsController.text) ??
            _units.length, // [NEW] Prefer explicit input
        'has_ot': _hasOt, // [NEW]
        'units': [
          if (_hasOt) {'unit_number': 0, 'link_url': _otLinkController.text},
          ..._units
        ],
      };

      if (widget.initialData != null) {
        // Update
        await _academyService.updateTextbook(
            widget.initialData!['id'], payload);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('수정되었습니다.')));
        }
      } else {
        // Create
        await _academyService.createTextbook(payload);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('등록되었습니다.')));
        }
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('교재 삭제'),
        content: const Text('정말 삭제하시겠습니까?'),
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

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });
    try {
      await _academyService.deleteTextbook(widget.initialData!['id']);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete Error: $e')));
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Categories
    final categories = {
      'SYNTAX': '구문',
      'READING': '독해',
      'GRAMMAR': '어법',
      'LISTENING': '듣기',
      'SCHOOL_EXAM': '내신'
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initialData == null ? '교재 등록' : '교재 수정'),
        actions: [
          if (widget.initialData != null)
            IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(labelText: '카테고리'),
                    items: categories.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedCategory = val!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: '교재명'),
                    validator: (v) => v!.isEmpty ? '필수 입력입니다.' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _publisherController,
                          decoration: const InputDecoration(labelText: '출판사'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _levelController,
                          decoration:
                              const InputDecoration(labelText: '레벨 (예: 고1)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _totalUnitsController,
                    decoration: const InputDecoration(
                      labelText: '총 강/챕터 수 (숫자)',
                      helperText:
                          '진도율 그래프의 기준이 됩니다.', // Denominator for progress
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('OT 강의 포함'),
                    subtitle: const Text('체크 시 수업 일지에서 OT 선택이 가능해집니다.'),
                    value: _hasOt,
                    onChanged: (val) => setState(() => _hasOt = val),
                  ),
                  if (_hasOt)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: TextFormField(
                        controller: _otLinkController,
                        decoration: const InputDecoration(
                          labelText: 'OT 강의 링크 (URL)',
                          prefixIcon: Icon(Icons.link),
                          helperText: 'OT는 0강으로 저장됩니다.',
                        ),
                      ),
                    ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('단원(Unit) 및 강의 링크',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: _addUnit,
                        icon: const Icon(Icons.add),
                        label: const Text('추가'),
                      ),
                    ],
                  ),
                  ..._units.asMap().entries.map((entry) {
                    final index = entry.key;
                    final unit = entry.value;
                    return Card(
                      key: ValueKey(index), // Note: simplistic key
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            Text('${unit['unit_number']}강',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                initialValue: unit['link_url'],
                                decoration: const InputDecoration(
                                  labelText: 'Link URL',
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  _units[index]['link_url'] = val;
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey),
                              onPressed: () => _removeUnit(index),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('저장'),
                  ),
                ],
              ),
            ),
    );
  }
}
