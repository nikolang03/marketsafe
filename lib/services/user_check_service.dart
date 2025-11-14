import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class UserCheckService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: 'marketsafe',
  );

  /// Check if email is already registered (only after successful signup completion)
  static Future<bool> isEmailAlreadyRegistered(String email) async {
    try {
      // Check in Firestore users collection for users who have completed signup
      // Only consider users as "registered" if they have completed the signup process
      final querySnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .where('signupCompleted', isEqualTo: true) // Only check users who completed signup
          .limit(1)
          .get();
      
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking email: $e');
      return false; // Return false on error to allow signup to continue
    }
  }

  /// Check if phone number is already registered (only after successful signup completion)
  static Future<bool> isPhoneAlreadyRegistered(String phoneNumber) async {
    try {
      // Check in Firestore users collection for users who have completed signup
      // Only consider users as "registered" if they have completed the signup process
      final querySnapshot = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .where('signupCompleted', isEqualTo: true) // Only check users who completed signup
          .limit(1)
          .get();
      
      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking phone: $e');
      return false; // Return false on error to allow signup to continue
    }
  }

  /// Check if user exists (email or phone) - only after successful signup completion
  static Future<Map<String, dynamic>> checkUserExists(String input) async {
    final result = <String, dynamic>{
      'exists': false,
      'type': null, // 'email' or 'phone'
      'message': null,
    };

    try {
      // Detect if input is email or phone
      bool isEmail = input.contains('@');
      bool isPhone = RegExp(r'^09\d{9}$').hasMatch(input);

      if (isEmail) {
        print('🔍 Checking email: $input (only after successful signup completion)');
        final emailExists = await isEmailAlreadyRegistered(input);
        if (emailExists) {
          result['exists'] = true;
          result['type'] = 'email';
          result['message'] = 'This email is already registered. Please use a different email or try logging in.';
          print('❌ Email already registered: $input');
        } else {
          print('✅ Email available for signup: $input');
        }
      } else if (isPhone) {
        // Convert to international format for checking
        String phoneNumber = input.startsWith('09') ? '+63${input.substring(1)}' : input;
        print('🔍 Checking phone: $phoneNumber (only after successful signup completion)');
        final phoneExists = await isPhoneAlreadyRegistered(phoneNumber);
        if (phoneExists) {
          result['exists'] = true;
          result['type'] = 'phone';
          result['message'] = 'This phone number is already registered. Please use a different phone number or try logging in.';
          print('❌ Phone already registered: $phoneNumber');
        } else {
          print('✅ Phone available for signup: $phoneNumber');
        }
      }
    } catch (e) {
      print('Error checking user existence: $e');
    }

    return result;
  }

  /// Check if username is already taken
  /// [excludeUserId] - Optional user ID to exclude from check (useful when editing profile)
  static Future<bool> isUsernameTaken(String username, {String? excludeUserId}) async {
    try {
      if (username.trim().isEmpty) {
        return false; // Empty username is not considered "taken"
      }

      final usernameLower = username.trim().toLowerCase();
      
      // Check in Firestore users collection for users who have completed signup
      final querySnapshot = await _firestore
          .collection('users')
          .where('username', isEqualTo: usernameLower)
          .where('signupCompleted', isEqualTo: true)
          .limit(1)
          .get();
      
      // If no results, username is available
      if (querySnapshot.docs.isEmpty) {
        return false;
      }
      
      // If excludeUserId is provided, check if the found user is the same user
      if (excludeUserId != null) {
        final foundUserId = querySnapshot.docs.first.id;
        if (foundUserId == excludeUserId) {
          // Same user, so username is not taken (they're keeping their own username)
          return false;
        }
      }
      
      // Username is taken by another user
      return true;
    } catch (e) {
      print('❌ Error checking username: $e');
      // On error, return false to allow signup/edit to continue (fail open)
      // This prevents blocking users due to network issues
      return false;
    }
  }

  /// Check if user was previously rejected (for informational purposes)
  static Future<bool> wasUserPreviouslyRejected(String input) async {
    try {
      bool isEmail = input.contains('@');
      bool isPhone = RegExp(r'^09\d{9}$').hasMatch(input);

      if (isEmail) {
        final querySnapshot = await _firestore
            .collection('users')
            .where('email', isEqualTo: input)
            .where('verificationStatus', isEqualTo: 'rejected')
            .limit(1)
            .get();
        
        if (querySnapshot.docs.isNotEmpty) {
          print('ℹ️ User was previously rejected: $input');
          return true;
        }
      } else if (isPhone) {
        String phoneNumber = input.startsWith('09') ? '+63${input.substring(1)}' : input;
        final querySnapshot = await _firestore
            .collection('users')
            .where('phoneNumber', isEqualTo: phoneNumber)
            .where('verificationStatus', isEqualTo: 'rejected')
            .limit(1)
            .get();
        
        if (querySnapshot.docs.isNotEmpty) {
          print('ℹ️ User was previously rejected: $phoneNumber');
          return true;
        }
      }
    } catch (e) {
      print('Error checking if user was rejected: $e');
    }
    
    return false;
  }
}
