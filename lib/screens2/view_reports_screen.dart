import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class ViewReportScreen extends StatelessWidget {
  final _key = encrypt.Key.fromUtf8('nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
  final _iv = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV
  late final encrypter = encrypt.Encrypter(
    encrypt.AES(_key, mode: encrypt.AESMode.cbc),
  );

  String decryptText(String encryptedText) {
    try {
      return encrypter.decrypt64(encryptedText, iv: _iv);
    } catch (e) {
      return "Decryption failed";
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text("View Reports", style:TextStyle(color:Colors.white)),
        backgroundColor: Colors.pink.shade700,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .where('userId', isEqualTo: user?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Text(
                "No reports submitted yet.",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            );
          }

          final reports = snapshot.data!.docs;

          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              final reportData = report.data() as Map<String, dynamic>;

              // Decrypt fields for display
              final decryptedDescription =
              decryptText(reportData['description'] ?? '');
              final decryptedCulpritDetails = reportData['culpritDetails'] != null
                  ? {
                'name': decryptText(reportData['culpritDetails']['name']),
                'description': decryptText(
                    reportData['culpritDetails']['description']),
                'age': reportData['culpritDetails']['age']
              }
                  : null;

              return Card(
                margin: EdgeInsets.all(10),
                child: ListTile(
                  contentPadding: EdgeInsets.all(10),
                  title: Text(
                    decryptedDescription.isNotEmpty
                        ? decryptedDescription
                        : "No description available",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    "Status: ${reportData['status'] ?? 'Submitted'}",
                    style: TextStyle(
                      color: reportData['status'] == 'Submitted'
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ),
                  trailing: Icon(Icons.arrow_forward, color: Colors.pink.shade700),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportDetailsPage(
                          reportId: report.id,
                          reportData: {
                            ...reportData,
                            'description': decryptedDescription,
                            'culpritDetails': decryptedCulpritDetails,
                          },
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ReportDetailsPage extends StatefulWidget {
  final String reportId;
  final Map<String, dynamic> reportData;

  const ReportDetailsPage({
    required this.reportId,
    required this.reportData,
  });

  @override
  _ReportDetailsPageState createState() => _ReportDetailsPageState();
}

class _ReportDetailsPageState extends State<ReportDetailsPage> {
  final ImagePicker _picker = ImagePicker();
  FlutterSoundRecorder? _audioRecorder;
  String? _voicePath;
  Map<String, dynamic> updatedReportData = {};

  @override
  void initState() {
    super.initState();
    _audioRecorder = FlutterSoundRecorder();
    _initRecorder();
    _fetchReportData();
  }

  Future<void> _initRecorder() async {
    await _audioRecorder!.openRecorder();
    if (!await Permission.microphone.isGranted) {
      await Permission.microphone.request();
    }
  }

  Future<void> _fetchReportData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('reports')
          .doc(widget.reportId)
          .get();
      if (doc.exists) {
        setState(() {
          updatedReportData = doc.data()!;
        });
      }
    } catch (e) {
      print("Error fetching report data: $e");
    }
  }

  Future<void> _startRecording() async {
    final tempDir = await getTemporaryDirectory();
    _voicePath = '${tempDir.path}/temp_audio.wav';
    await _audioRecorder!.startRecorder(toFile: _voicePath);
    setState(() {});
  }

  Future<void> _stopRecording(String reportId, String username) async {
    await _audioRecorder!.stopRecorder();

    if (_voicePath != null) {
      final fileName = "voice_${DateTime
          .now()
          .millisecondsSinceEpoch}.wav";
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('reports/$username/voice/$fileName');

      final uploadTask = storageRef.putFile(File(_voicePath!));
      final downloadUrl = await (await uploadTask).ref.getDownloadURL();

      await _updateFirestore(reportId, downloadUrl, "voice");
      setState(() {
        _voicePath = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Voice recording added successfully!")),
      );
      _fetchReportData(); // Refresh report data
    }
  }

  Future<void> _uploadFile(String reportId, String fileType,
      String username) async {
    final List<XFile>? pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles != null) {
      for (var file in pickedFiles) {
        final fileName =
            "${fileType}_${DateTime
            .now()
            .millisecondsSinceEpoch}.${file.name
            .split('.')
            .last}";
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('reports/$username/$fileType/$fileName');

        final uploadTask = storageRef.putFile(File(file.path));
        final downloadUrl = await (await uploadTask).ref.getDownloadURL();

        await _updateFirestore(reportId, downloadUrl, fileType);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$fileType uploaded successfully!")),
      );
      _fetchReportData(); // Refresh report data
    }
  }

  Future<void> _updateFirestore(String reportId, String downloadUrl, String type) async {
    final reportRef = FirebaseFirestore.instance.collection('reports').doc(reportId);
    final snapshot = await reportRef.get();

    // Handle voice as an array
    if (type == "voice") {
      final currentVoice = snapshot.data()?['voice'] ?? [];
      currentVoice.add(downloadUrl);

      await reportRef.update({'voice': currentVoice});
    } else {
      // Handle other media types
      final currentMedia = snapshot.data()?[type] ?? [];
      currentMedia.add(downloadUrl);

      await reportRef.update({type: currentMedia});
    }
  }


  Widget buildEvidenceList(String title, List<dynamic>? mediaUrls) {
    if (mediaUrls == null || mediaUrls.isEmpty) {
      return Container();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: mediaUrls.map((url) {
            String fileType = getFileType(url);
            if (fileType == "Voice") {
              // Play voice recordings
              return GestureDetector(
                onTap: () => _playVoiceRecording(url),
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    width: 100,
                    height: 100,
                    child: Center(
                      child: Icon(Icons.mic, color: Colors.purple),
                    ),
                  ),
                ),
              );
            } else if (fileType == "Photo") {
              // Full-screen image preview
              return GestureDetector(
                onTap: () => _showFullScreenImage(context, url),
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(Icons.broken_image, color: Colors.red),
                        );
                      },
                    ),
                  ),
                ),
              );
            } else {
              // Render non-image file icons (e.g., video)
              return GestureDetector(
                onTap: () => openFile(url),
                child: Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    width: 100,
                    height: 100,
                    child: Center(
                      child: getIconForFileType(fileType),
                    ),
                  ),
                ),
              );
            }
          }).toList(),
        ),
      ],
    );
  }


  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: EdgeInsets.all(20),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(Icons.broken_image, color: Colors.red),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }



  String getFileType(String url) {
    if (url.contains(".jpg") || url.contains(".jpeg") || url.contains(".png")) {
      return "Photo";
    } else if (url.contains(".mp4") || url.contains(".mkv")) {
      return "Video";
    } else if (url.contains(".wav") || url.contains(".mp3")) {
      return "Voice";
    } else {
      return "File";
    }
  }

  Icon getIconForFileType(String fileType) {
    switch (fileType) {
      case "Photo":
        return Icon(Icons.image, color: Colors.white);
      case "Video":
        return Icon(Icons.video_camera_back, color: Colors.white);
      case "Voice":
        return Icon(Icons.mic, color: Colors.white);
      default:
        return Icon(Icons.attach_file, color: Colors.white);
    }
  }

  void openFile(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  void dispose() {
    _audioRecorder?.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text("Report Details", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.pink.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Card(
              elevation: 4,
              margin: EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Description:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(widget.reportData['description'] ?? 'No description'),
                    SizedBox(height: 16),
                    Text(
                      "Status:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(widget.reportData['status'] ?? 'Submitted'),
                  ],
                ),
              ),
            ),
            if (updatedReportData['media'] != null)
              buildEvidenceList("Uploaded Media", updatedReportData['media']),
            if (updatedReportData['screenshots'] != null)
              buildEvidenceList(
                  "Uploaded Screenshots", updatedReportData['screenshots']),
            if (updatedReportData['voice'] != null)
              buildEvidenceList(
                  "Uploaded Voice Recordings", updatedReportData['voice']),
            if (_tempMedia.isNotEmpty ||
                _tempScreenshots.isNotEmpty ||
                _tempVoice != null) ...[
              SizedBox(height: 16),
              Text(
                "Pending Files for Submission:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._tempMedia.map((file) => _buildTempFilePreview(file, "Photo")),
                  ..._tempScreenshots
                      .map((file) => _buildTempFilePreview(file, "Screenshot")),
                  if (_tempVoice != null)
                    _buildTempFilePreview(_tempVoice!, "Voice"),
                ],
              ),
              SizedBox(height: 16),
            ],
            ElevatedButton.icon(
              icon: Icon(Icons.photo_camera, color: Colors.white),
              label:
              Text("Upload Photos", style: TextStyle(color: Colors.white)),
              onPressed: () =>
                  _uploadFileTemp("media"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.video_camera_back, color: Colors.white),
              label:
              Text("Upload Videos", style: TextStyle(color: Colors.white)),
              onPressed: () =>
                  _uploadFileTemp("video"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.screenshot, color: Colors.white),
              label: Text("Upload Screenshots",
                  style: TextStyle(color: Colors.white)),
              onPressed: () =>
                  _uploadFileTemp("screenshot"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.pink.shade700),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.mic, color: Colors.white),
              label: Text(
                _audioRecorder!.isRecording ? "Stop Recording" : "Record Voice",
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () async {
                if (_audioRecorder!.isRecording) {
                  await _stopRecordingTemp();
                } else {
                  await _startRecordingTemp();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Recording started...")),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink.shade700,
              ),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.cloud_upload, color: Colors.white),
              label:
              Text("Submit All", style: TextStyle(color: Colors.white)),
              onPressed: () =>
                  _submitAllFiles(widget.reportId, user?.email ?? "Anonymous"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitAllFiles(String reportId, String username) async {
    try {
      if (_tempMedia.isEmpty && _tempScreenshots.isEmpty && _tempVoice == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No files to submit.")),
        );
        return;
      }

      // Upload temp media
      for (var file in _tempMedia) {
        final fileName = "media_${DateTime.now().millisecondsSinceEpoch}.${file.path.split('.').last}";
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('reports/$username/media/$fileName');
        final uploadTask = storageRef.putFile(file);
        final downloadUrl = await (await uploadTask).ref.getDownloadURL();
        await _updateFirestore(reportId, downloadUrl, "media");
      }

      // Upload temp screenshots
      for (var file in _tempScreenshots) {
        final fileName = "screenshot_${DateTime.now().millisecondsSinceEpoch}.${file.path.split('.').last}";
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('reports/$username/screenshot/$fileName');
        final uploadTask = storageRef.putFile(file);
        final downloadUrl = await (await uploadTask).ref.getDownloadURL();
        await _updateFirestore(reportId, downloadUrl, "screenshots");
      }

      // Upload voice
      if (_tempVoice != null) {
        final fileName = "voice_${DateTime.now().millisecondsSinceEpoch}.wav";
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('reports/$username/voice/$fileName');
        final uploadTask = storageRef.putFile(_tempVoice!);
        final downloadUrl = await (await uploadTask).ref.getDownloadURL();
        await _updateFirestore(reportId, downloadUrl, "voice");
      }

      // Clear temp storage after successful upload
      setState(() {
        _tempMedia.clear();
        _tempScreenshots.clear();
        _tempVoice = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("All files submitted successfully!")),
      );

      // Refresh data
      _fetchReportData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error submitting files: $e")),
      );
    }
  }



  List<File> _tempMedia = [];
  List<File> _tempScreenshots = [];
  File? _tempVoice;

  Future<void> _uploadFileTemp(String fileType) async {
    final List<XFile>? pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles != null) {
      for (var file in pickedFiles) {
        final tempFile = File(file.path);
        setState(() {
          if (fileType == "media") {
            _tempMedia.add(tempFile);
          } else if (fileType == "screenshot") {
            _tempScreenshots.add(tempFile);
          }
        });
      }
    }
  }

  Future<void> _startRecordingTemp() async {
    final tempDir = await getTemporaryDirectory();
    _voicePath = '${tempDir.path}/temp_audio.wav';
    await _audioRecorder!.startRecorder(toFile: _voicePath);
    setState(() {});
  }

  Future<void> _stopRecordingTemp() async {
    await _audioRecorder!.stopRecorder();
    if (_voicePath != null) {
      setState(() {
        _tempVoice = File(_voicePath!);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Voice recording ready for submission.")),
      );
    }
  }

  Widget _buildTempFilePreview(File file, String fileType) {
    if (fileType == "Photo") {
      return GestureDetector(
        onTap: () => _showFullScreenImage(context, file.path),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Icon(Icons.broken_image, color: Colors.red),
                );
              },
            ),
          ),
        ),
      );
    } else if (fileType == "Voice") {
      return GestureDetector(
        onTap: () => _playVoiceRecording(file.path),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Container(
            width: 100,
            height: 100,
            child: Center(
              child: Icon(Icons.mic, color: Colors.purple),
            ),
          ),
        ),
      );
    } else {
      return Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Container(
          width: 100,
          height: 100,
          child: Center(
            child: getIconForFileType(fileType),
          ),
        ),
      );
    }
  }
  void _playVoiceRecording(String pathOrUrl) async {
    try {
      final player = FlutterSoundPlayer();
      await player.openPlayer();
      await player.startPlayer(
        fromURI: pathOrUrl,
        codec: Codec.defaultCodec,
        whenFinished: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Playback completed.")),
          );
          player.closePlayer();
        },
      );
    } catch (e) {
      print("Error playing voice recording: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to play the recording.")),
      );
    }
  }



}



