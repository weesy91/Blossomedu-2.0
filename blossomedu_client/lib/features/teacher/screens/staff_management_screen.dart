import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';
import 'dart:async';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final _academyService = AcademyService();
  final _searchController = TextEditingController();

  List<dynamic> _staffList = [];
  bool _isLoading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchStaff();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchStaff(query: _searchController.text);
    });
  }

  Future<void> _fetchStaff({String query = ''}) async {
    setState(() => _isLoading = true);
    try {
      final data = await _academyService.searchStaff(query: query);
      if (mounted) {
        setState(() {
          _staffList = data;
          _isLoading = false;
        });
      }
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
      appBar: AppBar(title: const Text('강사 계정 관리')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/teacher/staff/register'); // Register Staff
        },
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '이름, 아이디 검색...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _staffList.isEmpty
                    ? const Center(child: Text('검색 결과가 없습니다.'))
                    : ListView.separated(
                        itemCount: _staffList.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final staff = _staffList[index];
                          final name = staff['name'] ?? '이름 없음';
                          final firstChar = name.isNotEmpty ? name[0] : '?';

                          return ListTile(
                            leading: CircleAvatar(
                              child: Text(firstChar),
                            ),
                            title: Text(
                                '$name (${staff['position_display'] ?? '직책 미정'})'),
                            subtitle: Text(
                                '${staff['branch_name'] ?? '지점 미정'} | ${staff['username']}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await context.push(
                                  '/teacher/management/staff/${staff['id']}');
                              _fetchStaff(
                                  query: _searchController
                                      .text); // Refresh list on return
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
