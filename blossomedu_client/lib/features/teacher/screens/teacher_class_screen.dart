import 'package:flutter/material.dart';

/// Placeholder screen for the "수업" (Class) tab in teacher navigation.
/// Will be expanded to include:
/// - Today's class schedule
/// - Class log history
/// - Timetable management
class TeacherClassScreen extends StatelessWidget {
  const TeacherClassScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('수업 관리'),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 24),
            Text(
              '수업 관리 화면 준비 중',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '수업 시간표, 수업 일지 등이 여기에 표시됩니다.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
