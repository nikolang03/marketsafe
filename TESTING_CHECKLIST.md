# Face Recognition System - Testing Checklist

## 🎯 Critical Tests (Must Pass)

### 1. **Registration Flow - Signup with Face**
- [ ] **Blink Twice Screen**
  - Face detected with both eyes visible
  - Blink detection works correctly
  - Landmark features extracted (check logs: "✅ Landmark features extracted")
  - Embedding stored with email/phone binding
  - Navigates to "Move Closer" screen

- [ ] **Move Closer Screen**
  - Face size validation (minimum 200px)
  - Progress bar updates correctly
  - Face quality checks pass (head pose, eyes, centering)
  - Landmark features extracted (check logs)
  - Primary embedding registered successfully
  - Navigates to "Head Movement" screen

- [ ] **Head Movement Screen**
  - Left head turn detected
  - Right head turn detected
  - Landmark features extracted (check logs)
  - Additional embedding registered
  - Navigates to "Fill Information" screen

### 2. **Login Flow - Face Recognition**
- [ ] **Email/Phone Verification**
  - Enter valid email → User found
  - Enter valid phone → User found
  - Enter invalid email/phone → Error shown
  - Enter unregistered email/phone → "Account Not Found"

- [ ] **Face Scanning**
  - Progress bar shows:
    - Size progress (0-25%)
    - Features progress (0-25%) - requires ALL 4 features
    - Centering progress (0-20%)
    - Lighting progress (0-15%)
    - Quality progress (0-15%)
  - Face requirements:
    - Face size ≥ 180px
    - ALL features visible (both eyes, nose, mouth)
    - Face centered (25%-75% of screen)
    - Head pose < 15° tilt
    - Both eyes open (>0.3)
    - Natural expression (<0.85 smiling)

- [ ] **Face Verification**
  - **Same User (Correct)**
    - Similarity ≥ 99.5% (check logs)
    - Landmark features match (≥80% similarity)
    - Feature distances match (<10% error)
    - Login succeeds → Navigate to main app

  - **Different User (Security Test)**
    - Enter registered email
    - Show different face
    - Similarity should be < 99.5%
    - Should be REJECTED with error
    - Check logs: "🚨 CRITICAL SECURITY REJECTION"

  - **Similar-Looking Person**
    - Enter registered email
    - Show similar face (family member, etc.)
    - Similarity should be 95-99% (below 99.5%)
    - Should be REJECTED
    - Check logs: "🚨 Similarity < ULTRA PERFECT threshold"

### 3. **Profile Photo Verification**
- [ ] **Upload Profile Photo (Same User)**
  - Upload photo of registered user
  - Face verification passes (≥98.5% similarity)
  - Profile photo stored successfully

- [ ] **Upload Profile Photo (Different User)**
  - Upload photo of different person
  - Face verification fails (<98.5% similarity)
  - Error shown: "Face does not match registered face"

### 4. **Feature-Level Recognition Validation**
- [ ] **Check Logs During Registration**
  - Look for: "✅ Landmark features extracted: leftEye, rightEye, noseBase, ..."
  - Look for: "✅ Feature distances calculated: eyeDistance, noseMouthDistance, ..."
  - Look for: "✅ This embedding knows 'whose face is this' at feature level"

- [ ] **Check Logs During Login**
  - Look for: "✅ Landmark features match: similarity=0.XX (>= 0.80)"
  - Look for: "✅ Feature distances match: avgError=X.XXX < 0.1"
  - If mismatch: "🚨 Landmark feature mismatch" should appear

### 5. **Security Tests (Critical)**
- [ ] **Unauthorized Access Prevention**
  - Unregistered user enters registered email
  - Shows different face
  - **MUST BE REJECTED** - Check logs for security warnings
  - Similarity should be < 99.5%

- [ ] **Email-to-Face Binding**
  - User A registers with email A
  - User B tries to login with email A but shows face B
  - **MUST BE REJECTED** - Face doesn't match email

- [ ] **Email/Phone Verification**
  - Login screen requires email/phone before face scan
  - Camera doesn't start until email/phone verified
  - Face detection blocked if email/phone not verified

### 6. **Edge Cases**
- [ ] **Missing Features**
  - Face with only one eye visible
  - Face with nose/mouth not detected
  - Should show error: "Face features not complete"

- [ ] **Poor Lighting**
  - Very dark lighting
  - Very bright lighting
  - Progress bar shows lighting quality
  - Should still work if face is detectable

- [ ] **Face Not Centered**
  - Face too far left/right
  - Face too high/low
  - Progress bar shows centering progress
  - Should require face in center 50% (25%-75%)

- [ ] **Head Tilted**
  - Head tilted > 15°
  - Should show warning in logs
  - Should require better head pose

- [ ] **Multiple Faces**
  - Multiple faces in frame
  - Should use first detected face
  - Should work correctly

### 7. **Performance Tests**
- [ ] **Registration Speed**
  - Blink screen: < 5 seconds
  - Move closer screen: < 10 seconds
  - Head movement screen: < 10 seconds

- [ ] **Login Speed**
  - Face detection: Real-time (no lag)
  - Face verification: < 3 seconds
  - Overall login: < 5 seconds

- [ ] **Progress Bar Updates**
  - Updates smoothly (no jank)
  - Shows accurate progress (0-100%)
  - Updates in real-time as face position changes

### 8. **Log Validation (Check Console)**

#### **During Registration:**
```
✅ Landmark features extracted: leftEye, rightEye, noseBase, mouthBottom, ...
✅ Feature distances calculated: eyeDistance, noseMouthDistance, mouthWidth, ...
✅ This embedding knows "whose face is this" at feature level
✅ Storing landmark features: leftEye, rightEye, ...
✅ Storing feature distances: eyeDistance, noseMouthDistance, ...
```

#### **During Login (Success):**
```
✅ Current face landmark features extracted: leftEye, rightEye, ...
✅ Landmark features match: similarity=0.XXXX (>= 0.80)
✅ Feature distances match: avgError=0.XXXX < 0.1
✅✅✅ PERFECT RECOGNITION VALIDATION PASSED: Similarity 0.XXXX >= 0.995
```

#### **During Login (Rejection):**
```
🚨 Landmark feature mismatch: similarity=0.XXXX < 0.80
🚨🚨🚨 CRITICAL SECURITY REJECTION: Similarity 0.XXXX < ULTRA PERFECT threshold 0.995
```

### 9. **Database Verification**
- [ ] **Firestore Structure**
  - Check `face_embeddings/{userId}` collection
  - Verify `embeddings` array contains:
    - `embedding`: List of 512 values
    - `source`: 'blink_twice', 'move_closer', 'head_movement', etc.
    - `email`: User's email
    - `phoneNumber`: User's phone
    - `landmarkFeatures`: Map with eye, nose, mouth positions
    - `featureDistances`: Map with eye distance, nose-mouth distance, etc.

### 10. **UI/UX Tests**
- [ ] **Progress Bar**
  - Shows 5 components: Size, Features, Centering, Lighting, Quality
  - Updates smoothly as face position changes
  - Green when ready, red when not ready

- [ ] **Error Messages**
  - Clear and helpful
  - Shows what's wrong (face too small, not centered, etc.)
  - Provides guidance on how to fix

- [ ] **Camera Preview**
  - Shows elliptical face frame
  - Face detection indicator (green border when detected)
  - Smooth camera preview (60 FPS)

## 📋 Test Scenarios

### Scenario 1: Complete Signup Flow
1. Start signup
2. Complete OTP verification
3. Complete all 3 face verification steps (blink, move closer, head movement)
4. Fill information
5. Upload profile photo
6. **Expected**: User registered successfully with 4+ face embeddings stored

### Scenario 2: Complete Login Flow (Same User)
1. Enter registered email
2. Position face correctly (all requirements met)
3. Wait for face scan
4. **Expected**: Login succeeds, navigate to main app

### Scenario 3: Login with Different Face (Security)
1. Enter registered email
2. Show different person's face
3. **Expected**: Login fails with security error

### Scenario 4: Login with Unregistered Email
1. Enter unregistered email
2. **Expected**: "Account Not Found" error before face scan

### Scenario 5: Profile Photo Upload (Same User)
1. Log in successfully
2. Go to profile
3. Upload profile photo of same user
4. **Expected**: Photo upload succeeds (≥98.5% similarity)

### Scenario 6: Profile Photo Upload (Different User)
1. Log in successfully
2. Go to profile
3. Upload photo of different person
4. **Expected**: Photo upload fails with verification error

## 🔍 Debug Commands

### Check Logs for Feature Extraction:
```bash
# During registration, look for:
✅ Landmark features extracted
✅ Feature distances calculated

# During login, look for:
✅ Landmark features match
✅ Feature distances match
```

### Check Logs for Security:
```bash
# Should see for unauthorized access:
🚨🚨🚨 CRITICAL SECURITY REJECTION
🚨 Landmark feature mismatch
```

### Check Similarity Scores:
```bash
# Same user should show:
Similarity: 0.9950 - 0.9998 (99.5% - 99.98%)

# Different user should show:
Similarity: 0.7000 - 0.9900 (70% - 99%) - REJECTED
```

## ✅ Success Criteria

1. ✅ Same user can log in successfully (99.5%+ similarity)
2. ✅ Different user is REJECTED (<99.5% similarity)
3. ✅ Similar-looking person is REJECTED (<99.5% similarity)
4. ✅ Landmark features extracted during registration
5. ✅ Landmark features validated during login
6. ✅ Email/phone binding works correctly
7. ✅ Profile photo verification works (98.5%+ for same user)
8. ✅ Progress bar shows accurate progress
9. ✅ All security checks pass
10. ✅ No performance issues (smooth 60 FPS)

## 🚨 Known Issues to Watch For

1. **0.9 Similarity Issue**: If all similarities are ~0.9, embedding variance is too low
   - Check logs: "🚨 Embedding variance too low"
   - Solution: Ensure face alignment and quality checks are working

2. **Model Failure**: If all similarities are >0.99 for different people
   - Check logs: "🚨 CRITICAL: Most similarities are extremely high"
   - Solution: Check embedding diversity during registration

3. **Missing Features**: If landmark features not extracted
   - Check logs: "🚨 CRITICAL: Missing essential facial features"
   - Solution: Ensure face has all features visible (eyes, nose, mouth)

4. **Navigation Issues**: If app redirects to signup after successful login
   - Check: `signupCompleted` field in user data
   - Check: `userData` returned from `verifyUserFace`

## 📝 Test Report Template

```
Test Date: ___________
Tester: ___________

Registration:
- Blink: ✅/❌
- Move Closer: ✅/❌
- Head Movement: ✅/❌

Login:
- Same User: ✅/❌ (Similarity: ____%)
- Different User: ✅/❌ (Rejected: Yes/No)
- Similar Person: ✅/❌ (Rejected: Yes/No)

Profile Photo:
- Same User: ✅/❌
- Different User: ✅/❌ (Rejected: Yes/No)

Security:
- Unauthorized Access Blocked: ✅/❌
- Email-to-Face Binding: ✅/❌

Performance:
- Registration Speed: ____ seconds
- Login Speed: ____ seconds
- Progress Bar: Smooth/Janky

Issues Found:
1. ___________
2. ___________
3. ___________
```





















