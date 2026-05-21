import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notification_service.dart';
import 'screens/main_shell.dart';
import 'utils/app_theme.dart';
import 'utils/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);

  await AppState.loadPreferences();
  await NotificationService.init();
  await NotificationService.syncFromDatabase();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const FinanceApp());
}

class FinanceApp extends StatefulWidget {
  const FinanceApp({super.key});

  @override
  State<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends State<FinanceApp> {
  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onStateChange);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final primary = AppState.instance.primaryColor;
    return MaterialApp(
      title: 'Uffa',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      themeMode: AppState.instance.themeMode,
      theme: AppTheme.light(primary: primary),
      darkTheme: AppTheme.dark(primary: primary),
      home: MainShell(),
    );
  }
}
