import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/academy_service.dart';

class TeacherMainScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const TeacherMainScaffold({
    required this.navigationShell,
    super.key,
  });

  @override
  State<TeacherMainScaffold> createState() => _TeacherMainScaffoldState();
}

class _TeacherMainScaffoldState extends State<TeacherMainScaffold> {
  final AcademyService _service = AcademyService();
  int _unreadCount = 0;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchUnreadCount();
    // 30초마다 안 읽은 메시지 수 확인
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchUnreadCount(),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final count = await _service.getUnreadMessageCount();
      if (mounted) {
        setState(() => _unreadCount = count);
      }
    } catch (e) {
      print('Error fetching unread count: $e');
    }
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      floatingActionButton: SizedBox(
        height: 60,
        width: 60,
        child: Badge(
          isLabelVisible: _unreadCount > 0,
          label: Text('$_unreadCount'),
          offset: const Offset(-2, 2),
          child: FloatingActionButton(
            onPressed: () {
              context.push('/chat');
              // 채팅 화면 갔다오면 갱신
              Future.delayed(
                  const Duration(milliseconds: 500), _fetchUnreadCount);
            },
            backgroundColor: Colors.indigo,
            elevation: 4,
            shape: const CircleBorder(),
            child: const Icon(Icons.chat_bubble, size: 28, color: Colors.white),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: widget.navigationShell.currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '홈'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: '플래너'),
          BottomNavigationBarItem(
            icon: SizedBox.shrink(), // FAB Space
            label: '',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '학생'),
          BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_rounded), label: '더보기'),
        ],
        onTap: (index) {
          if (index == 2) return; // FAB Space - skip

          // [NEW] Student Menu Disabled temporarily
          if (index == 3) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('준비중'),
                content: const Text('다른 메뉴로 대체될 예정입니다.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('확인'),
                  ),
                ],
              ),
            );
            return;
          }

          _onTap(index);
        },
      ),
    );
  }
}
