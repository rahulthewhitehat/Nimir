import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();

    // Restore any pending timers for file deletion
    _restoreTimers().then((_) {
      // Navigate after restoring timers
      Future.delayed(const Duration(seconds: 3), () {
        _navigateBasedOnAuth(context);
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _navigateBasedOnAuth(BuildContext context) async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // Check Firestore for verification status
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data()?['verified'] == true) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        Navigator.pushReplacementNamed(context, '/secondVerification');
      }
    } else {
      Navigator.pushReplacementNamed(context, '/disclaimerScreen');
    }
  }

  Future<void> _restoreTimers() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if (userDoc.exists) {
      final uploadTimestamp = userDoc.data()?['uploadTimestamp'];
      if (uploadTimestamp != null) {
        final DateTime uploadTime = DateTime.fromMillisecondsSinceEpoch(uploadTimestamp);
        final DateTime deleteAt = uploadTime.add(const Duration(hours: 2));
        final Duration delay = deleteAt.difference(DateTime.now());

        if (delay.isNegative) {
          await _deleteUploadedFiles(user.uid); // Delete immediately if time elapsed
        } else {
          Timer(delay, () => _deleteUploadedFiles(user.uid)); // Schedule deletion
        }
      }
    }
  }


  Future<void> _deleteUploadedFiles(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final profileImageUrl = userDoc.data()?['profileImageUrl'];
      final idImageUrl = userDoc.data()?['idImageUrl'];

      if (profileImageUrl != null) {
        await FirebaseStorage.instance.refFromURL(profileImageUrl).delete();
      }
      if (idImageUrl != null) {
        await FirebaseStorage.instance.refFromURL(idImageUrl).delete();
      }

      // Remove URLs from Firestore
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'profileImageUrl': FieldValue.delete(),
        'idImageUrl': FieldValue.delete(),
      });

      print("Files and Firestore links successfully deleted.");
    } catch (e) {
      print("Error during file deletion: $e");
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo.png', height: 200),
              const SizedBox(height: 20),
              Text(
                'Nimir',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'An Anonymous Reporting Platform For Women!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.pink.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 40),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.pink.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
