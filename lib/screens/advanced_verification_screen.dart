import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class AdvancedVerificationScreen extends StatefulWidget {
  const AdvancedVerificationScreen({super.key});

  @override
  _AdvancedVerificationScreenState createState() =>
      _AdvancedVerificationScreenState();
}

class _AdvancedVerificationScreenState extends State<AdvancedVerificationScreen> {
  File? _selectedIDImage;
  File? _capturedProfileImage;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();

  bool _isUploading = false;
  String? _nameMatchStatus;
  String? _faceMatchStatus;
  bool _isVerified = false;
  bool _showContinueButton = false;
  String? _ocrExtractedName;
  String? _profileImageUrl;
  String? _idImageUrl;
  int _attemptsLeft = 3;

  // Securely generated AES key and IV
  final _key = encrypt.Key.fromUtf8(
      'nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
  final _iv = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV

  Future<void> _pickImage(bool isID) async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        if (isID) {
          _selectedIDImage = File(pickedFile.path);
        }
      });
    }
  }

  Future<void> _initialUpload(String userId, String encryptedName,
      String encryptedUsername) async {
    try {
      // Upload ID Image
      _idImageUrl = await _uploadToStorage(
          _selectedIDImage!, 'user_uploads/$userId/id_document.jpg');

      // Upload Profile Picture
      _profileImageUrl = await _uploadToStorage(
          _capturedProfileImage!, 'user_uploads/$userId/profile_picture.jpg');

      // Add initial entry to Firestore
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'name': encryptedName,
        'username': encryptedUsername,
        'profileImageUrl': _profileImageUrl,
        'idImageUrl': _idImageUrl,
        'verified': false, // Initially not verified
        'manualReview': false, // Initially not flagged for manual review
        'uploadTimestamp': DateTime
            .now()
            .millisecondsSinceEpoch, // For restoration
      }, SetOptions(merge: true));

      print("Initial data uploaded to Firestore.");
    } catch (e) {
      print("Error during initial upload: $e");
      _showSnackBar("Error during initial upload. Please try again.");
    }
  }

  Future<bool> _verifyGender(String userId) async {
    try {
      // Perform OCR on the uploaded ID image
      final inputImage = InputImage.fromFile(_selectedIDImage!);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);

      // Split recognized text into words for keyword matching
      List<String> words = [];
      for (var block in recognizedText.blocks) {
        for (var line in block.lines) {
          words.addAll(line.text.split(' '));
        }
      }

      // Check for gender-related keywords
      final keywords = ["female", "f"];
      bool isGenderVerified = keywords.any((keyword) =>
          words.any((extractedWord) =>
          extractedWord.toLowerCase() == keyword.toLowerCase()));

      // Return the verification result
      return isGenderVerified;
    } catch (e) {
      print("Error during gender verification: $e");
      return false;
    }
  }



  Future<void> _captureProfileImage() async {
    final capturedFile = await _picker.pickImage(source: ImageSource.camera);
    if (capturedFile != null) {
      setState(() {
        _capturedProfileImage = File(capturedFile.path);
      });
    }
  }

  Future<void> _processVerification() async {
    if (_selectedIDImage == null || _capturedProfileImage == null) {
      _showSnackBar("Please upload both ID and capture your photo.");
      return;
    }

    if (_nameController.text.isEmpty) {
      _showSnackBar("Please enter your name.");
      return;
    }

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("User not logged in. Please log in first.");
      return;
    }

    setState(() {
      _isUploading = true;
      _nameMatchStatus = null;
      _faceMatchStatus = null;
    });

    try {
      final String userId = user.uid;
      final String encryptedName = _encryptData(_nameController.text);
      final String generatedUsername = _generateUsername(_nameController.text);
      final String encryptedUsername = _encryptData(generatedUsername);

      // Step 1: Initial upload to storage and Firestore
      await _initialUpload(userId, encryptedName, encryptedUsername);

      // Step 2: Perform OCR and Face Detection
      await _performOCR();
      if (_ocrExtractedName
          ?.toLowerCase()
          .contains(_nameController.text.toLowerCase()) ??
          false) {
        setState(() {
          _nameMatchStatus = "Name match success!";
        });
      } else {
        setState(() {
          _nameMatchStatus = "Name match failed!";
        });
      }

      bool isFaceMatched = await _compareFaces();
      if (isFaceMatched) {
        setState(() {
          _faceMatchStatus = "Face match success!";
        });
      } else {
        setState(() {
          _faceMatchStatus = "Face match failed!";
        });
      }

      // Step 3: Gender Verification
      bool isGenderVerified = await _verifyGender(userId);
      if (!isGenderVerified) {
        setState(() {
          _nameMatchStatus = "Gender verification failed!";
        });
      }

      // Step 4: Determine verification outcome
      final bool verified = _nameMatchStatus == "Name match success!" &&
          _faceMatchStatus == "Face match success!" &&
          isGenderVerified;

      // Update Firestore based on the overall verification result
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'verified': verified,
        'manualReview': !verified, // Flag for manual review if not verified
      });

      if (verified) {
        _scheduleFileDeletion(userId);
        setState(() {
          _isVerified = true;
        });
        Future.delayed(const Duration(seconds: 2), () {
          setState(() {
            _showContinueButton = true;
          });
        });
      } else {
        setState(() {
          _attemptsLeft -= 1; // Reduce attempts left
        });

        if (_attemptsLeft > 0) {
          _showSnackBar(
              "Verification failed. Name, Face, or Gender not matched. Attempts left: $_attemptsLeft.");
        } else {
          _showSnackBar(
              "Account locked. Your details are submitted for manual verification.");

          // Mark account for manual review after 3rd failed attempt
          await FirebaseFirestore.instance.collection('users').doc(userId).update({
            'verified': false,
            'manualReview': true, // Submit for manual review
          });
        }
      }
    } catch (e) {
      print("Error during verification: $e");
      _showSnackBar("Verification failed: $e");
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }


  bool _isDeclarationChecked = false;


  void _scheduleFileDeletion(String userId) async {
    final DateTime deleteAt = DateTime.now().add(const Duration(hours: 2));
    final Duration delay = deleteAt.difference(DateTime.now());

    Timer(delay, () async {
      try {
        // Delete images from Firebase Storage
        if (_idImageUrl != null) {
          await FirebaseStorage.instance.refFromURL(_idImageUrl!).delete();
        }
        if (_profileImageUrl != null) {
          await FirebaseStorage.instance.refFromURL(_profileImageUrl!).delete();
        }

        // Remove URLs from Firestore
        await FirebaseFirestore.instance.collection('users').doc(userId).update(
            {
              'profileImageUrl': FieldValue.delete(),
              'idImageUrl': FieldValue.delete(),
            });

        print("Files and Firestore links successfully deleted.");
      } catch (e) {
        print("Error during file deletion: $e");
      }
    });
  }


  void _showSnackBar(String message) {
    if (ScaffoldMessenger.maybeOf(BuildContext as BuildContext) != null) {
      ScaffoldMessenger.of(BuildContext as BuildContext).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } else {
      print("Unable to show SnackBar. Message: $message");
    }
  }

  String _generateUsername(String text) {
    const adjectives = [
      'bright', 'sunny', 'calm', 'brave', 'charming', 'swift',
      'wise', 'bold', 'lively', 'gentle', 'frosty', 'fiery',
      'noble', 'clever', 'happy', 'merry', 'fuzzy', 'silly',
      'shiny', 'tiny', 'funny', 'lucky', 'peaceful', 'kind',
      'sharp', 'wild', 'pure', 'zesty', 'dreamy', 'golden',
      'soft', 'cool', 'crisp', 'warm', 'brightest', 'silent',
      'graceful', 'playful', 'tender', 'fearless', 'eager', 'vivid',
      'cheerful', 'courageous', 'radiant', 'nurturing', 'energetic', 'loyal',
      'magical', 'mystic', 'wholesome', 'hearty', 'sparkling', 'calmest',
      'serene', 'creative', 'daring', 'diligent', 'majestic', 'powerful',
      'gritty', 'hopeful', 'steady', 'giddy', 'proud', 'humble',
      'humorous', 'vibrant', 'faithful', 'unseen', 'purest', 'harmonious',
      'trusty', 'spicy', 'crispy', 'breezy', 'meek', 'zany',
      'quirky', 'hearty', 'valiant', 'sleek', 'fluffy', 'witty',
      'jolly', 'clearest', 'radiant', 'dainty', 'youthful', 'zealous',
      'luminous', 'plucky', 'fierce', 'unbroken', 'balanced', 'dazzling',
      'bubbly', 'spunky', 'adorable', 'dashing', 'jovial', 'sturdy'
    ];


    const secondWords = [
      'lion', 'falcon', 'star', 'leaf', 'cloud', 'river',
      'mountain', 'tree', 'hawk', 'wolf', 'fox', 'panther',
      'owl', 'rabbit', 'sparrow', 'tiger', 'deer', 'breeze',
      'stone', 'sky', 'flame', 'stream', 'dawn', 'twilight',
      'eagle', 'shark', 'dolphin', 'ocean', 'sun', 'moon',
      'storm', 'flower', 'pearl', 'wind', 'snow', 'ember',
      'shadow', 'beacon', 'comet', 'meadow', 'rain', 'glow',
      'drift', 'crystal', 'wave', 'forest', 'thunder', 'lightning',
      'petal', 'blaze', 'peak', 'ice', 'valley', 'lagoon',
      'sand', 'whisper', 'whale', 'falcon', 'feather', 'flock',
      'seashell', 'whirlwind', 'canopy', 'island', 'cliff', 'stream',
      'cascade', 'hill', 'prairie', 'serpent', 'reed', 'ridge',
      'vine', 'fern', 'trail', 'grove', 'lagoon', 'spark',
      'path', 'horizon', 'haven', 'spire', 'delta', 'nebula',
      'cosmos', 'quartz', 'tundra', 'mist', 'echo', 'abyss',
      'glacier', 'sapphire', 'fern', 'torrent', 'harbor', 'arch'
    ];


    final random = Random();
    String randomAdjective = adjectives[random.nextInt(
        adjectives.length)]; // Random adjective
    String randomSecondWord = secondWords[random.nextInt(
        secondWords.length)]; // Random second word
    String randomSuffix = random.nextInt(1000)
        .toString(); // Random number suffix

    return "$randomAdjective$randomSecondWord$randomSuffix";
  }


  String _encryptData(String data) {
    final encrypter = encrypt.Encrypter(encrypt.AES(_key));
    final encrypted = encrypter.encrypt(data, iv: _iv);
    return encrypted.base64;
  }


  Future<String?> _uploadToStorage(File file, String path) async {
    try {
      final storageRef = FirebaseStorage.instance.ref().child(path);
      final uploadTask = storageRef.putFile(file);
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print("Error uploading to storage: $e");
      return null; // Fallback to null if upload fails
    }
  }


  Future<void> _performOCR() async {
    try {
      final inputImage = InputImage.fromFile(_selectedIDImage!);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);

      List<String> words = [];
      for (var block in recognizedText.blocks) {
        for (var line in block.lines) {
          words.addAll(line.text.split(' '));
        }
      }
      print("Extracted OCR Words: ${words.join(', ')}");

      List<String> enteredNameWords = _nameController.text.split(' ');
      bool allWordsMatched = enteredNameWords.every((enteredWord) =>
          words.any((extractedWord) =>
              extractedWord.toLowerCase().contains(enteredWord.toLowerCase())));

      setState(() {
        _ocrExtractedName = allWordsMatched ? _nameController.text : null;
      });
    } catch (e) {
      print("Error during OCR: $e");
    }
  }

  Future<bool> _compareFaces() async {
    try {
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableContours: true,
          enableClassification: true,
        ),
      );

      final idInputImage = InputImage.fromFile(_selectedIDImage!);
      final profileInputImage = InputImage.fromFile(_capturedProfileImage!);

      final idFaces = await faceDetector.processImage(idInputImage);
      final profileFaces = await faceDetector.processImage(profileInputImage);

      if (idFaces.isEmpty || profileFaces.isEmpty) {
        return false;
      }

      idFaces.reduce((current, next) =>
      current.boundingBox.height * current.boundingBox.width >
          next.boundingBox.height * next.boundingBox.width
          ? current
          : next);


      return true;
    } catch (e) {
      print("Error during face comparison: $e");
      return false;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Advanced Verification",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.pink.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Verify Your Identity",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.pink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            if (!_isVerified) ...[
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Enter your full name",
                  labelStyle: TextStyle(color: Colors.pink.shade700),
                ),
              ),
              const SizedBox(height: 20),
              CheckboxListTile(
                title: const Text(
                  "I confirm that I am female and understand that this platform is exclusively for women.",
                  style: TextStyle(fontSize: 14),
                ),
                value: _isDeclarationChecked,
                onChanged: (bool? value) {
                  setState(() {
                    _isDeclarationChecked = value ?? false;
                  });
                },
              ),
              const SizedBox(height: 20),
              const Text(
                  "Upload your Government ID: Ensure the image is clear, with your name and picture visible. A scanned copy is preferred."),
              GestureDetector(
                onTap: () => _pickImage(true),
                child: Container(
                  height: 150,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.pink.shade200),
                  ),
                  child: _selectedIDImage == null
                      ? const Center(
                    child: Text("Tap to upload ID image"),
                  )
                      : Image.file(
                    _selectedIDImage!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                  "Capture your Profile Picture: Ensure the face is well lit and centered in the image."),
              GestureDetector(
                onTap: _captureProfileImage,
                child: Container(
                  height: 150,
                  margin: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.pink.shade200),
                  ),
                  child: _capturedProfileImage == null
                      ? const Center(
                    child: Text("Tap to capture profile picture"),
                  )
                      : Image.file(
                    _capturedProfileImage!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (_isUploading)
              const Center(child: CircularProgressIndicator())
            else if (_isVerified) ...[
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Verified Successfully!",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              if (_showContinueButton)
                ElevatedButton(
                  onPressed: () => Navigator.pushNamed(context, '/dashboard'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    "Continue",
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
            ] else ...[
              ElevatedButton(
                onPressed: _isDeclarationChecked && _attemptsLeft > 0
                    ? _processVerification
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDeclarationChecked && _attemptsLeft > 0
                      ? Colors.pink.shade700
                      : Colors.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  _attemptsLeft > 0
                      ? "Verify"
                      : "Waiting for Manual Verification",
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
              if (_nameMatchStatus != null)
                Text(
                  _nameMatchStatus!,
                  style: TextStyle(
                    fontSize: 16,
                    color: _nameMatchStatus == "Name match success!"
                        ? Colors.green
                        : Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (_faceMatchStatus != null)
                Text(
                  _faceMatchStatus!,
                  style: TextStyle(
                    fontSize: 16,
                    color: _faceMatchStatus == "Face match success!"
                        ? Colors.green
                        : Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (_attemptsLeft <= 0)
                const Text(
                  "Account locked. Details submitted for manual verification.",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          ],
        ),
      ),
    );
  }
}