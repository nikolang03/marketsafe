# Security & Code Quality Fix Plan

## Overview
This document provides a detailed, step-by-step plan to fix all identified security and code quality issues in the MarketSafe app.

---

## 🔴 CRITICAL FIXES (Must Fix Before Production)

### 1. Firestore Security Rules - Open Access

**Problem**: All Firestore collections allow unrestricted read/write access to anyone.

**Risk Level**: 🔴 **CRITICAL** - Anyone can read/write all user data, products, notifications, etc.

**Files to Modify**:
- `firestore.rules`

**Solution**: Implement proper authentication-based security rules.

#### Step 1: Understand Current User ID Format
Your app uses custom user IDs: `user_{timestamp}_{sanitizedUsername}` (e.g., `user_1762614407613_karlzamueldavidferrer27`)

However, Firebase Auth uses UIDs like `WN6LWiKj1YYVy6AmCabYgCO5G8L2`.

**Important**: You need to store Firebase Auth UID in the user document for security rules to work.

#### Step 2: Update User Document Structure
Add `firebaseAuthUid` field to user documents when creating accounts.

**File**: `lib/screens/fill_information_screen.dart`

**Location**: Around line 377-398 (where `userData` is created)

**Change**:
```dart
// BEFORE (line ~377)
final userData = {
  'uid': userId,
  'phoneNumber': userPhone,
  'email': userEmail,
  // ... other fields
};

// AFTER
final firebaseUser = FirebaseAuth.instance.currentUser;
final userData = {
  'uid': userId,
  'firebaseAuthUid': firebaseUser?.uid ?? '', // ADD THIS LINE
  'phoneNumber': userPhone,
  'email': userEmail,
  // ... other fields
};
```

#### Step 3: Create Secure Firestore Rules

**File**: `firestore.rules`

**Replace entire file with**:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function to get current user's Firebase Auth UID
    function getCurrentUserId() {
      return request.auth.uid;
    }
    
    // Helper function to check if user owns the document
    function isOwner(userId) {
      return isAuthenticated() && 
             (getCurrentUserId() == userId || 
              resource.data.firebaseAuthUid == getCurrentUserId());
    }
    
    // Helper function to check if user can read their own data
    function canReadOwnData(userId) {
      return isAuthenticated() && 
             (getCurrentUserId() == userId || 
              resource.data.firebaseAuthUid == getCurrentUserId());
    }
    
    // ==========================================
    // OTPs Collection - Public for signup
    // ==========================================
    match /otps/{email} {
      // Allow anyone to read/write OTPs (needed for signup)
      // But limit to prevent abuse
      allow read: if true;
      allow write: if true;
      // Note: OTPs should expire automatically (handled in code)
    }
    
    // ==========================================
    // Users Collection - Protected
    // ==========================================
    match /users/{userId} {
      // Read: Users can read their own data, or public profile info
      allow read: if isAuthenticated() && (
        // Own data
        canReadOwnData(userId) ||
        // Public profile info (for viewing other users' profiles)
        // Only allow reading username, profilePictureUrl, verificationStatus
        request.auth != null
      );
      
      // Create: Only authenticated users can create their own document
      allow create: if isAuthenticated() && (
        // Must match Firebase Auth UID
        request.resource.data.firebaseAuthUid == getCurrentUserId() ||
        // Or if no firebaseAuthUid yet (during signup), allow but will be updated
        !('firebaseAuthUid' in request.resource.data)
      );
      
      // Update: Users can only update their own data
      allow update: if isAuthenticated() && (
        // Must own the document
        isOwner(userId) ||
        // Or updating firebaseAuthUid field during signup
        (request.resource.data.firebaseAuthUid == getCurrentUserId() && 
         !('firebaseAuthUid' in resource.data))
      );
      
      // Delete: Users can only delete their own account
      allow delete: if isAuthenticated() && isOwner(userId);
    }
    
    // ==========================================
    // Face Metrics Collection - Protected
    // ==========================================
    match /faceMetrics/{faceDataId} {
      // Only users can read/write their own face metrics
      allow read, write: if isAuthenticated() && 
        resource.data.userId == getCurrentUserId();
      
      // Allow creating new face metrics
      allow create: if isAuthenticated() && 
        request.resource.data.userId == getCurrentUserId();
    }
    
    // ==========================================
    // Face Registry Collection - Protected
    // ==========================================
    match /face_registry/{faceRegistryId} {
      // Only users can read/write their own face registry entries
      allow read, write: if isAuthenticated() && 
        resource.data.userId == getCurrentUserId();
      
      // Allow creating new entries
      allow create: if isAuthenticated() && 
        request.resource.data.userId == getCurrentUserId();
    }
    
    // ==========================================
    // Face Embeddings Collection - Protected
    // ==========================================
    match /face_embeddings/{userId} {
      // Only users can read/write their own face embeddings
      allow read, write: if isAuthenticated() && 
        (userId == getCurrentUserId() || 
         resource.data.firebaseAuthUid == getCurrentUserId());
      
      // Allow creating new embeddings
      allow create: if isAuthenticated() && 
        (userId == getCurrentUserId() || 
         request.resource.data.firebaseAuthUid == getCurrentUserId());
    }
    
    // ==========================================
    // Verification Queue - Admin Only
    // ==========================================
    match /verificationQueue/{queueId} {
      // Only authenticated users can read (for admins)
      // In production, add admin role check
      allow read: if isAuthenticated();
      
      // Only admins can write (add admin check in production)
      allow write: if isAuthenticated();
      // TODO: Add admin role verification
      // Example: resource.data.adminId == getCurrentUserId()
    }
    
    // ==========================================
    // Products Collection - Protected
    // ==========================================
    match /products/{productId} {
      // Anyone authenticated can read products (for browsing)
      allow read: if isAuthenticated();
      
      // Only product owner can create/update/delete
      allow create: if isAuthenticated() && 
        request.resource.data.userId == getCurrentUserId();
      
      allow update: if isAuthenticated() && 
        resource.data.userId == getCurrentUserId();
      
      allow delete: if isAuthenticated() && 
        resource.data.userId == getCurrentUserId();
    }
    
    // ==========================================
    // Categories Collection - Public Read
    // ==========================================
    match /categories/{categoryId} {
      // Anyone can read categories
      allow read: if isAuthenticated();
      
      // Only admins can write (add admin check in production)
      allow write: if isAuthenticated();
      // TODO: Add admin role verification
    }
    
    // ==========================================
    // Notifications Collection - Protected
    // ==========================================
    match /notifications/{notificationId} {
      // Users can only read their own notifications
      allow read: if isAuthenticated() && 
        resource.data.userId == getCurrentUserId();
      
      // Users can create notifications (for system notifications)
      allow create: if isAuthenticated();
      
      // Users can update their own notifications (mark as read)
      allow update: if isAuthenticated() && 
        resource.data.userId == getCurrentUserId();
      
      // Users can delete their own notifications
      allow delete: if isAuthenticated() && 
        resource.data.userId == getCurrentUserId();
    }
    
    // ==========================================
    // Conversations Collection - Protected
    // ==========================================
    match /conversations/{conversationId} {
      // Users can read conversations they're part of
      allow read: if isAuthenticated() && 
        getCurrentUserId() in resource.data.participants;
      
      // Users can create conversations they're part of
      allow create: if isAuthenticated() && 
        getCurrentUserId() in request.resource.data.participants;
      
      // Users can update conversations they're part of
      allow update: if isAuthenticated() && 
        getCurrentUserId() in resource.data.participants;
    }
    
    // ==========================================
    // Messages Collection - Protected
    // ==========================================
    match /conversations/{conversationId}/messages/{messageId} {
      // Users can read messages in conversations they're part of
      allow read: if isAuthenticated();
      
      // Users can create messages in conversations they're part of
      allow create: if isAuthenticated() && 
        getCurrentUserId() == request.resource.data.senderId;
      
      // Users can update their own messages
      allow update: if isAuthenticated() && 
        resource.data.senderId == getCurrentUserId();
    }
    
    // ==========================================
    // Default Deny
    // ==========================================
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

#### Step 4: Deploy Firestore Rules

**Command**:
```bash
firebase deploy --only firestore:rules
```

**Or via Firebase Console**:
1. Go to Firebase Console → Firestore Database → Rules
2. Paste the new rules
3. Click "Publish"

#### Step 5: Test Security Rules

**Test Cases**:
1. ✅ Authenticated user can read their own user document
2. ✅ Authenticated user can update their own user document
3. ❌ Authenticated user CANNOT read other users' documents
4. ❌ Unauthenticated user CANNOT read any protected collections
5. ✅ User can create their own products
6. ❌ User CANNOT update other users' products

---

### 2. Hardcoded Gmail Password

**Problem**: Gmail app password is hardcoded in source code.

**Risk Level**: 🔴 **CRITICAL** - If code is public, password is exposed.

**Files to Modify**:
- `lib/services/email_service.dart`

**Solution Options**:

#### Option A: Use Environment Variables (Recommended for Production)

**Step 1**: Create `.env` file (add to `.gitignore`)

**File**: `.env` (create new file in project root)

```
GMAIL_USER=kincunanan33@gmail.com
GMAIL_PASSWORD=urif udrb lkuq xkgi
```

**Step 2**: Add `flutter_dotenv` package

**File**: `pubspec.yaml`

Add to dependencies:
```yaml
dependencies:
  flutter_dotenv: ^5.1.0
```

**Step 3**: Load environment variables in `main.dart`

**File**: `lib/main.dart`

Add at top of `main()` function:
```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  // ... rest of main()
}
```

**Step 4**: Update `email_service.dart`

**File**: `lib/services/email_service.dart`

**Change**:
```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EmailService {
  // Get from environment variables
  static String get _gmailUser => dotenv.env['GMAIL_USER'] ?? 'kincunanan33@gmail.com';
  static String get _gmailPassword => dotenv.env['GMAIL_PASSWORD'] ?? '';

  // ... rest of code
}
```

**Step 5**: Update `.gitignore`

**File**: `.gitignore`

Add:
```
.env
.env.local
```

#### Option B: Use Firebase Remote Config (Alternative)

**Step 1**: Store credentials in Firebase Remote Config

1. Go to Firebase Console → Remote Config
2. Add parameters:
   - `gmail_user`: `kincunanan33@gmail.com`
   - `gmail_password`: `urif udrb lkuq xkgi`

**Step 2**: Update `email_service.dart`

```dart
import 'package:firebase_remote_config/firebase_remote_config.dart';

class EmailService {
  static String? _gmailUser;
  static String? _gmailPassword;
  
  static Future<void> _loadConfig() async {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.fetchAndActivate();
    _gmailUser = remoteConfig.getString('gmail_user');
    _gmailPassword = remoteConfig.getString('gmail_password');
  }
  
  static Future<void> sendOtp(String email) async {
    await _loadConfig();
    // ... rest of code
  }
}
```

#### Option C: Use Firebase Functions (Most Secure)

**Best Practice**: Move email sending to Firebase Functions (backend), so credentials never touch the client.

**File**: `backend/app.js` (add new endpoint)

```javascript
const nodemailer = require('nodemailer');

// Store credentials in environment variables on Railway
const GMAIL_USER = process.env.GMAIL_USER || 'kincunanan33@gmail.com';
const GMAIL_PASSWORD = process.env.GMAIL_PASSWORD || 'urif udrb lkuq xkgi';

app.post('/api/send-otp', async (req, res) => {
  try {
    const { email } = req.body;
    
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }
    
    // Generate OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    
    // Send email using nodemailer
    const transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: {
        user: GMAIL_USER,
        pass: GMAIL_PASSWORD
      }
    });
    
    await transporter.sendMail({
      from: GMAIL_USER,
      to: email,
      subject: 'MarketSafe Verification Code',
      html: `<h1>Your OTP is: ${otp}</h1>`
    });
    
    // Store OTP in Firestore (with expiration)
    // ... store logic
    
    res.json({ success: true, message: 'OTP sent' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
```

**Then update Flutter app** to call this endpoint instead of sending directly.

**Recommendation**: Use **Option C (Firebase Functions)** for production, or **Option A (Environment Variables)** for quick fix.

---

## 🟡 MEDIUM PRIORITY FIXES

### 3. Test Enrollment Cleanup

**Problem**: Test enrollment UUID may not be cleaned up if main enrollment fails.

**Risk Level**: 🟡 **MEDIUM** - Orphaned test enrollments in Luxand.

**Files to Modify**:
- `lib/screens/fill_information_screen.dart`
- `lib/services/face_auth_backend_service.dart` (if delete endpoint exists)

**Solution**: Ensure test enrollment is deleted even if main enrollment fails.

#### Step 1: Add Cleanup Function

**File**: `lib/screens/fill_information_screen.dart`

**Location**: Add new method around line 830 (before `_showErrorDialog`)

```dart
/// Clean up test enrollment from Luxand
Future<void> _cleanupTestEnrollment(String testUuid, String email) async {
  if (testUuid.isEmpty) return;
  
  try {
    print('🧹 [CLEANUP] Deleting test enrollment UUID: $testUuid');
    
    // Call backend to delete the test enrollment
    final backendService = FaceAuthBackendService();
    final deleteResult = await NetworkService.executeWithRetry(
      () => backendService.deletePerson(email: email, uuid: testUuid),
      maxRetries: 2,
      retryDelay: const Duration(seconds: 1),
      loadingMessage: null, // Don't show loading for cleanup
      context: context,
      showNetworkErrors: false, // Don't show errors for cleanup
    );
    
    if (deleteResult['success'] == true || deleteResult['ok'] == true) {
      print('✅ [CLEANUP] Test enrollment deleted successfully: $testUuid');
    } else {
      print('⚠️ [CLEANUP] Failed to delete test enrollment: ${deleteResult['error']}');
    }
  } catch (e) {
    print('⚠️ [CLEANUP] Error cleaning up test enrollment: $e');
    // Don't throw - cleanup failure shouldn't block signup
  }
}
```

#### Step 2: Update Pre-Check Logic

**File**: `lib/screens/fill_information_screen.dart`

**Location**: Around line 290-296

**Change**:
```dart
// BEFORE (lines 290-296)
final testUuid = testEnrollResult['luxandUuid']?.toString();
if (testUuid != null && testUuid.isNotEmpty) {
  print('🔍 [PRE-CHECK] Test enrollment succeeded. Will delete test UUID: $testUuid');
  // Note: We'll clean this up when we enroll all 3 faces (which deletes duplicates for same email)
}

// AFTER
final testUuid = testEnrollResult['luxandUuid']?.toString() ?? '';
if (testUuid.isNotEmpty) {
  print('🔍 [PRE-CHECK] Test enrollment succeeded. UUID: $testUuid');
  // Store test UUID for cleanup later
  _pendingTestUuidCleanup = testUuid;
  _pendingTestEmail = userEmail.isNotEmpty ? userEmail : userPhone;
}
```

#### Step 3: Add State Variables

**File**: `lib/screens/fill_information_screen.dart`

**Location**: Add to class state variables (around line 30-50)

```dart
String _pendingTestUuidCleanup = '';
String _pendingTestEmail = '';
```

#### Step 4: Cleanup After Enrollment

**File**: `lib/screens/fill_information_screen.dart`

**Location**: After enrollment completes (around line 456-514)

**Change**:
```dart
// AFTER enrollment result (around line 456)
if (enrollResult['success'] == true) {
  final luxandUuid = enrollResult['luxandUuid']?.toString();
  final enrolledCount = enrollResult['enrolledCount'] as int? ?? 0;
  print('✅ Enrolled $enrolledCount face(s) from 3 verification steps. UUID: $luxandUuid');
  
  // Clean up test enrollment if it exists
  if (_pendingTestUuidCleanup.isNotEmpty) {
    await _cleanupTestEnrollment(_pendingTestUuidCleanup, _pendingTestEmail);
    _pendingTestUuidCleanup = '';
    _pendingTestEmail = '';
  }
  
  // ... rest of code
} else {
  // Even if enrollment fails, clean up test enrollment
  if (_pendingTestUuidCleanup.isNotEmpty) {
    await _cleanupTestEnrollment(_pendingTestUuidCleanup, _pendingTestEmail);
    _pendingTestUuidCleanup = '';
    _pendingTestEmail = '';
  }
  
  // ... error handling
}
```

#### Step 5: Cleanup in Error Handler

**File**: `lib/screens/fill_information_screen.dart`

**Location**: In catch block (around line 556)

**Change**:
```dart
} catch (e) {
  print('Error submitting form: $e');
  
  // Clean up test enrollment on error
  if (_pendingTestUuidCleanup.isNotEmpty) {
    await _cleanupTestEnrollment(_pendingTestUuidCleanup, _pendingTestEmail);
    _pendingTestUuidCleanup = '';
    _pendingTestEmail = '';
  }
  
  if (mounted) {
    // ... error display
  }
}
```

---

### 4. Lockout Service Persistence

**Problem**: Lockout state is stored in memory, resets on app restart.

**Risk Level**: 🟡 **MEDIUM** - Users can bypass lockout by restarting app.

**Files to Modify**:
- `lib/services/lockout_service.dart`

**Solution**: Store lockout state in SharedPreferences.

#### Step 1: Add SharedPreferences Dependency

**File**: `pubspec.yaml`

**Note**: `shared_preferences` should already be in dependencies. If not, add it.

#### Step 2: Update LockoutService

**File**: `lib/services/lockout_service.dart`

**Replace entire file with**:

```dart
import 'package:shared_preferences/shared_preferences.dart';

class LockoutService {
  static const String _lockoutTimeKey = 'lockout_time';
  static const String _failedAttemptsKey = 'failed_attempts';
  static const Duration _lockoutDuration = Duration(minutes: 2);
  static const int _maxFailedAttempts = 5;

  /// Initialize lockout state from SharedPreferences
  static Future<void> _initialize() async {
    // This is called automatically when needed
  }

  /// Get lockout time from storage
  static Future<DateTime?> _getLockoutTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lockoutTimeKey);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      print('❌ Error getting lockout time: $e');
    }
    return null;
  }

  /// Save lockout time to storage
  static Future<void> _setLockoutTime(DateTime? time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (time == null) {
        await prefs.remove(_lockoutTimeKey);
      } else {
        await prefs.setInt(_lockoutTimeKey, time.millisecondsSinceEpoch);
      }
    } catch (e) {
      print('❌ Error setting lockout time: $e');
    }
  }

  /// Get failed attempts from storage
  static Future<int> _getFailedAttempts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_failedAttemptsKey) ?? 0;
    } catch (e) {
      print('❌ Error getting failed attempts: $e');
      return 0;
    }
  }

  /// Save failed attempts to storage
  static Future<void> _setFailedAttempts(int attempts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_failedAttemptsKey, attempts);
    } catch (e) {
      print('❌ Error setting failed attempts: $e');
    }
  }

  static Future<void> setLockout() async {
    final now = DateTime.now();
    final currentAttempts = await _getFailedAttempts();
    await _setLockoutTime(now);
    await _setFailedAttempts(currentAttempts + 1);
    print('🚨 LOCKOUT ACTIVATED: Failed attempt ${currentAttempts + 1}/$_maxFailedAttempts');
  }

  static Future<void> recordFailedAttempt() async {
    final currentAttempts = await _getFailedAttempts();
    final newAttempts = currentAttempts + 1;
    await _setFailedAttempts(newAttempts);
    print('🚨 FAILED ATTEMPT: $newAttempts/$_maxFailedAttempts');
    
    if (newAttempts >= _maxFailedAttempts) {
      await setLockout();
    }
  }

  static Future<bool> isLockedOut() async {
    final lockoutTime = await _getLockoutTime();
    if (lockoutTime == null) return false;

    final now = DateTime.now();
    final timeSinceLockout = now.difference(lockoutTime);

    if (timeSinceLockout > _lockoutDuration) {
      // Reset lockout after duration
      await _setLockoutTime(null);
      await _setFailedAttempts(0);
      return false;
    }

    return true;
  }

  static Future<Duration?> getRemainingTime() async {
    final lockoutTime = await _getLockoutTime();
    if (lockoutTime == null) return null;

    final now = DateTime.now();
    final timeSinceLockout = now.difference(lockoutTime);

    if (timeSinceLockout > _lockoutDuration) {
      await _setLockoutTime(null);
      await _setFailedAttempts(0);
      return null;
    }

    return _lockoutDuration - timeSinceLockout;
  }

  static Future<void> clearLockout() async {
    await _setLockoutTime(null);
    await _setFailedAttempts(0);
  }

  static Future<int> getFailedAttempts() async {
    return await _getFailedAttempts();
  }

  static Future<bool> shouldBlockAccess() async {
    final isLocked = await isLockedOut();
    final attempts = await getFailedAttempts();
    return isLocked || attempts >= _maxFailedAttempts;
  }

  /// Reset lockout on app restart (for development/testing)
  static Future<void> resetLockout() async {
    await clearLockout();
    print('🔄 Lockout reset for testing');
  }

  /// Force clear lockout immediately (for debugging)
  static Future<void> forceClearLockout() async {
    await clearLockout();
    print('🔄 FORCE CLEAR: Lockout cleared immediately');
  }

  /// Get lockout status for debugging
  static Future<Map<String, dynamic>> getLockoutStatus() async {
    final lockoutTime = await _getLockoutTime();
    final attempts = await getFailedAttempts();
    final remaining = await getRemainingTime();
    
    return {
      'isLockedOut': await isLockedOut(),
      'failedAttempts': attempts,
      'maxFailedAttempts': _maxFailedAttempts,
      'lockoutTime': lockoutTime?.toIso8601String(),
      'remainingTime': remaining?.inSeconds,
    };
  }
}
```

#### Step 3: Update All Call Sites

**Files to Update**:
- `lib/screens/face_login_screen.dart`

**Change all synchronous calls to async**:

```dart
// BEFORE
if (LockoutService.isLockedOut()) {
  // ...
}

// AFTER
if (await LockoutService.isLockedOut()) {
  // ...
}
```

**Search for all usages**:
```bash
grep -r "LockoutService\." lib/
```

Update all to use `await` where needed.

---

## 🟢 LOW PRIORITY FIXES

### 5. Unused Code Cleanup

**Problem**: 33 linter warnings for unused code.

**Risk Level**: 🟢 **LOW** - Doesn't affect functionality, but increases maintenance burden.

**Solution**: Remove unused methods and fields.

#### Automated Cleanup

**Command**:
```bash
flutter analyze
```

This will show all unused code warnings.

#### Manual Cleanup List

**Files to Clean**:

1. **`lib/services/production_face_recognition_service.dart`**:
   - Remove: `_storeFaceEmbedding` (line 474)
   - Remove: `_getAllStoredFaceEmbeddings` (line 513)
   - Remove: `_validateEmbeddingDiversity` (line 532)
   - Remove: `_getEmbeddingCountForUser` (line 713)
   - Remove: `_findPermanentUserId` (line 741) - **WAIT**: Check if this is actually used
   - Remove: `_getCompatibleSecondaryEmbedding` (line 831)
   - Remove unused parameters: `landmarkFeatures`, `featureDistances` (lines 480-481)

2. **`lib/screens/face_login_screen.dart`**:
   - Remove: `_qualityAcceptableLastFrame` (line 61)
   - Remove: `_embeddingCaptureInterval` (line 67)
   - Remove: `_lastEmbeddingCaptureTime` (line 72)
   - Remove: `_estimateFaceRegionBrightness` (line 571)
   - Remove: `_appendDeepScanFrame` (line 659)
   - Remove: `_averageEmbeddings` (line 700)
   - Remove: `_normalizeEmbedding` (line 719)
   - Remove: `_calculateEmbeddingStability` (line 735)
   - Remove: `_calculateBoundingBoxStability` (line 757)
   - Remove: `_isEmbeddingValid` (line 820)
   - Remove: `_evaluateLiveness` (line 831)

3. **`lib/screens/face_movecloser_screen.dart`**:
   - Remove: `phoneNumber` variable (line 551)

4. **`lib/screens/fill_information_screen.dart`**:
   - Remove: `_extractRealBiometricFeatures` (line 837)

5. **`lib/services/face_recognition_service.dart`**:
   - Remove: `_uniquenessThreshold` (line 32)
   - Remove: `_maxSecondBestSimilarity` (line 33)
   - Remove: `_getAllStoredEmbeddings` (line 167)

6. **`lib/widgets/image_cropper.dart`**:
   - Remove: `_imageProvider` (line 25)
   - Remove: `_offset` (line 27)
   - Remove: `_isDragging` (line 28)
   - Remove: `matrix` variable (line 73)

7. **`lib/widgets/product_card.dart`**:
   - Remove: `_navigateToComments` (line 251)
   - Remove: `_formatDate` (line 2321)

8. **`lib/widgets/professional_face_guide.dart`**:
   - Remove: `_buildInstructions` (line 307)
   - Remove: `_buildStatusIndicator` (line 385)
   - Remove: `_buildActionButtons` (line 493)

**Note**: Before removing, verify the code is truly unused by searching for references:
```bash
grep -r "methodName" lib/
```

---

### 6. Input Validation Improvements

**Problem**: Some inputs lack proper validation (username length, age range).

**Risk Level**: 🟢 **LOW** - Edge cases, but good practice.

**Files to Modify**:
- `lib/screens/fill_information_screen.dart`

#### Step 1: Username Validation

**File**: `lib/screens/fill_information_screen.dart`

**Location**: Around line 780

**Change**:
```dart
// BEFORE
if (label == "Username" && value.length < 8) {
  return "Username must be at least 8 characters long";
}

// AFTER
if (label == "Username") {
  if (value.length < 8) {
    return "Username must be at least 8 characters long";
  }
  if (value.length > 30) {
    return "Username must be 30 characters or less";
  }
  // Check for valid characters (alphanumeric and underscore only)
  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
    return "Username can only contain letters, numbers, and underscores";
  }
}
```

#### Step 2: Age Validation

**File**: `lib/screens/fill_information_screen.dart`

**Location**: Around line 220

**Change**:
```dart
// BEFORE
final age = int.tryParse(ageController.text);
if (age == null) {
  throw Exception('Invalid age format');
}

// AFTER
final age = int.tryParse(ageController.text);
if (age == null) {
  throw Exception('Invalid age format');
}
if (age < 13) {
  throw Exception('You must be at least 13 years old to use this app');
}
if (age > 150) {
  throw Exception('Please enter a valid age');
}
```

#### Step 3: Email Validation

**File**: `lib/screens/fill_information_screen.dart`

**Location**: Add validation in form submission (around line 150)

**Add**:
```dart
// Validate email format if email signup
if (userEmail.isNotEmpty) {
  final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
  if (!emailRegex.hasMatch(userEmail)) {
    throw Exception('Please enter a valid email address');
  }
}
```

#### Step 4: Phone Number Validation

**File**: `lib/screens/fill_information_screen.dart`

**Location**: Add validation in form submission (around line 150)

**Add**:
```dart
// Validate phone format if phone signup
if (userPhone.isNotEmpty) {
  // Remove spaces and special characters for validation
  final cleanPhone = userPhone.replaceAll(RegExp(r'[^\d+]'), '');
  if (cleanPhone.length < 10 || cleanPhone.length > 15) {
    throw Exception('Please enter a valid phone number');
  }
}
```

---

### 7. Network Monitoring Optimization

**Problem**: Network monitoring checks every 3 seconds, may drain battery.

**Risk Level**: 🟢 **LOW** - Minor performance impact.

**Files to Modify**:
- `lib/services/network_service.dart`

#### Step 1: Adaptive Monitoring Frequency

**File**: `lib/services/network_service.dart`

**Location**: Around line 40

**Change**:
```dart
// BEFORE
_connectionTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {

// AFTER
// Adaptive monitoring: check more frequently when disconnected, less when connected
static Duration _getMonitoringInterval() {
  if (!_isConnected) {
    return const Duration(seconds: 2); // Check every 2s when disconnected
  }
  return const Duration(seconds: 5); // Check every 5s when connected
}

static void startMonitoring() {
  _connectionTimer?.cancel();
  
  void checkConnection() async {
    // ... existing check logic ...
    
    // Schedule next check with adaptive interval
    _connectionTimer = Timer(_getMonitoringInterval(), checkConnection);
  }
  
  // Start first check
  checkConnection();
}
```

#### Step 2: Pause Monitoring When App is Backgrounded

**File**: `lib/services/network_service.dart`

**Add**:
```dart
import 'package:flutter/widgets.dart';

class NetworkService {
  // ... existing code ...
  
  static AppLifecycleState? _appLifecycleState;
  
  static void _handleAppLifecycleChange(AppLifecycleState state) {
    _appLifecycleState = state;
    
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive) {
      // Pause monitoring when app is backgrounded
      stopMonitoring();
    } else if (state == AppLifecycleState.resumed) {
      // Resume monitoring when app comes to foreground
      startMonitoring();
    }
  }
  
  // Call this from main.dart
  static void setupLifecycleObserver() {
    WidgetsBinding.instance.addObserver(
      _AppLifecycleObserver(),
    );
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NetworkService._handleAppLifecycleChange(state);
  }
}
```

**File**: `lib/main.dart`

**Add**:
```dart
void main() async {
  // ... existing code ...
  
  // Setup network monitoring lifecycle
  NetworkService.setupLifecycleObserver();
  
  // ... rest of main()
}
```

---

## Implementation Checklist

### Critical Fixes
- [ ] **Fix 1**: Update Firestore security rules
  - [ ] Add `firebaseAuthUid` to user documents
  - [ ] Create new `firestore.rules` file
  - [ ] Deploy rules to Firebase
  - [ ] Test security rules

- [ ] **Fix 2**: Secure Gmail password
  - [ ] Choose solution (Option A, B, or C)
  - [ ] Implement chosen solution
  - [ ] Test email sending
  - [ ] Update `.gitignore`

### Medium Fixes
- [ ] **Fix 3**: Test enrollment cleanup
  - [ ] Add cleanup function
  - [ ] Update pre-check logic
  - [ ] Add cleanup in error handlers
  - [ ] Test cleanup on failure

- [ ] **Fix 4**: Lockout service persistence
  - [ ] Update `LockoutService` to use SharedPreferences
  - [ ] Update all call sites to use `await`
  - [ ] Test lockout persistence across app restarts

### Low Priority Fixes
- [ ] **Fix 5**: Unused code cleanup
  - [ ] Remove unused methods/fields
  - [ ] Run `flutter analyze` to verify
  - [ ] Test app functionality

- [ ] **Fix 6**: Input validation
  - [ ] Add username max length
  - [ ] Add age range validation
  - [ ] Add email format validation
  - [ ] Add phone number validation

- [ ] **Fix 7**: Network monitoring optimization
  - [ ] Implement adaptive monitoring frequency
  - [ ] Add app lifecycle observer
  - [ ] Test battery impact

---

## Testing Plan

### Security Testing
1. **Firestore Rules**:
   - Test authenticated user can read own data
   - Test authenticated user CANNOT read other users' data
   - Test unauthenticated user CANNOT access protected collections

2. **Gmail Password**:
   - Verify credentials are not in source code
   - Test email sending still works
   - Verify `.env` is in `.gitignore`

### Functionality Testing
1. **Test Enrollment Cleanup**:
   - Simulate enrollment failure
   - Verify test enrollment is cleaned up

2. **Lockout Persistence**:
   - Trigger lockout
   - Restart app
   - Verify lockout is still active

3. **Input Validation**:
   - Test invalid usernames (too short, too long, invalid chars)
   - Test invalid ages (negative, too high)
   - Test invalid email formats
   - Test invalid phone numbers

### Performance Testing
1. **Network Monitoring**:
   - Monitor battery usage
   - Verify monitoring pauses when app is backgrounded

---

## Notes

1. **Firestore Rules**: The rules provided are a starting point. You may need to adjust based on your specific use cases.

2. **Gmail Password**: For production, strongly consider moving email sending to Firebase Functions (Option C) for maximum security.

3. **Lockout Service**: The async changes will require updating all call sites. Use your IDE's "Find Usages" feature to locate all references.

4. **Testing**: Test thoroughly after each fix, especially the critical security fixes.

5. **Backup**: Before making changes, commit your current code to Git.

---

## Questions or Issues?

If you encounter any issues during implementation:
1. Check the error messages carefully
2. Review the code examples in this document
3. Test incrementally (one fix at a time)
4. Consult Firebase documentation for security rules syntax

Good luck with the fixes! 🚀

