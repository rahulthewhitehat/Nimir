import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:encrypt/encrypt.dart' as encrypt;


class EnhancedDashboard extends StatelessWidget {
  EnhancedDashboard({super.key});

  final _key = encrypt.Key.fromUtf8(
      'nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
  final _iv = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV

  /// Decrypt username
  String _decryptUsername(String encryptedUsername) {
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      final decrypted = encrypter.decrypt64(encryptedUsername, iv: _iv);
      return decrypted;
    } catch (e) {
      print("Decryption error: $e");
      return "Decryption failed";
    }
  }

  /// Fetch the decrypted username
  Future<String?> _fetchUsername(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final encryptedUsername = userDoc.data()?['username'];
        return encryptedUsername != null ? _decryptUsername(encryptedUsername) : "User";
      } else {
        return null;
      }
    } catch (e) {
      print("Error fetching username: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Dashboard",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.pink.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/notificationScreen');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: FutureBuilder<String?>(
        future: _fetchUsername(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    "Error loading user data.",
                    style: TextStyle(fontSize: 18, color: Colors.red),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Please check your internet connection or contact support.",
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final username = snapshot.data ?? "User";

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Replace static avatar with a random avatar
                    RandomAvatar(username, height: 60, width: 60),
                    const SizedBox(width: 16),
                    Text(
                      "Welcome, $username!",
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.pink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      _buildDashboardButton(
                        context,
                        title: "Submit Report",
                        icon: Icons.report,
                        onTap: () {
                          Navigator.pushNamed(context, '/submitReport');
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        title: "View Reports",
                        icon: Icons.list_alt,
                        onTap: () {
                          Navigator.pushNamed(context, '/viewReports');
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        title: "View Chats",
                        icon: Icons.chat,
                        onTap: () {
                          Navigator.pushNamed(context, '/MessagesScreen');
                        },
                      ),
                      _buildDashboardButton(
                        context,
                        title: "Public Feed",
                        icon: Icons.feed,
                        onTap: () {
                          Navigator.pushNamed(context, '/publicFeed');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDashboardButton(
      BuildContext context, {
        required String title,
        required IconData icon,
        required VoidCallback onTap,
      }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.pink.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: Colors.pink.shade700),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.pink.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
