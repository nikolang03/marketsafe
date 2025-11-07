import 'package:flutter/material.dart';
import 'face_blinktwice_screen.dart';

class FaceReadyScreen extends StatelessWidget {
  const FaceReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/logo.png',
                height: 60,
              ),
              
              const SizedBox(height: 30),

              // Title
              Text(
                "GET READY TO VERIFY YOURSELF",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  letterSpacing: 1.5,
                ),
              ),
              
              const SizedBox(height: 30),

              // Face image with red elliptical frame
              Container(
                width: 200,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.red, 
                    width: 3,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.elliptical(100, 125),
                    topRight: Radius.elliptical(100, 125),
                    bottomLeft: Radius.elliptical(100, 125),
                    bottomRight: Radius.elliptical(100, 125),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.elliptical(100, 125),
                    topRight: Radius.elliptical(100, 125),
                    bottomLeft: Radius.elliptical(100, 125),
                    bottomRight: Radius.elliptical(100, 125),
                  ),
                  child: Image.asset(
                    'assets/facereadyicon.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),

              // Instructions
              Text(
                "FRAME YOUR FACE IN THE OVAL,\nPRESS I'M READY AND MOVE CLOSER",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  letterSpacing: 1.0,
                  height: 1.5,
                ),
              ),
              
              const SizedBox(height: 40),

              // Ready button
              ElevatedButton(
                onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const FaceBlinkTwiceScreen()),
                      );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 8,
                ),
                child: const Text(
                  "IM READY",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

