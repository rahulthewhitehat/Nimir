import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';

class DisclaimerScreen extends StatefulWidget {
  @override
  _DisclaimerScreenState createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  int _currentSlide = 0;

  final List<Map<String, dynamic>> slides = [
    {
      "title": "Full Access for Registered Users",
      "content":
      "Users who log in via email, Google, or phone get full access to the app: Submit reports, check report status, post feeds, like/comment, and chat with others. Advanced verification is required, including government ID submission and AI verification.",
      "icon": Icons.verified_user,
    },
    {
      "title": "Anonymous Login",
      "content":
      "With anonymous login, you can submit reports and track status within the session. This option is great for quick usage but limits features.",
      "icon": Icons.person_outline,
    },
    {
      "title": "Direct Reporting",
      "content":
      "Direct reporting allows skipping login. Submit reports for a friend, someone you know, or provide evidence for pending unsolved cases. Ideal for third-party submissions.",
      "icon": Icons.send,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8E0E6), // Pink Light Background
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CarouselSlider.builder(
                itemCount: slides.length,
                options: CarouselOptions(
                  height: double.infinity,
                  viewportFraction: 1.0,
                  enableInfiniteScroll: false,
                  autoPlay: false,
                  onPageChanged: (index, _) {
                    setState(() {
                      _currentSlide = index;
                    });
                  },
                ),
                itemBuilder: (context, index, _) {
                  final slide = slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          slide['icon'],
                          size: 80,
                          color: Color(0xFFD81B60), // Pink Dark
                        ),
                        SizedBox(height: 20),
                        Text(
                          slide['title'],
                          style: TextStyle(
                            color: Color(0xFFD81B60), // Pink Dark
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 20),
                        Text(
                          slide['content'],
                          style: TextStyle(
                            color: Color(0xFF616161), // Gray Dark
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: slides.map((slide) {
                int index = slides.indexOf(slide);
                return Container(
                  width: 8.0,
                  height: 8.0,
                  margin: EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentSlide == index
                        ? Color(0xFFD81B60) // Pink Dark for Active
                        : Color(0xFFF8BBD0), // Pink Light for Inactive
                  ),
                );
              }).toList(),
            ),
            if (_currentSlide == slides.length - 1)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/login'); // Navigate to Login
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFFF06292), // Pink Medium
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 15, horizontal: 30),
                  ),
                  child: Text(
                    "Continue",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
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
