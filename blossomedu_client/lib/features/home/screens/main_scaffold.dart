import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../core/services/academy_service.dart';

class MainScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({
    required this.navigationShell,
    super.key,
  });

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
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
            backgroundColor: AppColors.primary,
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
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: '홈'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: '플래너'),
          BottomNavigationBarItem(
            icon: SizedBox.shrink(), // Accessability-only
            label: '', // Label removed for cleaner FAB look
          ),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '학습'),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: '더보기'),
        ],
        onTap: (index) {
          if (index == 2) return; // FAB Space
          _onTap(index);
        },
      ),
    );
  }
}
