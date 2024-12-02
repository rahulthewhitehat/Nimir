import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class UnverifiedReportsSubmissionScreen extends StatefulWidget {
  const UnverifiedReportsSubmissionScreen({Key? key}) : super(key: key);

  @override
  _UnverifiedReportsSubmissionScreenState createState() =>
      _UnverifiedReportsSubmissionScreenState();
}

class _UnverifiedReportsSubmissionScreenState
    extends State<UnverifiedReportsSubmissionScreen> {
  final _formKey = GlobalKey<FormState>();
  String _selectedLanguage = 'English';
  String _description = '';
  File? _recordedVoiceFile;
  List<File> _mediaFiles = [];
  List<File> _screenshotFiles = [];
  bool _knowsCulprit = false;
  String _culpritName = '';
  int _culpritAge = 0;
  String _culpritDescription = '';

  FlutterSoundRecorder? _audioRecorder;
  FlutterSoundPlayer? _audioPlayer = FlutterSoundPlayer();
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = FlutterSoundRecorder();
    _audioPlayer = FlutterSoundPlayer();
    _initRecorder();
    _initPlayer();
  }

  Future<void> _initRecorder() async {
    try {
      if (_audioRecorder == null) return;
      if (await Permission.microphone.request().isGranted) {
        await _audioRecorder!.openRecorder();
      } else {
        throw Exception("Microphone permission not granted");
      }
    } catch (e) {
      print("Recorder initialization failed: $e");
    }
  }

  Future<void> _initPlayer() async {
    try {
      await _audioPlayer!.openPlayer();
    } catch (e) {
      print("Player initialization failed: $e");
    }
  }

  @override
  void dispose() {
    _audioRecorder?.closeRecorder();
    _audioPlayer?.closePlayer();
    super.dispose();
  }

  final aesKey = encrypt.Key.fromUtf8('nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
  final aesIV = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV
  final encrypter = encrypt.Encrypter(
    encrypt.AES(encrypt.Key.fromUtf8('nmR89ujXkMwpS78N76gxZ34vT9u34WR8'),
        mode: encrypt.AESMode.cbc),
  );

  String encryptText(String plainText) {
    final encrypted = encrypter.encrypt(plainText, iv: aesIV);
    return encrypted.base64;
  }

  Future<void> _startRecording() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/temp_audio.wav';

      await _audioRecorder!.startRecorder(toFile: filePath);
      setState(() {
        isRecording = true;
        _recordedVoiceFile = File(filePath);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to start recording.")),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _audioRecorder!.stopRecorder();
      setState(() {
        isRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Recording stopped successfully.")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to stop recording.")),
      );
    }
  }

  Future<void> _playRecordedVoice() async {
    try {
      if (_recordedVoiceFile == null) throw Exception("No recording available.");

      await _audioPlayer!.startPlayer(
        fromURI: _recordedVoiceFile!.path,
        codec: Codec.defaultCodec,
        whenFinished: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Playback completed.")),
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to play recording.")),
      );
    }
  }

  Future<void> _pickFiles({required bool isScreenshot}) async {
    final List<XFile>? pickedFiles = await ImagePicker().pickMultiImage();
    if (pickedFiles != null) {
      setState(() {
        if (isScreenshot) {
          _screenshotFiles =
              pickedFiles.map((file) => File(file.path)).toList();
        } else {
          _mediaFiles = pickedFiles.map((file) => File(file.path)).toList();
        }
      });
    }
  }

  Future<void> _submitReport() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      try {
        final encryptedDescription = encryptText(_description);

        final encryptedCulpritName =
        _knowsCulprit ? encryptText(_culpritName) : null;

        final encryptedCulpritDescription =
        _knowsCulprit ? encryptText(_culpritDescription) : null;

        final uploadedVoicePath = await _uploadFile(
          file: _recordedVoiceFile,
          folder: 'audio',
        );

        final uploadedMediaPaths = await Future.wait(
          _mediaFiles.map((file) => _uploadFile(file: file, folder: 'media')),
        );

        final uploadedScreenshotPaths = await Future.wait(
          _screenshotFiles
              .map((file) => _uploadFile(file: file, folder: 'screenshots')),
        );

        await FirebaseFirestore.instance.collection('unverified_reports').add({
          'language': _selectedLanguage,
          'description': encryptedDescription,
          'voicePath': uploadedVoicePath,
          'media': uploadedMediaPaths,
          'screenshots': uploadedScreenshotPaths,
          'culpritDetails': _knowsCulprit
              ? {
            'name': encryptedCulpritName,
            'age': _culpritAge,
            'description': encryptedCulpritDescription,
          }
              : null,
          'timestamp': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Anonymous report submitted successfully!")),
        );

        setState(() {
          _description = '';
          _recordedVoiceFile = null;
          _mediaFiles = [];
          _screenshotFiles = [];
          _knowsCulprit = false;
          _culpritName = '';
          _culpritAge = 0;
          _culpritDescription = '';
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to submit anonymous report.")),
        );
      }
    }
  }

  Future<String?> _uploadFile({required File? file, required String folder}) async {
    if (file == null) return null;

    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final storageRef =
      FirebaseStorage.instance.ref().child('unverified_reports/$folder/$fileName');

      final task = storageRef.putFile(file);
      final downloadUrl = await (await task).ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      return null;
    }
  }

  Widget _buildFilePreview(List<File> files) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: files
          .map((file) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          file,
          height: 120,
          width: 120,
          fit: BoxFit.cover,
        ),
      ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Submit Anonymous Report", style: TextStyle(color:Colors.white)),
        backgroundColor: Colors.pink.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedLanguage,
                items: ['English', 'Tamil', 'Hindi']
                    .map((lang) => DropdownMenuItem(
                  value: lang,
                  child: Text(lang),
                ))
                    .toList(),
                onChanged: (value) => setState(() => _selectedLanguage = value!),
                decoration: InputDecoration(
                  labelText: "Select Language",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField("Incident Description", (value) => _description = value!),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  title: const Text("Do you know the culprit?"),
                  value: _knowsCulprit,
                  onChanged: (value) => setState(() => _knowsCulprit = value),
                ),
              ),
              if (_knowsCulprit) ...[
                _buildTextField("Culprit's Name", (value) => _culpritName = value!),
                const SizedBox(height: 16),
                _buildTextField(
                  "Culprit's Age",
                      (value) => _culpritAge = int.tryParse(value!) ?? 0,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  "Culprit's Description",
                      (value) => _culpritDescription = value!,
                  maxLines: 3,
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: Icon(
                  isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                ),
                label: Text(
                  isRecording ? "Stop Recording" : "Record Voice",
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                onPressed: isRecording ? _stopRecording : _startRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              if (_recordedVoiceFile != null)
                ListTile(
                  title: const Text("Recorded Voice"),
                  trailing: IconButton(
                    icon: Icon(Icons.play_arrow, color: Colors.pink.shade700),
                    onPressed: _playRecordedVoice,
                  ),
                ),
              const SizedBox(height: 16),
              _buildUploadButton(
                icon: Icons.upload,
                label: "Select Media",
                onPressed: () => _pickFiles(isScreenshot: false),
              ),
              const SizedBox(height: 8),
              _buildUploadButton(
                icon: Icons.screenshot,
                label: "Select Screenshots",
                onPressed: () => _pickFiles(isScreenshot: true),
              ),
              if (_mediaFiles.isNotEmpty) _buildFilePreview(_mediaFiles),
              if (_screenshotFiles.isNotEmpty) _buildFilePreview(_screenshotFiles),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _submitReport,
                child: Text(
                  "Submit Report",
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, Function(String?) onSaved,
      {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey.shade100,
      ),
      onSaved: onSaved,
    );
  }

  Widget _buildUploadButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.pink.shade700,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
