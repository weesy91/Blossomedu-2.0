import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/providers/user_provider.dart';

class MyPageScreen extends StatelessWidget {
  const MyPageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>().user;
    final rawName = user?.name ?? '';
    final displayName =
        rawName.trim().isNotEmpty ? rawName : (user?.username ?? '학생');
    final displayInitial = displayName.isNotEmpty ? displayName[0] : 'S';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              // 1. Profile Header
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ]),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Text(
                        displayInitial,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            user?.username ?? 'student01',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 2. Stats Dashboard
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.calendar_today,
                      title: '출석률',
                      value: '95%',
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 16),
                    _buildStatCard(
                      icon: Icons.emoji_events,
                      title: '단어 평균',
                      value: '88점',
                      color: Colors.orange,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // 3. Menu Options
              _buildMenuSection(title: '학습 관리', items: [
                _MenuItem(
                    icon: Icons.history,
                    title: '학습기록 확인',
                    onTap: () => context.push('/student/records')),
                _MenuItem(
                    icon: Icons.bar_chart,
                    title: '월간 리포트',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('월간 리포트'),
                          content: const Text(
                              '현재 구현 중인 기능입니다.\n빠른 시일 내에 제공될 예정입니다.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('확인')),
                          ],
                        ),
                      );
                    }),
              ]),

              _buildMenuSection(title: '앱 설정', items: [
                _MenuItem(
                    icon: Icons.notifications,
                    title: '알림 설정',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('알림 설정'),
                          content: const Text(
                              '현재 구현 중인 기능입니다.\n빠른 시일 내에 제공될 예정입니다.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('확인')),
                          ],
                        ),
                      );
                    }),
                _MenuItem(
                    icon: Icons.lock,
                    title: '비밀번호 변경',
                    onTap: () {
                      _showPasswordChangeDialog(context);
                    }),
                _MenuItem(
                    icon: Icons.info_outline,
                    title: '앱 정보',
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('BlossomEdu'),
                          content: const Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('버전: Alpha 0.9.1',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(height: 8),
                              Text('영어 학습 관리 앱'),
                              SizedBox(height: 4),
                              Text('© 2025 BlossomEdu'),
                              SizedBox(height: 12),
                              Text('⚠️ 현재 Alpha 테스트 중입니다.',
                                  style: TextStyle(
                                      color: Colors.orange, fontSize: 12)),
                            ],
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('확인')),
                          ],
                        ),
                      );
                    }),
              ]),

              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  context.read<UserProvider>().logout();
                  context.go('/login');
                },
                child: const Text('로그아웃', style: TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
      {required IconData icon,
      required String title,
      required String value,
      required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection(
      {required String title, required List<_MenuItem> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: items.map((item) {
              return ListTile(
                leading: Icon(item.icon, color: Colors.grey.shade700, size: 22),
                title: Text(item.title, style: const TextStyle(fontSize: 15)),
                trailing: const Icon(Icons.chevron_right,
                    color: Colors.grey, size: 20),
                onTap: item.onTap,
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  void _showPasswordChangeDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '현재 비밀번호',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '새 비밀번호',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '새 비밀번호 확인',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('새 비밀번호가 일치하지 않습니다.')),
                );
                return;
              }
              if (newPasswordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('비밀번호는 6자 이상이어야 합니다.')),
                );
                return;
              }
              // TODO: Implement actual password change API call
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('비밀번호가 변경되었습니다.')),
              );
            },
            child: const Text('변경'),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  _MenuItem({required this.icon, required this.title, required this.onTap});
}
