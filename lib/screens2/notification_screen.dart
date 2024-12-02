import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:random_avatar/random_avatar.dart';

class NotificationScreen extends StatelessWidget {
  NotificationScreen({super.key});

  final _key = encrypt.Key.fromUtf8(
      'nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
  final _iv = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV

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

  Future<void> _updateRequestStatus(String senderId, String status) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // Update status in "requestsReceived" for the current user
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('requestsReceived')
          .doc(senderId)
          .update({'status': status});

      // Update status in "requestsSent" for the sender
      await FirebaseFirestore.instance
          .collection('users')
          .doc(senderId)
          .collection('requestsSent')
          .doc(currentUser.uid)
          .update({'status': status});
    } catch (e) {
      print("Error updating request status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Center(
        child: Text("No user logged in."),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Notifications",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.pink.shade700,
      ),
      body: Column(
        children: [
          // Received Requests
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .collection('requestsReceived')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("No received friend requests."),
                  );
                }

                final receivedRequests = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: receivedRequests.length,
                  itemBuilder: (context, index) {
                    final request = receivedRequests[index];
                    final encryptedUsername = request['senderUsername'] ?? '';
                    final senderUsername = _decryptUsername(encryptedUsername);
                    final status = request['status'] ?? 'pending';
                    final senderId = request['senderId'];

                    return Card(
                      margin: const EdgeInsets.all(10),
                      child: ListTile(
                        leading: RandomAvatar(senderUsername, height: 40, width: 40),
                        title: Text(
                          senderUsername,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          "Status: $status",
                          style: TextStyle(
                            color: status == 'accepted'
                                ? Colors.green
                                : status == 'rejected'
                                ? Colors.red
                                : Colors.orange,
                          ),
                        ),
                        trailing: status == 'pending'
                            ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () => _updateRequestStatus(senderId, 'accepted'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _updateRequestStatus(senderId, 'rejected'),
                            ),
                          ],
                        )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(),

          // Sent Requests
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .collection('requestsSent')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("No sent friend requests."),
                  );
                }

                final sentRequests = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: sentRequests.length,
                  itemBuilder: (context, index) {
                    final request = sentRequests[index];
                    final encryptedUsername = request['receiverUsername'] ?? '';
                    final receiverUsername = _decryptUsername(encryptedUsername);
                    final status = request['status'] ?? 'pending';

                    return Card(
                      margin: const EdgeInsets.all(10),
                      child: ListTile(
                        leading: RandomAvatar(receiverUsername, height: 40, width: 40),
                        title: Text(
                          receiverUsername,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          status == 'accepted'
                              ? "Your request was accepted by $receiverUsername."
                              : status == 'rejected'
                              ? "Your request was rejected by $receiverUsername."
                              : "Pending...",
                          style: TextStyle(
                            color: status == 'accepted'
                                ? Colors.green
                                : status == 'rejected'
                                ? Colors.red
                                : Colors.orange,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
