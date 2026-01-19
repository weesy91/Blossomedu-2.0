import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // [NEW] For PointerDeviceKind
import 'package:provider/provider.dart';
import 'config/router.dart';
import 'core/constants.dart';
import 'core/providers/user_provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart'; // [RESTORED]

void main() async {
  // [Changed] to async
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(
      'ko_KR', null); // [NEW] Initialize Korean locale
  runApp(const BlossomApp());
}

class BlossomApp extends StatelessWidget {
  const BlossomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
      ],
      child: MaterialApp.router(
        title: 'BlossomEdu',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ko', 'KR'),
          Locale('en', 'US'),
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
          useMaterial3:
              false, // Disabled due to Windows ShaderCompiler crash (ink_sparkle.frag)
          scaffoldBackgroundColor: AppColors.background,
          fontFamily: 'Roboto',
        ),
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.trackpad,
          },
        ),
        routerConfig: router,
      ),
    );
  }
}
