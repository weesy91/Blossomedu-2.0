import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({
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
          backgroundColor: AppColors.primary,
          elevation: 4,
          shape: const CircleBorder(),
          child: const Icon(Icons.chat_bubble, size: 28, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
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
