import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/speech/v1.dart' as speech;
import 'package:googleapis_auth/auth_io.dart';
import 'package:dart_sentiment/dart_sentiment.dart';
import 'package:text2pdf/text2pdf.dart' as makepdf;


final aesKey = encrypt.Key.fromUtf8('nmR89ujXkMwpS78N76gxZ34vT9u34WR8'); // 32-byte key
final aesIV = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St'); // 16-byte IV
final encrypter = encrypt.Encrypter(encrypt.AES(aesKey, mode: encrypt.AESMode.cbc));
var decryptdes = "";
var trans = "";
var screenShots = "";
var decryptedCulpritDetails = "";
var sentimentReport = "";
var encryptedReport1 = "";
var encryptedReport2 ="";
var encryptedReport3 = "";
var fullygenreport ="";

// Function to decrypt a string
String decryptText(String encryptedText) {
  try {
    return encrypter.decrypt64(encryptedText, iv: aesIV);
  } catch (e) {
    print("Error decrypting text: $e");
    return "Decryption failed";
  }
}


var decryptedCulpName;
var culpritage;
var decryptedCulpDes;

Future<void> fetchAndDecryptReportDetails(String reportId) async {
  try {
    // Fetch the report document from Firestore
    final reportSnapshot =
    await FirebaseFirestore.instance.collection('reports').doc(reportId).get();

    if (!reportSnapshot.exists) {
      print("Report with ID $reportId not found.");
      return;
    }

    // Extract report data
    final reportData = reportSnapshot.data();
    if (reportData == null) {
      print("No data found for report ID $reportId.");
      return;
    }

    // Decrypt description
    final encryptedDescription = reportData['description'];
    final decryptedDescription = decryptText(encryptedDescription);
    decryptdes = decryptedDescription;
    // Decrypt culprit details (if available)
    String? decryptedCulpritName;
    String? decryptedCulpritDescription;
    if (reportData['culpritDetails'] != null) {
      final culpritDetails = reportData['culpritDetails'];
      decryptedCulpritName = decryptText(culpritDetails['name']);
      decryptedCulpritDescription = decryptText(culpritDetails['description']);
    }


    // Store decrypted details in variables
    final String userId = reportData['userId'];
    final String selectedLanguage = reportData['language'];
    final String voiceFilePath = reportData['voicePath'] ?? "No voice file provided";
    final List<dynamic> mediaFiles = reportData['media'] ?? [];
    final List<dynamic> screenshotFiles = reportData['screenshots'] ?? [];
    final int? culpritAge = reportData['culpritDetails']?['age'];
    // Print decrypted report details
    print("Decrypted Report Details for ID: $reportId");
    print("User ID: $userId");
    print("Selected Language: $selectedLanguage");
    print("Description (Decrypted): $decryptedDescription");
    print("Voice File Path: $voiceFilePath");
    print("Media Files: $mediaFiles");
    print("Screenshot Files: $screenshotFiles");

    if (decryptedCulpritName != null && decryptedCulpritDescription != null) {
      print("Culprit Details:");
      print("- Name (Decrypted): $decryptedCulpritName");
      decryptedCulpName  = decryptedCulpritName;
      print("- Age: $culpritAge");
      culpritage = culpritAge;
      print("- Description (Decrypted): $decryptedCulpritDescription");
      decryptedCulpDes = decryptedCulpritDescription;
    } else {
      print("Culprit Details: Not provided");
    }
    print("Timestamp: ${reportData['timestamp']}");
  } catch (e) {
    print("Error fetching or decrypting report details: $e");
  }

  decryptedCulpritDetails = "Name of the culprit : $decryptedCulpName, Age of the culprit is $culpritage, Description about the user is $decryptedCulpDes";
}

Future<File?> downloadFile(String url, String fileName) async {
  try {
    // Get the directory for temporary storage
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/$fileName';

    // Download the file
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      // Write the file to the local system
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      print("File downloaded successfully: $filePath");
      return file;
    } else {
      print("Failed to download file. Status code: ${response.statusCode}");
      return null;
    }
  } catch (e) {
    print("Error downloading file: $e");
    return null;
  }
}

Future<void> processVoiceFile(String voiceFileUrl) async {
  // Extract file name from the URL
  final fileName = voiceFileUrl.split('/').last.split('?').first;

  // Download the file locally
  final localFile = await downloadFile(voiceFileUrl, fileName);

  if (localFile != null) {
    // Pass the local file path to the speech-to-text conversion function
    await convertSpeechToText(localFile.path);
  } else {
    print("Failed to process voice file. Download error.");
  }
}


// Function to fetch voice file and convert it to text

Future<void> convertSpeechToText(String voiceFilePath) async {
  // Replace with your JSON content
  const jsonContent = '''
{
  "type": "service_account",
  "project_id": "nimir-e76fc",
  "private_key_id": "0f5aa4bd8112e81da9a98e7de4a3fb84ab60e7b6",
  "private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCj6CX82f1O4MmL\\n42UeT1EzmRMgYaCwxXeDeUuUlkWu6Ii1iCd3e0Psy/MsdGSca2ZfKVsPwbOUCoOi\\nkR2Pu0ZyK17AF/Nl+JAWlVyp6xp2245STCoJ1E+W1utnGwy20gJFh5HQMa4uiqZg\\nHr5QuXb03QZ7MTo/X8T81SrIcvjeoU1mqv5UFV9+kbh5eVvT8pSs/ZB1n5NehGDK\\n8+CEMkzrouopvIik4pra/g0jfo8muK1IfkE6LHRpU/tXfoS1JUNDzssq7ibY9m9U\\nT9f+r/VnpM6zYQm7teNM2+Jv07AwDTv3gbnHe9wGXlUjTTKPMJy/JkKyFTt46+2f\\nrjL4c6udAgMBAAECggEAAIY9RjTQVFCbHyEdcV5hl8pVPv+boFUmumXzRvNqylIg\\nyyviAcYu2R1slrzR7D+FC/2O4VsGSbf1jy9AVUsNFk/AitlzbuUVA5gmEWkYzuk0\\nPbEpWpoHndJBiIqT8isef2hyn/mODBoSHtvvp0R19qHqY7nW7N2lPLCAkDRF9Y20\\nkzR3lcYQfj//bQo4GaMWiZkDfBYEq4CiArmtsygoLvWuHaai5J5w0WqD7BMYpqVb\\nofeIjfUMiSUH+MZ65YM3cTao4u9xvXqMsBtCaRx60RxTiuznfsicmkip5JhyZPCj\\n6eId+gER4ADulYH35TgYKRnVDPmjypZUVxSGKnHbZQKBgQDZnAX3GOSqdxkFFa34\\n0JV8k4KlkRc3IJYKl7yiiGeWgirKWdfPN/xYLsEwipiRlCZCxqXl6BTkwFj8wdBU\\neAXph/vLm8si5UAyqBotoJ/Ah2DxA94lZuC/cJgRvx92+Ngldj5m2Ro5NxNKjaqo\\nlyEmbo1wGbIGaylAVy9iCCAzEwKBgQDA0rurXP3p9i9uJ5XmPb2+8bxX2IXPMVn4\\nj5OEmEC7j3yCTsWJFp2wVFOlvyInZpsHniHLDWMRQVGK085VsPpef98WCAR643w9\\nf+lVQoWCTFncKEAJv73gbTyuL625WpLgJG46xTfc65yJb+yG5CFQOdBlWUYwTLJ8\\nWcFDV6zMjwKBgFHIF13UFywRcm+8xBM8oNGexnze2HC5aGo2uIgE55li9h3yQe74\\nxXeGqshJbilYGkECUxria+fEei0T0e3M5bvshS7yMBe/PK9NCfmX4jIDLuWlZHl9\\n/n00HZKd139o6iK6G52ffgF+t1tPfpG5qpW8+p7kqUlMQMaTfZVEJIXNAoGAPd2f\\nDu0oHn+5WgtjYdrfXTssJbc3v3FjH4fZWcqLwmHYHeruH/zcnS2BJQW9DI00Im6P\\nAxoJdgjSA8vPQNkmi1lVlzj9Tvxb6VN35r4QHe0nS6ayXS5i2nXR6UUs5PJ1e2rU\\n3xBVyxDhSYtahTD+q0HRZiMNjQOepJ0bj+K6c2sCgYEAiVdrJlTZuZRtLJ3jYlpx\\nOAej4lSOu16yGL41agMQd1FzQ3jyBYfqSuuO6Ymi9LTTAjBBgk/ykZ+lOV157wlv\\nOThVPV7WbOdKRFYg38jXPxjf+FlyfT4c/XDNfih8cxuPUG6qQz1AGL/dR3aBvATt\\nJRGMZPQp0iwgH7BG1uXJQi8=\\n-----END PRIVATE KEY-----\\n",
  "client_email": "speech-to-text-service@nimir-e76fc.iam.gserviceaccount.com",
  "client_id": "114606926417960703556",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/speech-to-text-service%40nimir-e76fc.iam.gserviceaccount.com",
  "universe_domain": "googleapis.com"
}
''';


  // Parse the JSON string to create ServiceAccountCredentials
  final credentials = ServiceAccountCredentials.fromJson(jsonContent);

  // Define the scopes required for the Speech-to-Text API
  const scopes = [speech.SpeechApi.cloudPlatformScope];

  // Authenticate
  final httpClient = await clientViaServiceAccount(credentials, scopes);
  final speechApi = speech.SpeechApi(httpClient);

  try {
    // Read the file and encode it in base64
    final audioBytes = await File(voiceFilePath).readAsBytes();
    final audioContent = base64Encode(audioBytes);

    // Configure the request
    final request = speech.RecognizeRequest(
      config: speech.RecognitionConfig(
        encoding: 'LINEAR16',
        sampleRateHertz: 16000,
        languageCode: 'en-US',
      ),
      audio: speech.RecognitionAudio(
        content: audioContent,
      ),
    );

    // Call the Speech-to-Text API
    final response = await speechApi.speech.recognize(request);

    // Handle the response
    if (response.results != null && response.results!.isNotEmpty) {
      final transcript = response.results!
          .map((result) => result.alternatives!.first.transcript)
          .join('\n');
      print('Transcript: $transcript');
      trans = transcript;
    } else {
      print('No transcript available.');
    }
  } catch (e) {
    print('Error during speech-to-text conversion: $e');
  } finally {
    httpClient.close();
  }
}


Future<void> processScreenshots(String reportId) async {
  try {
    // Fetch the report document from Firestore
    final reportSnapshot =
    await FirebaseFirestore.instance.collection('reports').doc(reportId).get();

    if (!reportSnapshot.exists) {
      print("Report with ID $reportId not found.");
      return;
    }

    // Extract the screenshots URLs
    final reportData = reportSnapshot.data();
    if (reportData == null || reportData['screenshots'] == null) {
      print("No screenshots found for report ID $reportId.");
      return;
    }

    final screenshotUrls = List<String>.from(reportData['screenshots']);
    print("Found ${screenshotUrls.length} screenshots. Downloading and processing...");

    // Prepare to store the extracted text
    final List<String> extractedTexts = [];

    for (var i = 0; i < screenshotUrls.length; i++) {
      final url = screenshotUrls[i];
      print("Processing screenshot $i...");

      // Download the screenshot locally
      final localFile = await downloadFile2(url, 'screenshot_$i.png');
      if (localFile == null) {
        print("Failed to download screenshot $i.");
        continue;
      }

      // Perform OCR on the downloaded file
      final inputImage = InputImage.fromFile(localFile);
      final textRecognizer = TextRecognizer();
      final recognizedText = await textRecognizer.processImage(inputImage);

      // Collect recognized text
      for (var block in recognizedText.blocks) {
        for (var line in block.lines) {
          extractedTexts.add(line.text);
        }
      }
    }

    // Display the extracted text in the terminal
    if (extractedTexts.isNotEmpty) {
      print("Extracted Text from Screenshots:");
      for (var text in extractedTexts) {
        print(text);
      }
    } else {
      print("No text could be extracted from the screenshots.");
    }
    screenShots = extractedTexts.join(",");

    // Optionally: Store the extracted text in Firestore
   // await FirebaseFirestore.instance
     //   .collection('reports')
      //  .doc(reportId)
      //  .update({'screenshotTexts': extractedTexts});
   // print("Extracted texts stored in Firestore under 'screenshotTexts'.");

  } catch (e) {
    print("Error during screenshot processing: $e");
  }
}

// Helper function to download a file
Future<File?> downloadFile2(String url, String fileName) async {
  try {
    final directory = await getTemporaryDirectory();
    final localPath = '${directory.path}/$fileName';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      print("Failed to download file from $url. Status code: ${response.statusCode}");
      return null;
    }
  } catch (e) {
    print("Error downloading file from $url: $e");
    return null;
  }
}

Future<void> processFullReport(String reportId) async {
  try {
    print("Starting to process report with ID: $reportId");

    // Step 1: Fetch and decrypt report details
    print("\nStep 1: Fetching and decrypting report details...");
    await fetchAndDecryptReportDetails(reportId);
    print("Decrypted Description: $decryptdes");
    print("Decrypted Culprit Details: $decryptedCulpritDetails");

    // Step 2: Process voice file for speech-to-text
    print("\nStep 2: Processing voice file for speech-to-text...");
    final reportSnapshot =
    await FirebaseFirestore.instance.collection('reports').doc(reportId).get();
    if (reportSnapshot.exists) {
      final reportData = reportSnapshot.data();
      if (reportData != null && reportData['voicePath'] != null) {
        final voiceFileUrl = reportData['voicePath'];
        await processVoiceFile(voiceFileUrl);
        print("Voice Transcript: $trans");
      } else {
        print("No voice file available for this report.");
      }
    } else {
      print("Report not found. Skipping voice file processing.");
    }

    // Step 3: Process screenshots for OCR
    print("\nStep 3: Processing screenshots for OCR...");
    await processScreenshots(reportId);
    print("Extracted Screenshot Texts: $screenShots");

    // Step 4: Perform sentiment analysis
    print("\nStep 4: Performing sentiment analysis...");
    await performSentimentAnalysis(decryptdes, trans);
    print("Sentiment Report: $sentimentReport");

    // Step 5: Generate the detailed report
    print("\nStep 5: Generating detailed report...");
    await generateDetailedReport(
      description: decryptdes,
      voiceTranscript: trans,
      extractedTextFromScreenshots: screenShots,
      culpritDetails: decryptedCulpritDetails,
      sentimentAnalysisReport: sentimentReport,
      reportId: reportId
    );

    print("\nAll steps completed for report ID: $reportId.");
  } catch (e) {
    print("Error processing full report with ID $reportId: $e");
  }
}


final Map<String, int> customWords = {
  // Negative words (Sad, Fearful, Angry, Emotional, etc.)
  "fear": -5,
  "threatened": -4,
  "violated": -5,
  "stalking": -4,
  "unsafe": -5,
  "objectified": -4,
  "distressed": -5,
  "blackmail": -5,
  "aggressive": -4,
  "unsettling": -3,
  "intrusive": -3,
  "uncomfortable": -3,
  "harassed": -5,
  "abuse": -5,
  "abusive": -5,
  "abused": -5,
  "vocal": -3,
  "sexual": -5,
  "molested": -5,
  "exploited": -5,
  "assaulted": -5,
  "assault": -5,
  "intimidated": -4,
  "demeaned": -4,
  "humiliated": -5,
  "shamed": -5,
  "shameful": -4,
  "sorrowful": -4,
  "sad": -3,
  "desperate": -3,
  "depressed": -4,
  "lonely": -3,
  "isolated": -3,
  "anxious": -4,
  "anxiety": -4,
  "panic": -4,
  "terrified": -5,
  "traumatized": -5,
  "horrified": -5,
  "crying": -3,
  "weep": -3,
  "frustrated": -3,
  "vexed": -3,
  "agitated": -3,
  "flustered": -3,
  "angered": -4,
  "rage": -4,
  "hostile": -4,
  "furious": -4,
  "annoyed": -3,
  "irritated": -3,
  "betrayed": -5,
  "paranoid": -4,
  "heartbroken": -4,
  "shattered": -4,
  "broken": -4,
  "mistreated": -5,
  "threatening": -4,
  "violent": -5,
  "insulted": -4,
  "disrespected": -4,
  "inappropriate": -4,
  "coerced": -4,
  "pressured": -3,
  "unethical": -4,
  "unjust": -4,
  "wronged": -4,
  "manipulated": -4,
  "hurt": -3,
  "demeaning": -4,
  "sickening": -4,
  "victimized": -5,
  "disgusting": -5,
  "repulsive": -5,
  "offended": -3,
  "mocked": -4,
  "ridiculed": -4,
  "bullied": -5,
  "threats": -4,
  "guilt": -3,
  "regret": -3,
  "ashamed": -4,
  "despair": -4,
  "anguish": -4,
  "trembling": -3,
  "nervous": -3,
  "uneasy": -3,
  "restless": -3,
  "overwhelmed": -3,
  "cry": -3,
  "sob": -3,
  "tears": -3,
  "bitter": -3,
  "fearful": -4,
  "dreadful": -4,
  "outraged": -4,
  "yelled": -3,
  "screamed": -3,
  "hopeless": -4,
  "defeated": -4,
  "worthless": -4,
  "degraded": -5,
  "insulting": -4,
  "mistreatment": -5,
  "abandonment": -3,
  "hopelessness": -4,
  "violation": -5,
  "sadness": -3,
  "embarrassed": -3,
  "awkward": -3,
  "forced": -4,
  "reluctant": -3,
  "apologetic": -2,
  "apology": -2,

  // Positive words (Support, Empowerment, Respect)
  "professional": 2,
  "supportive": 4,
  "respectful": 3,
  "empowered": 4,
  "safe": 3,
  "secure": 3,
  "comfortable": 3,
  "encouraged": 4,
  "hopeful": 3,
  "kind": 3,
  "positive": 3,
  "uplifted": 4,
  "confident": 4,
  "encouraging": 3,
  "empathetic": 4,
  "understanding": 4,
  "relieved": 3,
  "assisted": 3,
  "helpful": 3,
  "trusted": 4,
  "sympathetic": 4,
  "considerate": 4,
  "grateful": 3,
  "thankful": 3,
  "appreciative": 3,
  "honest": 3,
  "truthful": 3,
  "sincere": 3,
  "reassured": 3,
  "motivated": 4,
  "inspired": 4,
  "valued": 3,
  "acknowledged": 3,
  "heard": 3,
  "supported": 4,
  "valid": 3,
  "respected": 3,
  "reliable": 3,
  "comforted": 4,
  "peaceful": 3,
  "pleasant": 3,
  "hope": 3,
  "caring": 4,
  "love": 4,
  "protection": 3,
  "freedom": 4,
  "justice": 4,
  "fairness": 3,
};



Future<void> performSentimentAnalysis(String userDescription, String transcript) async {
  final sentiment = Sentiment();

  // Analyze user-submitted description
  final userDescriptionAnalysis = _customAnalysis(sentiment.analysis(userDescription), userDescription);
  print("\nUser Description Sentiment Analysis:");
  _displayAnalysis(userDescriptionAnalysis);

  // Analyze transcript from voice
  final transcriptAnalysis = _customAnalysis(sentiment.analysis(transcript), transcript);
  print("\nVoice Transcript Sentiment Analysis:");
  _displayAnalysis(transcriptAnalysis);

  // Generate report summary
  print("\nGenerated Sentiment Report:");
  print("Description Sentiment -> ${_interpretScore(userDescriptionAnalysis['score'])}");
  print("Transcript Sentiment -> ${_interpretScore(transcriptAnalysis['score'])}");

  sentimentReport = "Sentimental Analysis of user description: $userDescriptionAnalysis, Sentimental Analysis of the audio recorded by the user: $transcriptAnalysis, Description Sentiment -> ${_interpretScore(userDescriptionAnalysis['score'])}Transcript Sentiment -> ${_interpretScore(transcriptAnalysis['score'])}";
}

// Function to adjust sentiment analysis based on custom words
Map<String, dynamic> _customAnalysis(Map<String, dynamic> analysis, String text) {
  int customScore = 0;

  // Split the text into words and calculate custom score
  final words = text.split(RegExp(r'\s+'));
  for (var word in words) {
    if (customWords.containsKey(word.toLowerCase())) {
      customScore += customWords[word.toLowerCase()]!;
    }
  }

  // Adjust the score and return updated analysis
  analysis['customScore'] = customScore;
  analysis['score'] += customScore;
  return analysis;
}

// Helper function to display sentiment analysis results
void _displayAnalysis(Map<String, dynamic> analysis) {
  print("Score: ${analysis['score']}");
  print("Custom Score Adjustment: ${analysis['customScore']}");
  print("Comparative Score: ${analysis['comparative']}");
  print("Positive Words: ${analysis['positive']}");
  print("Negative Words: ${analysis['negative']}");
}

// Helper function to interpret scores
String _interpretScore(int score) {
  if (score > 3) return "Highly Positive";
  if (score > 0) return "Positive";
  if (score == 0) return "Neutral";
  if (score > -3) return "Negative";
  return "Highly Negative";
}

const String _apiKey = "AIzaSyBHb0C2d4pQDHImpKV4GwKdGTPEuUn3xF0";

Future<void> generateDetailedReport({
  required String description,
  required String voiceTranscript,
  required String extractedTextFromScreenshots,
  required String culpritDetails,
  required String sentimentAnalysisReport,
  required String reportId,
}) async {
  // Log all variables to ensure they are not null or empty
  // Combine all data into a structured prompt
  final prompt1 = '''
  Here the user submits a description of the incident in detail through text and voice description. The police needs to know the main details and evidences from the description. Provide the important details and evidences:

  Case Details:
  - User Submitted Description: "$description"
  - Voice Transcript: "$voiceTranscript"
  - Extracted Text from Screenshots: "$extractedTextFromScreenshots"
  The summary should focus on key findings, emotional impact, and actionable insights for the authorities to review. Ensure clarity and conciseness.
  ''';

  // Log the prompt to verify its content
  print("Generated Prompt Sent to Gemini API:");

  try {
    final response = await http.post(
      Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$_apiKey"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": prompt1}
            ]
          }
        ]
      }),
    );

    // Check the response
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final botReply = data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
      if (botReply != null) {
        print("Generated Detailed Report:");
        print(botReply);
         encryptedReport1 = encrypter.encrypt(botReply, iv: aesIV).base64;
      } else {
        print("Error: No report was generated.");
      }
    } else {
      print("Error: Failed to generate the report. Status code: ${response.statusCode}");
      print("Response: ${response.body}");
    }
  } catch (e) {
    print("Error during Gemini API call: $e");
  }

  final prompt2 = '''
  Here the user submits the screenshots related to incident in detail .:
  Case Details:
  - User Submitted Description: "$description"
  - Voice Transcript: "$voiceTranscript"
  - Extracted Text from Screenshots: "$extractedTextFromScreenshots"
  . The police needs to know the main details and evidences from the description. Provide the important details and evidences:
The summary should focus on key findings, emotional impact, and actionable insights for the authorities to review. Ensure clarity and conciseness.
  ''';

  // Log the prompt to verify its content
  print("Generated Prompt Sent to Gemini API:");

  try {
    final response = await http.post(
      Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$_apiKey"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": prompt2}
            ]
          }
        ]
      }),
    );

    // Check the response
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final botReply = data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
      if (botReply != null) {
        print("Generated Detailed Report:");
        print(botReply);
         encryptedReport2 = encrypter.encrypt(botReply, iv: aesIV).base64;
      } else {
        print("Error: No report was generated.");
      }
    } else {
      print("Error: Failed to generate the report. Status code: ${response.statusCode}");
      print("Response: ${response.body}");
    }
  } catch (e) {
    print("Error during Gemini API call: $e");
  }

  final prompt3 = '''  
   Here the user provides the culprit details and the  sentiment analysis report is provided. :
  - Culprit Details: "$culpritDetails"
      - Sentiment Analysis Report: "$sentimentAnalysisReport"
      The police need the culprit details and a comprehensive sentiment analysis report that makes the police decide the truthfulness:The summary should focus on key findings, emotional impact, and actionable insights for the authorities to review. Ensure clarity and conciseness.
''';
  print("Generated Prompt Sent to Gemini API:");
  print("The prompt created: \n $prompt3");

  try {
    final response = await http.post(
      Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$_apiKey"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": prompt3}
            ]
          }
        ]
      }),
    );

    // Check the response
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final botReply = data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];
      if (botReply != null) {
        print("Generated Detailed Report:");
        print(botReply);
       encryptedReport3 = encrypter.encrypt(botReply, iv: aesIV).base64;
      } else {
        print("Error: No report was generated.");
      }
    } else {
      print("Error: Failed to generate the report. Status code: ${response.statusCode}");
      print("Response: ${response.body}");
    }
  } catch (e) {
    print("Error during Gemini API call: $e");
  }

  fullygenreport = encryptedReport1 + " " + encryptedReport2 + " " + encryptedReport3;
  makepdf.Text2Pdf.generatePdf(fullygenreport);

  await FirebaseFirestore.instance.collection('ai_reports').doc(reportId).set({
    'generated_report_1': encryptedReport1,
    'generated_report_2': encryptedReport2,
    'generated_report_3': encryptedReport3,
    'timestamp': FieldValue.serverTimestamp(), // Optional: Store the timestamp for when the reports were generated
  });
}




