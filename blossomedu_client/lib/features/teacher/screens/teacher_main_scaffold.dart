import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TeacherMainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const TeacherMainScaffold({
    required this.navigationShell,
    super.key,
  });

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      floatingActionButton: SizedBox(
        height: 60,
        width: 60,
        child: FloatingActionButton(
          onPressed: () {
            context.push('/chat');
          },
          backgroundColor: Colors.indigo,
          elevation: 4,
          shape: const CircleBorder(),
          child: const Icon(Icons.chat_bubble, size: 28, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
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
          _onTap(index);
        },
      ),
    );
  }
}
