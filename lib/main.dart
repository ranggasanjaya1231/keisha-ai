import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart';

// Import services dan screens yang sudah dipisah
import 'services/database_helper.dart';
import 'screens/get_started_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/main_chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  await _requestAppPermissions();

  Map<String, dynamic> db = await DatabaseHelper.loadLocalDb();
  String? lastUser = db["last_active_user"];
  runApp(KeishaApp(initialUser: lastUser));
}

Future<void> _requestAppPermissions() async {
  try {
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
    ].request();
  } catch (e) {
    debugPrint("Permission error: $e");
  }
}

class KeishaApp extends StatefulWidget {
  final String? initialUser;
  const KeishaApp({super.key, this.initialUser});

  @override
  State<KeishaApp> createState() => _KeishaAppState();
}

class _KeishaAppState extends State<KeishaApp> {
  bool isDarkMode = false;

  void toggleDarkMode(bool val) {
    setState(() => isDarkMode = val);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keisha AI',
      debugShowCheckedModeBanner: false,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF616BF2),
          primary: const Color(0xFF616BF2),
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        cardColor: Colors.white,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardColor: const Color(0xFF161B22),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF616BF2),
          primary: const Color(0xFF616BF2),
          surface: const Color(0xFF161B22),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      initialRoute: widget.initialUser != null ? '/chat' : '/get_started',
      routes: {
        '/get_started': (context) => const GetStartedScreen(),
        '/auth': (context) => const AuthScreen(),
        '/chat': (context) => MainChatScreen(
              initialUser: widget.initialUser,
              isDarkMode: isDarkMode,
              onToggleDarkMode: toggleDarkMode,
            ),
      },
    );
  }
}
