import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:random_avatar/random_avatar.dart';

class AiChatScreen extends StatefulWidget {
  @override
  _AiChatScreenState createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isTyping = false;

  final String _apiKey = "AIzaSyBHb0C2d4pQDHImpKV4GwKdGTPEuUn3xF0";

  // AES Key and IV
  final encrypt.Key _aesKey = encrypt.Key.fromUtf8(
      'nmR89ujXkMwpS78N76gxZ34vT9u34WR8');
  final encrypt.IV _aesIV = encrypt.IV.fromUtf8('Rk9iNwvM34k8F7St');
  late final encrypt.Encrypter _encrypter = encrypt.Encrypter(
      encrypt.AES(_aesKey, mode: encrypt.AESMode.cbc));

  @override
  void initState() {
    super.initState();
    _fetchChats();
  }

  // Encrypt a message
  String _encryptMessage(String message) {
    return _encrypter
        .encrypt(message, iv: _aesIV)
        .base64;
  }

  // Decrypt a message
  String _decryptMessage(String encryptedMessage) {
    try {
      return _encrypter.decrypt64(encryptedMessage, iv: _aesIV);
    } catch (e) {
      return "Error decrypting message";
    }
  }

  // Fetch previous chats
  Future<void> _fetchChats() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final chatDocs = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_chats')
        .orderBy('timestamp', descending: false)
        .get();

    setState(() {
      _messages.addAll(chatDocs.docs.map((doc) {
        final data = doc.data();
        final role = data['role'] ?? 'bot';
        final content = _decryptMessage(data['content'] ?? '');
        return {"role": role, "content": content};
      }));
    });
  }

  // Save a message to Firestore
  Future<void> _saveMessage(String role, String content) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final encryptedContent = _encryptMessage(content);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_chats')
        .add({
      'role': role,
      'content': encryptedContent,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // Send a message
  Future<void> _sendMessage(String text) async {
    setState(() {
      _messages.add({"role": "user", "content": text});
      _isTyping = true;
    });

    await _saveMessage("user", text); // Save the user's message in Firestore

    // Check if the input is relevant
    if (!_isRelevantInput(text)) {
      setState(() {
        _messages.add({
          "role": "bot",
          "content": "I'm here to provide emotional support and guidance. Let me know how I can help you."
        });
      });
      await _saveMessage(
        "bot",
        "I'm here to provide emotional support and guidance. Let me know how I can help you.",
      );
      setState(() {
        _isTyping = false;
      });
      return;
    }
    try {
      final response = await http.post(
        Uri.parse(
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent?key=$_apiKey"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": text}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final botReply = data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];

        if (botReply != null && botReply.isNotEmpty) {
          setState(() {
            _messages.add({"role": "bot", "content": botReply});
          });
          await _saveMessage("bot", botReply);
        } else {
          setState(() {
            _messages.add({
              "role": "bot",
              "content": "Hmm, I couldn’t quite catch that. Can you try again?"
            });
          });
          await _saveMessage(
            "bot",
            "Hmm, I couldn’t quite catch that. Can you try again?",
          );
        }
      } else {
        setState(() {
          _messages.add({
            "role": "bot",
            "content": "I'm having trouble processing that. Please try again."
          });
        });
        await _saveMessage(
          "bot",
          "I'm having trouble processing that. Please try again.",
        );
      }
    } catch (e) {
      print("Error: $e");
      setState(() {
        _messages.add({
          "role": "bot",
          "content":
          "Oops, something went wrong. Please check your connection and try again."
        });
      });
      await _saveMessage(
        "bot",
        "Oops, something went wrong. Please check your connection and try again.",
      );
    } finally {
      setState(() {
        _isTyping = false;
      });
    }
  }


  bool _isRelevantInput(String input) {
    final irrelevantKeywords = {
      'code',
      'c program',
      'python',
      'java',
      'javascript',
      'flutter',
      'dart',
      'algorithm',
      'stock',
      'money',
      'finance',
      'recipe',
      'weather',
      'news',
      'politics',
      'game',
      'match',
      'sports',
      'football',
      'cricket',
      'hacking',
      'malware',
      'virus',
      'exploit',
      'programming',
      'AI project',
      'science',
      'math',
      'physics',
      'chemistry',
      'biology',
      'geometry',
      'trigonometry',
      'machine learning',
      'neural network',
      'blockchain',
      'crypto',
      'bitcoin',
      'NFT',
      'investment',
      'real estate',
      'shopping',
      'discount',
      'sale',
      'coupon',
      'fashion',
      'celebrity',
      'gossip',
      'movies',
      'TV shows',
      'streaming',
      'Netflix',
      'Amazon Prime',
      'YouTube',
      'hardware',
      'GPU',
      'CPU',
      'RAM',
      'motherboard',
      'smartphones',
      'gadgets',
      'cars',
      'automobile',
      'racing',
      'formula 1',
      'motorcycle',
      'airplane',
      'travel',
      'tourism',
      'hotel',
      'resort',
      'vacation',
      'booking',
      'cruise',
      'luxury',
      'passport',
      'visa',
      'beach',
      'mountain',
      'adventure',
      'expedition',
      'trekking',
      'climbing',
      'astronomy',
      'astrology',
      'zodiac',
      'horoscope',
      'space',
      'NASA',
      'rockets',
      'aliens',
      'UFO',
      'mars',
      'satellite',
      'blackhole',
      'multiverse',
      'quantum physics',
      'wormhole',
      'cosmos',
      'evolution',
      'dinosaurs',
      'fossils',
      'archaeology',
      'mythology',
      'folklore',
      'comics',
      'superhero',
      'Marvel',
      'DC',
      'Avengers',
      'Superman',
      'Batman',
      'manga',
      'anime',
      'Naruto',
      'One Piece',
      'Dragon Ball',
      'Pokemon',
      'Digimon',
      'fantasy',
      'magic',
      'wizard',
      'Harry Potter',
      'Lord of the Rings',
      'Hobbit',
      'elves',
      'dragons',
      'vampires',
      'werewolves',
      'ghost',
      'paranormal',
      'conspiracy',
      'Illuminati',
      'bigfoot',
      'Loch Ness',
      'aliens',
      'myths',
      'legends',
      'fairy tales',
      'princess',
      'castle',
      'unicorn',
      'treasure',
      'pirates',
      'expedition',
      'underwater',
      'deep sea',
      'coral',
      'ocean',
      'submarine',
      'scuba diving',
      'fishing',
      'surfing',
      'volcano',
      'earthquake',
      'hurricane',
      'tornado',
      'climate',
      'global warming',
      'carbon footprint',
      'sustainability',
      'recycling',
      'renewable energy',
      'solar power',
      'wind energy',
      'electric cars',
      'Tesla',
      'SpaceX',
      'Elon Musk',
      'Jeff Bezos',
      'Amazon',
      'e-commerce',
      'online shopping',
      'PayPal',
      'Venmo',
      'credit card',
      'debit card',
      'banking',
      'loan',
      'mortgage',
      'insurance',
      'taxes',
      'audit',
      'accounting',
      'bookkeeping',
      'HR',
      'recruitment',
      'job interview',
      'resume',
      'LinkedIn',
      'career',
      'startup',
      'entrepreneur',
      'business',
      'company',
      'strategy',
      'advertising',
      'marketing',
      'branding',
      'PR',
      'public relations',
      'graphic design',
      'Photoshop',
      'video editing',
      'photography',
      'cinematography',
      'studio',
      'film',
      'Hollywood',
      'Bollywood',
      'Oscars',
      'Grammys',
      'concert',
      'band',
      'orchestra',
      'piano',
      'guitar',
      'violin',
      'singing',
      'karaoke',
      'music theory',
      'music production',
      'DJ',
      'club',
      'nightlife',
      'party',
      'wedding',
      'ceremony',
      'bride',
      'groom',
      'honeymoon',
      'anniversary',
      'birthday',
      'celebration',
      'festival',
      'Christmas',
      'New Year',
      'Halloween',
      'Easter',
      'Diwali',
      'Thanksgiving',
      'Hanukkah',
      'Ramadan',
      'Eid',
      'Buddha',
      'Zen',
      'meditation',
      'yoga',
      'wellness',
      'spa',
      'massage',
      'exercise',
      'workout',
      'gym',
      'weightlifting',
      'cardio',
      'running',
      'marathon',
      'cycling',
      'swimming',
      'hiking',
      'camping',
      'survival',
      'fire',
      'shelter',
      'first aid',
      'tools',
      'gear',
      'equipment',
      'diet',
      'nutrition',
      'vegan',
      'vegetarian',
      'keto',
      'paleo',
      'gluten-free',
      'recipes',
      'cooking',
      'baking',
      'chef',
      'restaurant',
      'cuisine',
      'coffee',
      'tea',
      'beverages',
      'beer',
      'wine',
      'whiskey',
      'cocktail',
      'bar',
      'pub',
      'liquor',
      'soft drinks',
      'energy drinks',
      'snacks',
      'desserts',
      'chocolates',
      'ice cream',
      'cake',
      'pastry',
      'bread',
      'sandwich',
      'pizza',
      'burger',
      'pasta',
      'sushi',
      'noodles',
      'curry',
      'spices',
      'herbs',
      'organic',
      'farm',
      'gardening',
      'plants',
      'flowers',
      'trees',
      'forest',
      'wildlife',
      'zoo',
      'pets',
      'dogs',
      'cats',
      'birds',
      'fish',
      'reptiles',
      'exotic animals'
    };


    // Check if any irrelevant keyword is present in the input
    for (var keyword in irrelevantKeywords) {
      if (input.toLowerCase().contains(keyword)) {
        return false;
      }
    }
    return true;
  }


  Widget _buildMessage(Map<String, String> message) {
    final isUserMessage = message["role"] == "user";
    final user = FirebaseAuth.instance.currentUser;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: isUserMessage
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        // Bot avatar for bot messages
        if (!isUserMessage)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.pink.shade200,
              child: const Icon(
                Icons.chat_bubble,
                color: Colors.white,
              ),
            ),
          ),

        // Message bubble
        Flexible(
          child: Column(
            crossAxisAlignment: isUserMessage
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(
                  vertical: 4,
                  horizontal: 8, // Add horizontal margin to avoid touching the edge
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isUserMessage
                      ? Colors.blue.shade100
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft:
                    isUserMessage ? Radius.circular(12) : Radius.zero,
                    bottomRight:
                    isUserMessage ? Radius.zero : Radius.circular(12),
                  ),
                ),
                child: Text(
                  message["content"] ?? "",
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ),

              // Timestamp
              Padding(
                padding: const EdgeInsets.only(
                  left: 8,
                  right: 8,
                  bottom: 4,
                ),
                child: Text(
                  "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} - ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),

        // User avatar for user messages
        if (isUserMessage)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: CircleAvatar(
              radius: 20,
              child: RandomAvatar(
                user?.email ?? "User",
                height: 40,
                width: 40,
              ),
            ),
          ),
      ],
    );
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Chat with Tara",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.pink.shade700,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: Container(
              color: Colors.pink.shade50,
              child: ListView.builder(
                reverse: true,
                itemCount: _messages.length,
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemBuilder: (context, index) {
                  final message = _messages[_messages.length - 1 - index];
                  return _buildMessage(message);
                },
              ),

            ),
          ),

          // Typing Indicator
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.pink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "Tara is typing...",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          // Input Field and Send Button
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                      final text = _controller.text.trim();
                      if (text.isNotEmpty) {
                        _controller.clear();
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
