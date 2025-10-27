import 'dart:math';
import 'dart:convert';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class EmailService {
  // Gmail SMTP configuration
  static const String _gmailUser = 'kincunanan33@gmail.com'; // Your Gmail
  static const String _gmailPassword =
      'urif udrb lkuq xkgi'; // Your App Password

  // OTP storage key for SharedPreferences
  static const String _otpStorageKey = 'otp_storage';
  
  // Firebase Firestore instance for "marketsafe" database
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  static Future<void> sendOtp(String email) async {
    print('🔍 Email Service: Sending OTP to $email');

    email = email.trim();
    final emailRegex = RegExp(r'\S+@\S+\.\S+');
    if (!emailRegex.hasMatch(email)) {
      throw Exception("Invalid email format.");
    }

    // Generate 6-digit OTP
    final random = Random();
    final otp = (100000 + random.nextInt(900000)).toString();
    print('🔍 Generated OTP: $otp for email: $email');

    // Store OTP with expiration (5 minutes) in SharedPreferences
    await _storeOtp(email, otp);
    print('🔍 OTP stored successfully');

    try {
      // Gmail SMTP server
      final smtpServer = gmail(_gmailUser, _gmailPassword);

      // Create email message
      final message = Message()
        ..from = Address(_gmailUser, 'MarketSafe')
        ..recipients.add(email)
        ..subject = 'MarketSafe Verification Code'
        ..html = '''
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #d32f2f;">MarketSafe Verification Code</h2>
            <p>Your verification code is:</p>
            <div style="background-color: #f5f5f5; padding: 20px; text-align: center; margin: 20px 0;">
              <h1 style="color: #d32f2f; font-size: 32px; margin: 0; letter-spacing: 5px;">$otp</h1>
            </div>
            <p>This code will expire in 5 minutes.</p>
            <p>If you didn't request this code, please ignore this email.</p>
          </div>
        ''';

      // Send email
      final sendReport = await send(message, smtpServer);
      print('✅ OTP sent successfully to $email');
      print('Send report: $sendReport');
      
      // Log OTP for debugging
      print('=== OTP GENERATED ===');
      print('Email: $email');
      print('OTP Code: $otp');
      print('====================================');
    } catch (e) {
      print('❌ Email sending error: $e');
      // Fallback: show OTP in console for development
      print('=== OTP FOR DEVELOPMENT ===');
      print('Email: $email');
      print('OTP Code: $otp');
      print('==========================');
      // Don't throw error, just show in console
    }
  }

  static Future<bool> verifyOtp(String email, String code) async {
    print('🔍 Email Service: Verifying OTP for $email');
    print('🔍 Email Service: Code received: $code');

    email = email.trim();
    code = code.trim();

    // Use SharedPreferences as primary storage (more reliable)
    var storedData = await _getOtp(email);
    
    if (storedData == null) {
      print('❌ No OTP found for this email: $email');
      final allOtps = await _getAllOtps();
      print('🔍 Available emails in storage: ${allOtps.keys.toList()}');
      print('🔍 All stored OTPs: $allOtps');
      
      // IMPROVED: Try case-insensitive email matching
      for (final storedEmail in allOtps.keys) {
        if (storedEmail.toLowerCase() == email.toLowerCase()) {
          print('🔍 Found case-insensitive match: $storedEmail');
          storedData = allOtps[storedEmail];
          break;
        }
      }
      
      if (storedData == null) {
        return false;
      }
    }

    print('🔍 Found stored OTP data: $storedData');
    final now = DateTime.now().millisecondsSinceEpoch;
    print('🔍 Current time: $now, Expires: ${storedData['expires']}');
    
    if (now > storedData['expires']) {
      await _removeOtp(email);
      print('❌ OTP has expired for $email');
      return false;
    }

    print('🔍 Comparing OTPs - Expected: ${storedData['otp']}, Got: $code');
    // IMPROVED: Trim whitespace and compare
    if (storedData['otp'].toString().trim() != code.trim()) {
      print('❌ Invalid OTP code for $email. Expected: ${storedData['otp']}, Got: $code');
      return false;
    }

    // OTP is valid, remove it from storage
    await _removeOtp(email);
    print('✅ OTP verified successfully for $email');
    return true;
  }

  // Helper methods for SharedPreferences OTP storage
  static Future<void> _storeOtp(String email, String otp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final otpData = {
        'otp': otp,
        'expires': DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      };
      
      // Get existing OTPs
      final existingOtps = await _getAllOtps();
      existingOtps[email] = otpData;
      
      // Store back to SharedPreferences
      await prefs.setString(_otpStorageKey, jsonEncode(existingOtps));
      print('💾 OTP stored for $email: $otp');
    } catch (e) {
      print('❌ Error storing OTP: $e');
    }
  }

  static Future<Map<String, dynamic>?> _getOtp(String email) async {
    try {
      final allOtps = await _getAllOtps();
      return allOtps[email];
    } catch (e) {
      print('❌ Error getting OTP: $e');
      return null;
    }
  }

  static Future<Map<String, Map<String, dynamic>>> _getAllOtps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final otpString = prefs.getString(_otpStorageKey);
      
      if (otpString == null) {
        return {};
      }
      
      final Map<String, dynamic> decoded = jsonDecode(otpString);
      return decoded.map((key, value) => MapEntry(key, Map<String, dynamic>.from(value)));
    } catch (e) {
      print('❌ Error getting all OTPs: $e');
      return {};
    }
  }

  static Future<void> _removeOtp(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allOtps = await _getAllOtps();
      allOtps.remove(email);
      
      if (allOtps.isEmpty) {
        await prefs.remove(_otpStorageKey);
      } else {
        await prefs.setString(_otpStorageKey, jsonEncode(allOtps));
      }
      
      print('🗑️ OTP removed for $email');
    } catch (e) {
      print('❌ Error removing OTP: $e');
    }
  }


  // Debug method to show all OTPs in Firebase
  static Future<void> debugShowAllFirebaseOtps() async {
    try {
      final snapshot = await _firestore.collection('otps').get();
      print('🔥 Firebase OTPs:');
      for (var doc in snapshot.docs) {
        final data = doc.data();
        print('  - ${doc.id}: ${data['otp']} (expires: ${data['expires']})');
      }
    } catch (e) {
      print('❌ Error getting Firebase OTPs: $e');
    }
  }
}
