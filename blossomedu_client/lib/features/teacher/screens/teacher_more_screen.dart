import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/user_provider.dart';

class TeacherMoreScreen extends StatelessWidget {
  const TeacherMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Current user for role check
    final user = context.watch<UserProvider>().user;
    final pos = user?.position; // 'TEACHER', 'VICE', 'PRINCIPAL', 'TA'
    final isSuper = user?.isSuperuser == true;

    // Helper to check roles
    bool hasStudentAccess() {
      if (isSuper) return true;
      return ['TA', 'VICE', 'PRINCIPAL'].contains(pos);
    }

    bool hasAdminAccess() {
      if (isSuper) return true;
      return ['PRINCIPAL', 'VICE'].contains(pos);
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50, // Gray Background
      appBar: AppBar(
        title: const Text('더보기'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // No back button - this is a tab
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              // 1. Profile Header
              _buildProfileHeader(user, pos, isSuper),

              const SizedBox(height: 20),

              // 2. Menu Sections
              if (hasStudentAccess())
                _buildMenuSection('학생 관리', [
                  _MenuItem(
                    icon: Icons.person_add,
                    title: '학생 등록/퇴원 관리',
                    subtitle: '신규 학생 등록 및 배정',
                    onTap: () => context.push('/teacher/student/register'),
                  ),
                  _MenuItem(
                    icon: Icons.manage_accounts,
                    title: '학생 계정 관리',
                    subtitle: '전체 학생 검색 및 조회',
                    onTap: () => context.push('/teacher/management/students'),
                  ),
                  _MenuItem(
                    icon: Icons.assignment_turned_in, // Good icon for reports
                    title: '성적표 발송 및 관리',
                    subtitle: '월간 성적표 생성 및 공유',
                    onTap: () => context.push('/teacher/management/reports'),
                  ),
                  _MenuItem(
                    icon: Icons.history,
                    title: '학생 로그 검색',
                    subtitle: '수업, 과제, 시험 통합 히스토리',
                    onTap: () => context.push('/teacher/management/log-search'),
                  ),
                ]),

              if (hasStudentAccess())
                _buildMenuSection('학습 관리', [
                  _MenuItem(
                    icon: Icons.menu_book,
                    title: '교재(Textbook) 관리',
                    subtitle: '구문/독해/어법/내신 교재 등록',
                    onTap: () => context.push('/academy/textbooks'),
                  ),
                  _MenuItem(
                    icon: Icons.abc,
                    title: '단어장(Vocab) 관리',
                    subtitle: '단어장 CSV 등록 및 관리',
                    onTap: () => context.push('/teacher/vocab'),
                  ),
                  _MenuItem(
                    icon: Icons.emoji_events,
                    title: '이벤트 단어장 관리',
                    subtitle: '랭킹 이벤트 단어장/기간 설정',
                    onTap: () => context.push('/teacher/vocab/events'),
                  ),
                ]),

              if (hasAdminAccess())
                _buildMenuSection('강사 관리', [
                  _MenuItem(
                    icon: Icons.person_add_alt_1,
                    title: '강사 계정 등록',
                    subtitle: '신규 선생님 등록',
                    onTap: () => context.push('/teacher/staff/register'),
                  ),
                  _MenuItem(
                    icon: Icons.dashboard_customize,
                    title: '담당 강사 관리 (일일 현황)', // [NEW]
                    onTap: () => context.push('/teacher/daily-status'),
                  ),
                  _MenuItem(
                    icon: Icons.supervisor_account,
                    title: '강사 계정 관리',
                    subtitle: '전체 강사 검색 및 조회',
                    onTap: () => context.push('/teacher/management/staff'),
                  ),
                ]),

              if (hasAdminAccess())
                _buildMenuSection('시스템 설정 (Admin)', [
                  _MenuItem(
                    icon: Icons.settings,
                    title: '지점/학교 메타데이터 관리',
                    subtitle: '지점 및 학교 정보 등록/수정',
                    onTap: () => context.push('/teacher/management/system'),
                  ),
                  _MenuItem(
                    icon: Icons.campaign,
                    title: '학원 공지사항 관리',
                    subtitle: '학원 공지사항 등록 및 배너 관리',
                    onTap: () => context.push('/teacher/announcements'),
                  ),
                  _MenuItem(
                    icon: Icons.touch_app, // Kiosk Icon
                    title: '등하원 키오스크 모드',
                    subtitle: '학생용 등하원 체크 화면 실행',
                    onTap: () => context.push('/attendance/kiosk'),
                  ),
                ]),

              const SizedBox(height: 10),

              // Logout Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextButton(
                  onPressed: () {
                    context.read<UserProvider>().logout();
                    context.go('/login');
                  },
                  child:
                      const Text('로그아웃', style: TextStyle(color: Colors.red)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(dynamic user, String? pos, bool isSuper) {
    final rawName = user?.name ?? '';
    final displayName =
        rawName.trim().isNotEmpty ? rawName : (user?.username ?? '선생님');
    final displayInitial = displayName.isNotEmpty ? displayName[0] : 'T';
    return Container(
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
            backgroundColor: Colors.indigo.withOpacity(0.1),
            child: Text(
              displayInitial,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (isSuper)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('ADMIN',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.red,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${user?.username ?? ''} | ${pos ?? '직책없음'}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection(String title, List<_MenuItem> items) {
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                )
              ]),
          child: Column(
            children: items.map((item) {
              int idx = items.indexOf(item);
              return Column(
                children: [
                  if (idx > 0)
                    Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Colors.grey.shade100,
                        indent: 16,
                        endIndent: 16),
                  ListTile(
                    leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.indigo.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(item.icon, color: Colors.indigo, size: 20)),
                    title: Text(item.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    subtitle: item.subtitle != null
                        ? Text(item.subtitle!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey))
                        : null,
                    trailing: const Icon(Icons.chevron_right,
                        color: Colors.grey, size: 18),
                    onTap: item.onTap,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  _MenuItem(
      {required this.icon,
      required this.title,
      this.subtitle,
      required this.onTap});
}
