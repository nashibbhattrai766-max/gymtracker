import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'config/api_config.dart';
import 'config/profile.dart';
import 'providers/gym_provider.dart';
import 'screens/home_screen.dart';
import 'screens/log_screen.dart';
import 'screens/exercise_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'services/reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.load();
  await Profile.load();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const GymTrackerApp());
}

class GymTrackerApp extends StatelessWidget {
  const GymTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GymProvider()..init(),
      child: MaterialApp(
        title: 'GymTracker',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const MainShell(),
      ),
    );
  }

  ThemeData _buildTheme() {
    const primaryColor    = Color(0xFF6C63FF); // Electric violet
    const accentOrange    = Color(0xFFFF6B35); // Energetic orange
    const bgDark          = Color(0xFF0F0F1A); // Near-black navy
    const surfaceColor    = Color(0xFF1A1A2E); // Dark card surface
    const surfaceVariant  = Color(0xFF22223A); // Slightly lighter surface

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary:         primaryColor,
        secondary:       accentOrange,
        surface:         surfaceColor,
        surfaceContainerHighest: surfaceVariant,
        onPrimary:       Colors.white,
        onSurface:       Colors.white,
      ),
      scaffoldBackgroundColor: bgDark,
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      textTheme: const TextTheme(
        displayLarge:  TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        displayMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        headlineLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        headlineMedium:TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        bodyLarge:     TextStyle(color: Colors.white70),
        bodyMedium:    TextStyle(color: Colors.white60),
        labelLarge:    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle:  const TextStyle(color: Colors.white38),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}

// ── Main scaffold with bottom nav ─────────────────────────────────────────────

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  static const _logTab = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ReminderService.requestPermission();
      await _openTabFromNotification();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _openTabFromNotification();
      final provider = context.read<GymProvider>();
      provider.refreshHealthStatus().then((_) => provider.syncWatchData());
    }
  }

  /// The gym (8 PM) and daily-log (11 PM) reminders open the Log tab when tapped.
  Future<void> _openTabFromNotification() async {
    final tab = await ReminderService.consumeLaunchTab();
    if (tab == 'log' && mounted) setState(() => _currentIndex = _logTab);
  }

  final List<Widget> _screens = const [
    HomeScreen(),
    LogScreen(),
    ExerciseScreen(),
    ProgressScreen(),
    AiChatScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded),     label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note_rounded),     label: 'Log'),
          BottomNavigationBarItem(icon: Icon(Icons.fitness_center_rounded), label: 'Exercise'),
          BottomNavigationBarItem(icon: Icon(Icons.insights_rounded),       label: 'Progress'),
          BottomNavigationBarItem(icon: Icon(Icons.smart_toy_rounded),     label: 'AI Coach'),
        ],
      ),
    );
  }
}
