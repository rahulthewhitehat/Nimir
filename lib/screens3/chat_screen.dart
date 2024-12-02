import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:random_avatar/random_avatar.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String username;

  const ChatScreen({super.key, required this.userId, required this.username});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final _key = encrypt.Key.fromUtf8('nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
  final _iv = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV

  String _encryptMessage(String message) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    return encrypter.encrypt(message, iv: _iv).base64;
  }

  String _decryptMessage(String encryptedMessage) {
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      return encrypter.decrypt64(encryptedMessage, iv: _iv);
    } catch (e) {
      return "Decryption error";
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final currentUserId = currentUser.uid;
    final chatId = currentUserId.compareTo(widget.userId) < 0
        ? "${currentUserId}_${widget.userId}"
        : "${widget.userId}_${currentUserId}";

    try {
      final encryptedMessage = _encryptMessage(text);

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': currentUserId,
        'receiverId': widget.userId,
        'text': encryptedMessage,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'user1': currentUserId,
        'user2': widget.userId,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastMessage': encryptedMessage,
      }, SetOptions(merge: true));

      _messageController.clear();
    } catch (e) {
      print("Error sending message: $e");
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

    final currentUserId = currentUser.uid;
    final chatId = currentUserId.compareTo(widget.userId) < 0
        ? "${currentUserId}_${widget.userId}"
        : "${widget.userId}_${currentUserId}";

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            RandomAvatar(
              widget.username,
              height: 36,
              width: 36,
            ),
            const SizedBox(width: 10),
            Text(
              widget.username,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        backgroundColor: Colors.pink.shade700,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No messages yet."));
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final decryptedText = _decryptMessage(message['text']);
                    final isSentByMe = message['senderId'] == currentUserId;
                    final timestamp = message['timestamp']?.toDate();

                    return Row(
                      mainAxisAlignment: isSentByMe
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      children: [
                        if (!isSentByMe)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: RandomAvatar(
                              widget.username,
                              height: 30,
                              width: 30,
                            ),
                          ),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: isSentByMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 5, horizontal: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSentByMe
                                      ? Colors.pink.shade100
                                      : Colors.grey.shade300,
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    topRight: Radius.circular(12),
                                    bottomLeft: isSentByMe
                                        ? Radius.circular(12)
                                        : Radius.zero,
                                    bottomRight: isSentByMe
                                        ? Radius.zero
                                        : Radius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  decryptedText,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                              if (timestamp != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 2),
                                  child: Text(
                                    "${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')} - ${timestamp.day}/${timestamp.month}/${timestamp.year}",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (isSentByMe)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: RandomAvatar(
                              currentUser.displayName ?? currentUser.email!,
                              height: 30,
                              width: 30,
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 15,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.pink.shade700,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: () {
                      final text = _messageController.text.trim();
                      if (text.isNotEmpty) {
                        _messageController.clear();
                        _sendMessage(text);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
