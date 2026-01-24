import 'package:flutter/material.dart'; // [NEW] For Container
import 'package:go_router/go_router.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/planner/screens/planner_screen.dart';
import '../features/planner/screens/assignment_detail_screen.dart';
import '../features/teacher/screens/teacher_home_screen.dart';
import '../features/teacher/screens/student_list_screen.dart';
import '../features/teacher/screens/teacher_student_planner_screen.dart';
import '../features/teacher/screens/teacher_class_log_create_screen.dart';
import '../features/teacher/screens/assignment_review_screen.dart';
import '../features/teacher/screens/word_test_review_screen.dart';
import '../features/teacher/screens/word_test_request_list_screen.dart';
import '../features/teacher/screens/teacher_vocab_manage_screen.dart';
import '../features/teacher/screens/teacher_vocab_event_manage_screen.dart';
import '../features/teacher/screens/student_registration_screen.dart';
import '../features/teacher/screens/teacher_more_screen.dart';
import '../features/teacher/screens/teacher_registration_screen.dart';
import '../features/teacher/screens/student_management_screen.dart';
import '../features/teacher/screens/staff_management_screen.dart';
import '../features/teacher/screens/student_detail_screen.dart';
import '../features/teacher/screens/staff_detail_screen.dart';
import '../features/teacher/screens/system_management_screen.dart';
import '../features/teacher/screens/teacher_main_scaffold.dart'; // [NEW] Teacher Shell
import '../features/teacher/screens/teacher_planner_screen.dart'; // [NEW] Teacher Planner
import '../features/teacher/screens/announcement_manage_screen.dart'; // [NEW]
import '../features/teacher/screens/teacher_pending_assignments_screen.dart'; // [NEW]
import '../features/student/screens/word_test_screen.dart';
import '../features/student/screens/word_test_result_screen.dart';
import '../features/student/screens/study_screen.dart';
import '../features/student/screens/my_page_screen.dart';
import '../features/home/screens/main_scaffold.dart';
import '../features/academy/screens/textbook_management_screen.dart';
import '../features/academy/screens/textbook_create_screen.dart';
import '../features/student/screens/student_book_selection_screen.dart';
import '../features/student/screens/study_record_screen.dart';
import '../features/student/screens/student_assignment_history_screen.dart'; // [NEW]
import '../features/student/screens/makeup_task_screen.dart'; // [NEW]
import '../features/messaging/screens/chat_list_screen.dart'; // [NEW]
import '../features/messaging/screens/chat_room_screen.dart'; // [NEW]
import '../features/teacher/screens/offline_test_projection_screen.dart'; // [NEW]
import '../features/teacher/screens/offline_test_grading_screen.dart'; // [NEW]
import '../features/teacher/screens/student_log_search_screen.dart'; // [NEW]

final router = GoRouter(
  initialLocation: '/login',
  routes: [
    // [FIX] Handle Root Path
    GoRoute(
      path: '/',
      redirect: (_, __) => '/login',
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    // [NEW] Shell Route for Persistent Navigation
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainScaffold(navigationShell: navigationShell);
      },
      branches: [
        // Tab 1: Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        // Tab 2: Planner
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/planner',
              builder: (context, state) => const PlannerScreen(),
            ),
          ],
        ),
        // Tab 3: Empty (FAB Space Placeholder) - Not used but needed index
        StatefulShellBranch(
            routes: [GoRoute(path: '/dummy', builder: (c, s) => Container())]),
        // Tab 4: Study
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/student/study',
              builder: (context, state) => const StudyScreen(),
            ),
          ],
        ),
        // Tab 5: MyPage
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/student/mypage',
              builder: (context, state) => const MyPageScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/assignment/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return AssignmentDetailScreen(taskId: id.toString());
      },
    ),
    // [NEW] Teacher Shell Route for Persistent Navigation
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return TeacherMainScaffold(navigationShell: navigationShell);
      },
      branches: [
        // Tab 0: 홈 (Dashboard)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/teacher/home',
              builder: (context, state) => const TeacherHomeScreen(),
            ),
          ],
        ),
        // Tab 1: 플래너 (통합: 수업 + 과제)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/teacher/planner',
              builder: (context, state) => const TeacherPlannerScreen(),
            ),
          ],
        ),
        // Tab 2: FAB Space (Empty placeholder)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/teacher/dummy',
              builder: (c, s) => Container(),
            ),
          ],
        ),
        // Tab 3: 학생 (Students)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/teacher/students',
              builder: (context, state) => const StudentListScreen(),
            ),
          ],
        ),
        // Tab 4: 설정 (More/Settings)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/teacher/more',
              builder: (context, state) => const TeacherMoreScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/teacher/student/register',
      builder: (context, state) => const StudentRegistrationScreen(),
    ),
    GoRoute(
      path: '/teacher/student/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return TeacherStudentPlannerScreen(studentId: id.toString());
      },
    ),
    GoRoute(
      path: '/teacher/class_log/create',
      builder: (context, state) {
        final studentId = state.uri.queryParameters['studentId'] ?? '';
        final studentName = state.uri.queryParameters['studentName'] ?? '학생';
        final date = state.uri.queryParameters['date'];
        final subject = state.uri.queryParameters['subject'];
        return TeacherClassLogCreateScreen(
            studentId: studentId.toString(),
            studentName: studentName,
            subject: subject ?? 'SYNTAX',
            date: date);
      },
    ),
    GoRoute(
      path: '/teacher/assignment/review/:assignmentId',
      builder: (context, state) {
        final id = state.pathParameters['assignmentId'] ?? '0';
        return AssignmentReviewScreen(assignmentId: id.toString());
      },
    ),
    GoRoute(
      path: '/teacher/word/requests',
      builder: (context, state) => const WordTestRequestListScreen(),
    ),
    GoRoute(
      path: '/teacher/vocab',
      builder: (context, state) => const TeacherVocabManageScreen(),
    ),
    GoRoute(
      path: '/teacher/vocab/events',
      builder: (context, state) => const TeacherVocabEventManageScreen(),
    ),
    // /teacher/more is now in StatefulShellRoute
    GoRoute(
      path: '/teacher/staff/register',
      builder: (context, state) => const TeacherRegistrationScreen(),
    ),
    // [NEW] Management Routes
    GoRoute(
      path: '/teacher/management/students',
      builder: (context, state) => const StudentManagementScreen(),
    ),
    GoRoute(
      path: '/teacher/management/students/:id', // [NEW] Detail
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        final tabStr = state.uri.queryParameters['tab'];
        final initialTabIndex = tabStr != null ? int.tryParse(tabStr) ?? 0 : 0;
        return StudentDetailScreen(
            studentId: id, initialTabIndex: initialTabIndex);
      },
    ),
    GoRoute(
      path: '/teacher/management/staff',
      builder: (context, state) => const StaffManagementScreen(),
    ),
    GoRoute(
      path: '/teacher/management/staff/:id', // [NEW] Detail
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        return StaffDetailScreen(staffId: id);
      },
    ),
    GoRoute(
      path: '/teacher/management/system', // [NEW] System
      builder: (context, state) => const SystemManagementScreen(),
    ),
    GoRoute(
      path: '/teacher/announcements',
      builder: (context, state) => const AnnouncementManageScreen(),
    ),
    GoRoute(
      path: '/teacher/assignments/pending',
      builder: (context, state) => const TeacherPendingAssignmentsScreen(),
    ),
    GoRoute(
      path: '/teacher/word/review/:resultId',
      builder: (context, state) {
        final id = state.pathParameters['resultId'] ?? '0';
        return WordTestReviewScreen(testResultId: id.toString());
      },
    ),
    // [NEW] Textbook Routes
    GoRoute(
      path: '/academy/textbooks',
      builder: (context, state) => const TextbookManagementScreen(),
    ),
    GoRoute(
      path: '/academy/textbook/create',
      builder: (context, state) {
        final category = (state.extra as Map<String, dynamic>?)?['category'];
        return TextbookCreateScreen(initialCategory: category);
      },
    ),
    GoRoute(
      path: '/academy/textbook/edit/:id',
      builder: (context, state) {
        final bookData = state.extra as Map<String, dynamic>;
        return TextbookCreateScreen(initialData: bookData);
      },
    ),
    GoRoute(
      path: '/student/test/start',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return WordTestScreen(
          bookId: int.tryParse(extra['bookId'].toString()) ?? 0,
          testRange: extra['range']?.toString() ?? '',
          assignmentId: extra['assignmentId']?.toString() ?? '',
          testMode: extra['testMode']?.toString() ?? 'test',
          initialWords: (extra['words'] as List?)
              ?.map((e) => Map<String, String>.from(e))
              .toList(),
          questionType: extra['questionType']?.toString() ?? 'word_to_meaning',
        );
      },
    ),
    GoRoute(
      path: '/student/test/result',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return WordTestResultScreen(
          score: int.tryParse(extra['score'].toString()) ?? 0,
          total: int.tryParse(extra['totalCount'].toString()) ?? 0,
          answers: (extra['answers'] as List?)
                  ?.map((e) => Map<String, String>.from(e))
                  .toList() ??
              [],
          wrongWords: (extra['wrongWords'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              [],
          testId: int.tryParse(extra['testId'].toString()) ?? 0,
        );
      },
    ),
    GoRoute(
      path: '/student/book/select',
      builder: (context, state) => const StudentBookSelectionScreen(),
    ),
    GoRoute(
      path: '/student/records',
      builder: (context, state) => const StudyRecordScreen(),
    ),
    GoRoute(
      path: '/student/assignments/history',
      builder: (context, state) => const StudentAssignmentHistoryScreen(),
    ),
    GoRoute(
      path: '/student/makeup-tasks', // [NEW] Makeup Tasks
      builder: (context, state) => const MakeupTaskScreen(),
    ),
    // [NEW] Messaging Routes
    GoRoute(
      path: '/chat',
      builder: (context, state) => const ChatListScreen(),
    ),
    GoRoute(
      path: '/chat/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ChatRoomScreen(
          conversationId: id,
          otherUserName: extra['otherUserName'] ?? '채팅',
        );
      },
    ),
    // [NEW] Offline Test Routes
    GoRoute(
      path: '/teacher/offline-test/projection',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        // Cast dynamic list to List<Map<String, dynamic>>
        final rawWords = extra['words'] as List<dynamic>? ?? [];
        final words =
            rawWords.map((e) => Map<String, dynamic>.from(e)).toList();

        return OfflineTestProjectionScreen(
          words: words,
          durationPerWord:
              int.tryParse(extra['duration']?.toString() ?? '3') ?? 3,
          bookId: int.tryParse(extra['bookId'].toString()) ?? 0,
          range: extra['range']?.toString() ?? '',
          studentId: extra['studentId']?.toString() ?? '',
          mode: extra['mode']?.toString() ?? 'eng_kor',
        );
      },
    ),
    GoRoute(
      path: '/teacher/offline-test/grading',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final rawWords = extra['words'] as List<dynamic>? ?? [];
        final words =
            rawWords.map((e) => Map<String, dynamic>.from(e)).toList();

        return OfflineTestGradingScreen(
          words: words,
          bookId: int.tryParse(extra['bookId'].toString()) ?? 0,
          range: extra['range']?.toString() ?? '',
          studentId: extra['studentId']?.toString() ?? '',
        );
      },
    ),
    // [NEW] Student Log Search
    GoRoute(
      path: '/teacher/management/log-search',
      builder: (context, state) => const StudentLogSearchScreen(),
    ),
  ],
);
