import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class PostScreen extends StatefulWidget {
  const PostScreen({super.key});

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final _key = encrypt.Key.fromUtf8(
      'nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
  final _iv = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV
  final TextEditingController _textController = TextEditingController();
  final List<File> _selectedImages = [];
  bool _isPosting = false;

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.length + _selectedImages.length <= 3) {
      setState(() {
        _selectedImages.addAll(pickedFiles.map((file) => File(file.path)));
      });
    } else {
      _showSnackBar("You can only select up to 3 images.");
    }
  }

  Future<void> _submitPost() async {
    if (_textController.text.isEmpty) {
      _showSnackBar("Please enter some text for the post.");
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("You must be logged in to post.");
      return;
    }

    setState(() {
      _isPosting = true;
    });

    try {
      // Encrypt text
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      final encryptedText = encrypter
          .encrypt(_textController.text, iv: _iv)
          .base64;

      // Fetch encrypted username from Firestore
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final encryptedUsername = userDoc.data()?['username'];

      // Upload images
      List<String> imageUrls = [];
      for (final image in _selectedImages) {
        final fileName = "${DateTime
            .now()
            .millisecondsSinceEpoch}_${user.uid}.jpg";
        final ref = FirebaseStorage.instance.ref().child(
            'post_images/$fileName');
        await ref.putFile(image);
        final url = await ref.getDownloadURL();
        imageUrls.add(url);
      }

      // Save post to Firestore with initialized fields
      await FirebaseFirestore.instance.collection('posts').add({
        'userId': user.uid,
        'username': encryptedUsername,
        'text': encryptedText,
        'images': imageUrls,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': 0, // Initialize likes count
        'likedBy': [], // Initialize likedBy as an empty list
      });

      _showSnackBar("Post submitted successfully!");
      Navigator.pop(context);
    } catch (e) {
      _showSnackBar("Error submitting post: $e");
    } finally {
      setState(() {
        _isPosting = false;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    // Automatically prompt the user to select images upon entering the screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showMediaSelectionDialog();
    });
  }

  void _showMediaSelectionDialog() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.length + _selectedImages.length <= 3) {
      setState(() {
        _selectedImages.addAll(pickedFiles.map((file) => File(file.path)));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Create Post",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.pink.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Header Text
            const Text(
              "Create Your Post",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            // Skip Button for Media Selection
            if (_selectedImages.isEmpty)
              Align(
                alignment: Alignment.center,
                child: ElevatedButton(
                  onPressed: () {
                    _textController.clear();
                    setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    "Skip to Text Input",
                    style: TextStyle(
                      color: Colors.pink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Image Previews
            if (_selectedImages.isNotEmpty)
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  itemBuilder: (context, index) {
                    return Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _selectedImages[index],
                              height: 100,
                              width: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 5,
                          right: 5,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedImages.removeAt(index);
                              });
                            },
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.red,
                              child: Icon(
                                  Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            const SizedBox(height: 20),

            // Text Input Field
            const Text(
              "Write a Caption",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: _textController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: "What's on your mind?",
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Add Image Button
            Align(
              alignment: Alignment.center,
              child: ElevatedButton.icon(
                onPressed: _selectedImages.length < 3 ? _pickImages : null,
                icon: const Icon(Icons.image, color: Colors.white),
                label: const Text(
                  "Add More Images (max 3)",
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Submit Button
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitPost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isPosting
                      ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  )
                      : const Text(
                    "Submit Post",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}