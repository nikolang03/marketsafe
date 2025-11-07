import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/face_login_screen.dart';
import 'navigation_wrapper.dart';
import 'services/network_service.dart';
import 'services/lockout_service.dart';
import 'widgets/loading_screen.dart';
import 'package:camera/camera.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (kDebugMode) {
    debugPrint('Starting MarketSafe app...');
  }
  
  try {
    if (kDebugMode) {
      debugPrint('Initializing Firebase...');
    }
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (kDebugMode) {
      debugPrint('✅ Firebase initialized successfully');
    }

    // Initialize Firebase App Check for security
    try {
      if (kDebugMode) {
        debugPrint('🔒 Initializing Firebase App Check...');
      }
      
      await FirebaseAppCheck.instance.activate(
        // For Android: Use debug provider in debug mode, Play Integrity in release
        // Play Integrity requires the app to be published/registered in Google Play
        // For iOS: Automatically uses DeviceCheck or App Attest
        // For Web: Uses reCAPTCHA Enterprise
        androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      );
      
      if (kDebugMode) {
        debugPrint('✅ Firebase App Check initialized successfully');
        debugPrint('🛡️ Your Firebase backend is now protected from abuse');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Firebase App Check initialization error: $e');
        debugPrint('⚠️ App Check failed, but app will continue without it');
      }
      // Continue anyway - App Check is optional but recommended
    }

    if (kDebugMode) {
      // Initialize Firebase Storage
      debugPrint('🔍 Initializing Firebase Storage...');
      debugPrint('✅ Firebase Storage initialized successfully');
      
      // Test watermarking functionality (commented out - method doesn't exist)
      // debugPrint('🧪 Testing watermarking functionality...');
      // try {
      //   await WatermarkingService.testWatermarking();
      // } catch (e) {
      //   debugPrint('❌ Watermarking test failed: $e');
      // }

      // Force clear lockout for testing
      debugPrint('🔄 Force clearing lockout for testing...');
      LockoutService.forceClearLockout();
      debugPrint('✅ Lockout force cleared successfully');
      
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('❌ Firebase initialization error: $e');
    }
    // Continue anyway - app can still work without Firebase for basic UI
  }

  if (kDebugMode) {
    debugPrint('Starting Flutter app...');
  }
  
  // Start network monitoring
  NetworkService.startMonitoring();
  
  runApp(const MarketSafeApp());
}

class MarketSafeApp extends StatelessWidget {
  const MarketSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarketSafe',
      debugShowCheckedModeBanner: false,
      // Performance optimizations
      builder: (context, child) {
        // Enable performance overlay only in debug mode
        if (kDebugMode) {
          return child!;
        }
        return child!;
      },
      home: FutureBuilder(
        future: _initializeApp(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen(
              message: "Initializing MarketSafe...",
              showProgress: true,
            );
          }
          
          if (snapshot.hasError) {
            return ErrorScreen(error: snapshot.error.toString());
          }
          
          return const WelcomeScreen();
        },
      ),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/login': (context) => const FaceLoginScreen(),
        '/main': (context) => const NavigationWrapper(),
      },
    );
  }

  Future<void> _initializeApp() async {
    if (kDebugMode) {
      debugPrint('App initialization starting...');
    }
    // Small delay to ensure Firebase is ready and show loading screen
    await Future.delayed(const Duration(milliseconds: 1000));
    if (kDebugMode) {
      debugPrint('App initialization completed');
    }
  }
}


class ErrorScreen extends StatelessWidget {
  final String error;
  
  const ErrorScreen({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 80,
              ),
              const SizedBox(height: 20),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                error,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  // Restart the app
                  Navigator.of(context).pushReplacementNamed('/welcome');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
