# Quick Deploy Guide - Step by Step

## 🚀 Fastest Way to Deploy Everything

### Step 1: Deploy Backend (5 minutes)

**Using Railway (Easiest):**

1. Go to https://railway.app → Sign up with GitHub
2. Click **"New Project"** → **"Deploy from GitHub repo"**
3. Select your repository
4. Click **"Add Service"** → **"GitHub Repo"**
5. Select your repo → Choose `backend` folder
6. Go to **"Variables"** tab → Add:
   ```
   LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1
   PORT=4000
   ALLOWED_ORIGINS=*
   ```
7. Wait for deployment → Copy the URL (e.g., `https://marketsafe-backend.up.railway.app`)
8. **✅ Save this URL!**

### Step 2: Deploy Admin Web Panel (5 minutes)

**Using Firebase Hosting:**

1. Open terminal in your project root (`C:\marketsafe`)
2. Run:
   ```bash
   npm install -g firebase-tools
   firebase login
   firebase init hosting
   ```
3. When prompted:
   - **Public directory?** → Type: `web`
   - **Single-page app?** → Type: `No`
   - **GitHub deploys?** → Type: `No`
4. Deploy:
   ```bash
   firebase deploy --only hosting
   ```
5. Your admin panel will be at: `https://marketsafe-e57cf.web.app`
6. **✅ Save this URL!**

### Step 3: Update Flutter App (2 minutes)

1. Open `lib/services/production_face_recognition_service.dart`
2. Find line 34:
   ```dart
   defaultValue: 'https://your-backend-domain.com',
   ```
3. Replace with your Railway URL:
   ```dart
   defaultValue: 'https://marketsafe-backend.up.railway.app',
   ```
4. Save the file

### Step 4: Build APK (3 minutes)

```bash
cd C:\marketsafe
flutter build apk --release
```

Your APK is at: `build/app/outputs/flutter-apk/app-release.apk`

### Step 5: Test Everything

1. **Test Backend:**
   - Open: `https://your-backend-url.com/api/health`
   - Should show: `{"ok":true}`

2. **Test Admin Panel:**
   - Open: `https://marketsafe-e57cf.web.app/login.html`
   - Login with manager credentials

3. **Test App:**
   - Install APK on device
   - Test signup/login
   - Verify face recognition works

## ✅ Done!

- **App APK**: `build/app/outputs/flutter-apk/app-release.apk`
- **Admin Login**: `https://marketsafe-e57cf.web.app/login.html`
- **Backend**: `https://your-backend-url.com`

Share the APK and admin login URL with your users!

