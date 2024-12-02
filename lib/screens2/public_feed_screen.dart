import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:carousel_slider/carousel_slider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:random_avatar/random_avatar.dart';

import 'comments_screen.dart';

class PublicFeedScreen extends StatefulWidget {
  const PublicFeedScreen({super.key});

  @override
  State<PublicFeedScreen> createState() => _PublicFeedScreenState();
}

class _PublicFeedScreenState extends State<PublicFeedScreen> {
  final _key = encrypt.Key.fromUtf8(
      'nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
  final _iv = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV

  String _decryptText(String encryptedText) {
    try {
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      final decrypted = encrypter.decrypt64(encryptedText, iv: _iv);
      return decrypted;
    } catch (e) {
      print("Decryption error: $e");
      return "Decryption failed";
    }
  }


  Future<void> _toggleLike(DocumentSnapshot post) async {
    try {
      final postRef = FirebaseFirestore.instance.collection('posts').doc(
          post.id);
      final userId = FirebaseAuth.instance.currentUser?.uid;

      if (userId == null) return;

      final likedBy = List<String>.from(post['likedBy'] ?? []);
      final likes = post['likes'] ?? 0;

      if (likedBy.contains(userId)) {
        // User already liked -> Unlike
        await postRef.update({
          'likedBy': FieldValue.arrayRemove([userId]),
          'likes': likes - 1,
        });
      } else {
        // User has not liked -> Like
        await postRef.update({
          'likedBy': FieldValue.arrayUnion([userId]),
          'likes': likes + 1,
        });
      }
    } catch (e) {
      print("Error toggling like: $e");
    }
  }

  Future<void> _sendFriendRequest(String receiverId, String receiverUsername) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null || currentUser.uid == receiverId) {
      return; // Prevent sending requests to yourself
    }

    final senderId = currentUser.uid;

    try {
      // Fetch the current user's encrypted username from Firestore
      final senderDoc = await FirebaseFirestore.instance.collection('users').doc(senderId).get();
      final encryptedSenderUsername = senderDoc.data()?['username'];
      if (encryptedSenderUsername == null) {
        _showSnackBar("Error: Your username is missing. Please check your profile.");
        return;
      }

      // Encrypt the receiver's username before saving
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      final encryptedReceiverUsername = encrypter.encrypt(receiverUsername, iv: _iv).base64;

      // References to Firestore documents
      final senderDocRef = FirebaseFirestore.instance.collection('users').doc(senderId);
      final receiverDocRef = FirebaseFirestore.instance.collection('users').doc(receiverId);

      // Add request to sender's "requestsSent" subcollection
      await senderDocRef.collection('requestsSent').doc(receiverId).set({
        'receiverId': receiverId,
        'receiverUsername': encryptedReceiverUsername,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Add request to receiver's "requestsReceived" subcollection
      await receiverDocRef.collection('requestsReceived').doc(senderId).set({
        'senderId': senderId,
        'senderUsername': encryptedSenderUsername,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Show a snackbar to indicate success
      _showSnackBar("Friend request sent!");
    } catch (e) {
      print("Error sending friend request: $e");
      _showSnackBar("Failed to send friend request.");
    }

    setState(() {}); // Refresh UI to reflect the updated button state
  }


  Future<bool> _isRequestSent(String receiverId) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return false;
    }

    final senderId = currentUser.uid;

    try {
      final requestDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(senderId)
          .collection('requestsSent')
          .doc(receiverId)
          .get();

      return requestDoc.exists; // Check if the request is already sent
    } catch (e) {
      print("Error checking friend request status: $e");
      return false;
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.pink.shade700,
        title: const Text(
          "Nimir",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text("No posts available. Be the first to post!"),
            );
          }

          final posts = snapshot.data!.docs;

          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              final text = _decryptText(post['text']);
              final username = _decryptText(post['username']);
              final images = post['images'] as List<dynamic>? ?? [];
              final timestamp = post['timestamp']?.toDate();
              final likes = post['likes'] ?? 0;
              final likedBy = List<String>.from(post['likedBy'] ?? []);
              final userId = FirebaseAuth.instance.currentUser?.uid;
              final postUserId = post['userId'];

              final isLiked = likedBy.contains(userId);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with avatar, username, and friend request button
                      Row(
                        children: [
                          RandomAvatar(username, height: 40, width: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              username,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          FutureBuilder<bool>(
                            future: _isRequestSent(postUserId),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                );
                              }

                              final isRequestSent = snapshot.data ?? false;

                              return IconButton(
                                icon: Icon(
                                  isRequestSent ? Icons.check_circle : Icons.person_add,
                                  color: isRequestSent ? Colors.green : Colors.pink.shade700,
                                ),
                                onPressed: isRequestSent
                                    ? null
                                    : () async {
                                  await _sendFriendRequest(postUserId, username);
                                  setState(() {});
                                  _showSnackBar("Friend request sent successfully!");
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Post images carousel
                      if (images.isNotEmpty)
                        CarouselSlider(
                          options: CarouselOptions(
                            height: 250,
                            enableInfiniteScroll: false,
                            viewportFraction: 1.0,
                          ),
                          items: images.map((imageUrl) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              ),
                            );
                          }).toList(),
                        ),

                      const SizedBox(height: 10),

                      // Like and comment buttons
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              isLiked ? Icons.favorite : Icons.favorite_border,
                              color: isLiked ? Colors.red : Colors.black,
                            ),
                            onPressed: () => _toggleLike(post),
                          ),
                          Text("$likes"),
                          const SizedBox(width: 20),
                          IconButton(
                            icon: const Icon(Icons.comment, color: Colors.blue),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CommentScreen(postId: post.id),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      // Post text
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          text,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),

                      // Timestamp
                      if (timestamp != null)
                        Text(
                          DateFormat('yyyy-MM-dd – kk:mm').format(timestamp),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pushNamed(context, '/postScreen'),
        backgroundColor: Colors.pink.shade700,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}