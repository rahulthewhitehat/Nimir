import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:nimir/screens/disclaimer.dart';
import 'package:nimir/screens/settings_screen.dart';
import 'package:nimir/screens/splash_screen.dart';
import 'package:nimir/screens/login_screen.dart';
import 'package:nimir/screens/signup_screen.dart';
import 'package:nimir/screens/advanced_verification_screen.dart';
import 'package:nimir/screens/user_dashboard.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:nimir/screens2/notification_screen.dart';
import 'package:nimir/screens2/post_screen.dart';
import 'package:nimir/screens2/public_feed_screen.dart';
import 'package:nimir/screens2/view_reports_screen.dart';
import 'package:nimir/screens3/messages_screen.dart';
import 'package:nimir/screens2/report_submission_screen.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Initialize Firebase

  // Activate Firebase App Check
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider
        .playIntegrity, // Use PlayIntegrity or SafetyNet
  );
  runApp(const NimirApp());
}
class NimirApp extends StatelessWidget {
  const NimirApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nimir',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => LoginScreen(),
        '/signup': (context) => SignUpScreen(),
        '/secondVerification': (context) => const AdvancedVerificationScreen(),
        '/dashboard': (context) => EnhancedDashboard(),
        '/settings': (context) => const SettingsScreen(),
        '/publicFeed': (context) => const PublicFeedScreen(),
        '/postScreen': (context) => const PostScreen(),
        '/notificationScreen': (context) => NotificationScreen(),
        '/MessagesScreen': (context) => MessagesScreen(),
        '/submitReport': (context) => ReportSubmissionPage(),
        '/viewReports': (context) => ViewReportScreen(),
        '/disclaimerScreen':(context) => DisclaimerScreen(),
      },
    );
  }
}
