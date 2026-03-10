import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/pairing_screen.dart';
import 'screens/request_screen.dart';
import 'services/auth_service.dart';
import 'theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  try {
    await AuthService.instance.ensureSignedIn();
  } catch (e) {
    // Auth may fail offline on first launch — app still works, will retry on next action
    debugPrint('Auth sign-in deferred: $e');
  }
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const YesClaudeApp());
}

class YesClaudeApp extends StatelessWidget {
  const YesClaudeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yes Claude...',
      debugShowCheckedModeBanner: false,
      theme: YesClaudeTheme.build(),
      home: const AppRouter(),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _loading = true;
  bool _isPaired = false;

  @override
  void initState() {
    super.initState();
    _checkPairing();
  }

  Future<void> _checkPairing() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('deviceId');
    setState(() {
      _isPaired = deviceId != null;
      _loading = false;
    });
  }

  void _onPaired() {
    setState(() {
      _isPaired = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isPaired) {
      return const RequestScreen();
    }
    return PairingScreen(onPaired: _onPaired);
  }
}
