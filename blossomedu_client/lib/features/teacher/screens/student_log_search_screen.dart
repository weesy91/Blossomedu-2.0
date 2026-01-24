import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/services/academy_service.dart';
import '../../../core/constants.dart';

class StudentLogSearchScreen extends StatefulWidget {
  const StudentLogSearchScreen({super.key});

  @override
  State<StudentLogSearchScreen> createState() => _StudentLogSearchScreenState();
}

class _StudentLogSearchScreenState extends State<StudentLogSearchScreen> {
  final AcademyService _academyService = AcademyService();

  bool _isLoading = false;
  List<dynamic> _students = [];
  int? _selectedStudentId;

  // Filters
  DateTimeRange? _dateRange;
  final Set<String> _selectedTypes = {'LOG', 'ASM', 'TEST'}; // Default all

  // Data
  List<dynamic> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
      final students =
          await _academyService.getStudents(scope: 'all'); // 모든 학생 조회?
      if (mounted) {
        setState(() {
          _students = students;
          // select first default? or none
        });
      }
    } catch (e) {
      print('Error loading students: $e');
    }
  }

  Future<void> _searchLogs() async {
    if (_selectedStudentId == null) return;

    setState(() => _isLoading = true);
    try {
      final logs = await _academyService.searchStudentLogs(
        studentId: _selectedStudentId!,
        startDate: _dateRange != null
            ? DateFormat('yyyy-MM-dd').format(_dateRange!.start)
            : null,
        endDate: _dateRange != null
            ? DateFormat('yyyy-MM-dd').format(_dateRange!.end)
            : null,
        types: _selectedTypes.toList(),
      );

      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('검색 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('학생 로그 통합 검색'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. Filter Section
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Student Dropdown
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: '학생 선택',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  value: _selectedStudentId,
                  items: _students.map<DropdownMenuItem<int>>((s) {
                    return DropdownMenuItem(
                      value: s['id'],
                      child: Text('${s['name']} (${s['grade']})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() => _selectedStudentId = val);
                    _searchLogs();
                  },
                ),
                const SizedBox(height: 12),

                // Date Range & Chips
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2023),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            initialDateRange: _dateRange,
                          );
                          if (picked != null) {
                            setState(() => _dateRange = picked);
                            _searchLogs();
                          }
                        },
                        icon: const Icon(Icons.date_range, size: 18),
                        label: Text(
                          _dateRange == null
                              ? '날짜 범위 선택'
                              : '${DateFormat('MM.dd').format(_dateRange!.start)} ~ ${DateFormat('MM.dd').format(_dateRange!.end)}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    if (_dateRange != null)
                      IconButton(
                        onPressed: () {
                          setState(() => _dateRange = null);
                          _searchLogs();
                        },
                        icon: const Icon(Icons.close,
                            size: 18, color: Colors.grey),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildFilterChip('수업일지', 'LOG'),
                    _buildFilterChip('과제', 'ASM'),
                    _buildFilterChip('단어시험', 'TEST'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 2. Result List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _selectedStudentId == null
                    ? const Center(
                        child: Text('학생을 선택해주세요.',
                            style: TextStyle(color: Colors.grey)))
                    : _logs.isEmpty
                        ? const Center(
                            child: Text('검색 결과가 없습니다.',
                                style: TextStyle(color: Colors.grey)))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _logs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return _buildLogCard(_logs[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String code) {
    final isSelected = _selectedTypes.contains(code);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          if (val) {
            _selectedTypes.add(code);
          } else {
            _selectedTypes.remove(code);
          }
        });
        _searchLogs();
      },
      selectedColor: AppColors.primary.withOpacity(0.2),
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> item) {
    final type = item['type'];
    final title = item['title'] ?? '';
    final content = item['content'] ?? '';
    final subInfo = item['sub_info'] ?? '';
    final rawDate = item['raw_date'] ?? '';

    Color color;
    IconData icon;
    String typeLabel;

    switch (type) {
      case 'LOG':
        color = Colors.blue;
        icon = Icons.edit_note;
        typeLabel = '수업';
        break;
      case 'ASM':
        color = Colors.orange;
        icon = Icons.assignment;
        typeLabel = '과제';
        break;
      case 'TEST':
        color = Colors.purple;
        icon = Icons.quiz;
        typeLabel = '시험';
        break;
      default:
        color = Colors.grey;
        icon = Icons.info;
        typeLabel = '기타';
    }

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
          )
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Indicator
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(typeLabel,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text(rawDate,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                        if (item['status'] == 'OVERDUE' ||
                            item['status'] == 'FAIL') ...[
                          const Spacer(),
                          const Icon(Icons.error, size: 16, color: Colors.red),
                        ]
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(content,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (subInfo.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(subInfo,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ]
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
