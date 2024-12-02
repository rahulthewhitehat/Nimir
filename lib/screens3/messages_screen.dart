import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:random_avatar/random_avatar.dart';

import '../screens2/ai_chat_screen.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
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

  Future<List<Map<String, String>>> _fetchChatUsers() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return [];

    final List<Map<String, String>> chatUsers = [];
    final currentUserId = currentUser.uid;

    try {
      // Check requestsSent collection
      final requestsSentSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('requestsSent')
          .where('status', isEqualTo: 'accepted')
          .get();

      for (var doc in requestsSentSnapshot.docs) {
        chatUsers.add({
          'userId': doc['receiverId'],
          'username': _decryptUsername(doc['receiverUsername']),
        });
      }

      // Check requestsReceived collection
      final requestsReceivedSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('requestsReceived')
          .where('status', isEqualTo: 'accepted')
          .get();

      for (var doc in requestsReceivedSnapshot.docs) {
        chatUsers.add({
          'userId': doc['senderId'],
          'username': _decryptUsername(doc['senderUsername']),
        });
      }
    } catch (e) {
      print("Error fetching chat users: $e");
    }

    return chatUsers;
  }

  void _navigateToChatScreen(BuildContext context, String userId, String username) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          userId: userId,
          username: username,
        ),
      ),
    );
    setState(() {}); // Refresh the MessagesScreen when returning
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "You must be logged in via email or Google to access chats."),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Messages",
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
        backgroundColor: Colors.pink.shade700,
        elevation: 1,
      ),
      body: FutureBuilder<List<Map<String, String>>>(
        future: _fetchChatUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                "No chats available.",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final chatUsers = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Chat with AI placeholder
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AiChatScreen(),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  margin: const EdgeInsets.only(bottom: 16.0),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade50,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.pink.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: RandomAvatar(
                          "SolaceBot", // Unique identifier for the AI chat avatar
                          height: 50,
                          width: 50,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Chat with Tara",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.pink,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Tara is here to provide support and guidance.",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.pink,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),

              // Divider for clarity
              const Divider(thickness: 1, color: Colors.grey),

              // Chat users list
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  "Your Chats",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              ...chatUsers.map((user) {
                final currentUserId = FirebaseAuth.instance.currentUser!.uid;
                final chatId = currentUserId.compareTo(user['userId']!) < 0
                    ? "${currentUserId}_${user['userId']!}"
                    : "${user['userId']!}_${currentUserId}";

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(chatId)
                      .get(),
                  builder: (context, chatSnapshot) {
                    if (chatSnapshot.connectionState == ConnectionState.waiting) {
                      return const ListTile(
                        title: Text("Loading..."),
                      );
                    }

                    if (!chatSnapshot.hasData || !chatSnapshot.data!.exists) {
                      // No chat document exists yet
                      return ListTile(
                        leading: ClipOval(
                          child: Container(
                            color: Colors.grey.shade300,
                            child: RandomAvatar(user['username']!,
                                height: 50, width: 50),
                          ),
                        ),
                        title: Text(
                          user['username']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: const Text(
                          "Tap to chat",
                          style: TextStyle(color: Colors.grey),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.pink,
                          size: 18,
                        ),
                        onTap: () {
                          _navigateToChatScreen(
                              context, user['userId']!, user['username']!);
                        },
                      );
                    }

                    final chatData = chatSnapshot.data!;
                    final lastMessage = chatData['lastMessage'] != null
                        ? _decryptUsername(chatData['lastMessage'])
                        : "Tap to chat";
                    final lastTimestamp = chatData['lastMessageTimestamp']
                        ?.toDate();
                    final timeAgo = lastTimestamp != null
                        ? _getTimeAgo(lastTimestamp)
                        : "";

                    return ListTile(
                      leading: ClipOval(
                        child: Container(
                          color: Colors.grey.shade300,
                          child: RandomAvatar(user['username']!,
                              height: 50, width: 50),
                        ),
                      ),
                      title: Text(
                        user['username']!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        lastMessage,
                        style: const TextStyle(color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            timeAgo,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.pink,
                            size: 18,
                          ),
                        ],
                      ),
                      onTap: () {
                        _navigateToChatScreen(
                            context, user['userId']!, user['username']!);
                      },
                    );
                  },
                );
              }).toList(),
            ],
          );
        },
      ),
    );
  }


  String _getTimeAgo(DateTime? timestamp) {
    if (timestamp == null) return "";
    final difference = DateTime.now().difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'just now';
    }
  }
}
