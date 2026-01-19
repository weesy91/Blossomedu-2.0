import 'package:flutter/material.dart';
import '../../../../core/services/academy_service.dart';
import '../../../../core/services/vocab_service.dart';

class SystemManagementScreen extends StatefulWidget {
  const SystemManagementScreen({super.key});

  @override
  State<SystemManagementScreen> createState() => _SystemManagementScreenState();
}

class _SystemManagementScreenState extends State<SystemManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _academyService = AcademyService();
  final _vocabService = VocabService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('시스템 설정 (메타데이터)'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '지점 관리'),
            Tab(text: '학교 관리'),
            Tab(text: '출판사 관리'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _BranchList(service: _academyService),
          _SchoolList(service: _academyService),
          _PublisherList(service: _vocabService),
        ],
      ),
    );
  }
}

class _BranchList extends StatefulWidget {
  final AcademyService service;
  const _BranchList({required this.service});

  @override
  State<_BranchList> createState() => _BranchListState();
}

class _BranchListState extends State<_BranchList> {
  List<dynamic> _branches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await widget.service.getBranches();
      if (mounted)
        setState(() {
          _branches = data;
          _isLoading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: _branches.length,
        itemBuilder: (_, i) {
          final branch = _branches[i];
          return ListTile(
            title: Text(branch['name']),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showAddDialog(context, branch: branch),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteBranch(branch['id']),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteBranch(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.service.deleteBranch(id);
        _fetch();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showAddDialog(BuildContext context, {Map<String, dynamic>? branch}) {
    String name = branch?['name'] ?? '';
    bool isEdit = branch != null;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? '지점 수정' : '지점 추가'),
        content: TextFormField(
          initialValue: name,
          decoration: const InputDecoration(labelText: '지점명'),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              if (name.isEmpty) return;
              try {
                if (isEdit) {
                  await widget.service
                      .updateBranch(branch['id'], {'name': name});
                } else {
                  await widget.service.createBranch({'name': name});
                }

                if (mounted) {
                  Navigator.pop(context);
                  _fetch();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: Text(isEdit ? '수정' : '추가'),
          ),
        ],
      ),
    );
  }
}

class _SchoolList extends StatefulWidget {
  final AcademyService service;
  const _SchoolList({required this.service});

  @override
  State<_SchoolList> createState() => _SchoolListState();
}

class _SchoolListState extends State<_SchoolList> {
  List<dynamic> _schools = [];
  List<dynamic> _branches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final schoolsData = await widget.service.getSchools();
      final branchesData = await widget.service.getBranches();
      if (mounted)
        setState(() {
          _schools = schoolsData;
          _branches = branchesData;
          _isLoading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: _schools.length,
        itemBuilder: (_, i) {
          final school = _schools[i];
          // Determine branches text
          final associatedBranches =
              (school['branches_details'] as List<dynamic>?)
                      ?.map((b) => b['name'])
                      .join(', ') ??
                  '';

          return ListTile(
            title: Text(school['name']),
            subtitle: Text(
                associatedBranches.isEmpty ? '분원 미지정' : associatedBranches),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showAddDialog(context, school: school),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteSchool(school['id']),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteSchool(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.service.deleteSchool(id);
        _fetch();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showAddDialog(BuildContext context, {Map<String, dynamic>? school}) {
    String name = school?['name'] ?? '';
    // Initial branches
    List<int> selectedBranchIds = [];
    if (school != null && school['branches'] != null) {
      selectedBranchIds = List<int>.from(school['branches']);
    }

    bool isEdit = school != null;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(isEdit ? '학교 수정' : '학교 추가'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: name,
                    decoration: const InputDecoration(labelText: '학교명'),
                    onChanged: (v) => name = v,
                  ),
                  const SizedBox(height: 16),
                  const Text('관할 분원 선택:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.maxFinite,
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: _branches.map((b) {
                          final bId = b['id'] as int;
                          final isSelected = selectedBranchIds.contains(bId);
                          return FilterChip(
                            label: Text(b['name']),
                            selected: isSelected,
                            onSelected: (bool selected) {
                              setState(() {
                                if (selected) {
                                  selectedBranchIds.add(bId);
                                } else {
                                  selectedBranchIds.remove(bId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소')),
              TextButton(
                onPressed: () async {
                  if (name.isEmpty) return;
                  try {
                    Map<String, dynamic> data = {
                      'name': name,
                      'branches': selectedBranchIds
                    };

                    if (isEdit) {
                      await widget.service.updateSchool(school['id'], data);
                    } else {
                      await widget.service.createSchool(data);
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                      _fetch();
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: Text(isEdit ? '수정' : '추가'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PublisherList extends StatefulWidget {
  final VocabService service;
  const _PublisherList({required this.service});

  @override
  State<_PublisherList> createState() => _PublisherListState();
}

class _PublisherListState extends State<_PublisherList> {
  List<dynamic> _publishers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await widget.service.getPublishers();
      if (mounted) {
        setState(() {
          _publishers = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        itemCount: _publishers.length,
        itemBuilder: (_, i) {
          final publisher = _publishers[i];
          return ListTile(
            title: Text(publisher['name']),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () =>
                      _showAddDialog(context, publisher: publisher),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deletePublisher(publisher['id']),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _deletePublisher(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.service.deletePublisher(id);
        _fetch();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  void _showAddDialog(BuildContext context, {Map<String, dynamic>? publisher}) {
    String name = publisher?['name'] ?? '';
    final isEdit = publisher != null;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? '출판사 수정' : '출판사 추가'),
        content: TextFormField(
          initialValue: name,
          decoration: const InputDecoration(labelText: '출판사명'),
          onChanged: (v) => name = v,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          TextButton(
            onPressed: () async {
              if (name.isEmpty) return;
              try {
                if (isEdit) {
                  await widget.service.updatePublisher(publisher['id'], name);
                } else {
                  await widget.service.createPublisher(name);
                }
                if (mounted) {
                  Navigator.pop(context);
                  _fetch();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: Text(isEdit ? '수정' : '추가'),
          ),
        ],
      ),
    );
  }
}
