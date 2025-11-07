# Public Deployment Guide - App & Admin Web Panel

This guide will help you deploy both your Flutter app and admin web panel publicly so they can be accessed from anywhere.

## Overview

You need to deploy:
1. **Backend API** (Node.js) - For face recognition
2. **Admin Web Panel** (HTML files) - For admin management
3. **Flutter App** (APK) - Update with public backend URL

---

## Part 1: Deploy Backend API (Node.js)

### Step 1: Choose a Hosting Service (FREE Options)

#### Option A: Railway (Recommended - Easiest)
1. Go to https://railway.app
2. Sign up with GitHub
3. Click **"New Project"** → **"Deploy from GitHub repo"**
4. Select your `backend` folder
5. Add environment variables:
   - `LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1`
   - `PORT=4000` (optional, Railway auto-assigns)
   - `SIMILARITY_THRESHOLD=0.85` (optional)
   - `LIVENESS_THRESHOLD=0.90` (optional)
   - `ALLOWED_ORIGINS=*` (allows all origins)
6. Railway will give you a URL like: `https://your-app-name.up.railway.app`
7. **Copy this URL** - you'll need it for the app and web panel

#### Option B: Render
1. Go to https://render.com
2. Sign up with GitHub
3. Click **"New"** → **"Web Service"**
4. Connect your GitHub repo
5. Set:
   - **Root Directory**: `backend`
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
6. Add environment variables (same as Railway)
7. Render gives you: `https://your-app-name.onrender.com`

#### Option C: Fly.io
1. Go to https://fly.io
2. Install Fly CLI: `curl -L https://fly.io/install.sh | sh`
3. In `backend` folder, run: `fly launch`
4. Add secrets: `fly secrets set LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1`
5. Deploy: `fly deploy`
6. Get URL: `https://your-app-name.fly.dev`

### Step 2: Test Your Backend

After deployment, test your backend URL:
```bash
curl https://your-backend-url.com/api/health
```

Should return: `{"ok":true,"time":"..."}`

**✅ Save your backend URL** - You'll need it for the next steps!

---

## Part 2: Deploy Admin Web Panel

### Option A: Firebase Hosting (Recommended - FREE)

1. **Install Firebase CLI** (if not installed):
   ```bash
   npm install -g firebase-tools
   ```

2. **Login to Firebase**:
   ```bash
   firebase login
   ```

3. **Initialize Firebase Hosting** (in your project root):
   ```bash
   cd C:\marketsafe
   firebase init hosting
   ```
   
   When prompted:
   - **What do you want to use as your public directory?** → `web`
   - **Configure as a single-page app?** → `No`
   - **Set up automatic builds and deploys with GitHub?** → `No` (or Yes if you want)

4. **Deploy**:
   ```bash
   firebase deploy --only hosting
   ```

5. Your admin panel will be at: `https://marketsafe-e57cf.web.app` or `https://marketsafe-e57cf.firebaseapp.com`

6. **Access URLs**:
   - Login: `https://marketsafe-e57cf.web.app/login.html`
   - Admin Panel: `https://marketsafe-e57cf.web.app/admin.html`

### Option B: Netlify (FREE)

1. Go to https://netlify.com
2. Sign up with GitHub
3. Click **"Add new site"** → **"Import an existing project"**
4. Connect your GitHub repo
5. Set:
   - **Base directory**: `web`
   - **Build command**: (leave empty)
   - **Publish directory**: `web`
6. Click **"Deploy site"**
7. Your site will be at: `https://your-site-name.netlify.app`

### Option C: Vercel (FREE)

1. Go to https://vercel.com
2. Sign up with GitHub
3. Click **"Add New Project"**
4. Import your GitHub repo
5. Set:
   - **Root Directory**: `web`
   - **Framework Preset**: Other
6. Click **"Deploy"**
7. Your site will be at: `https://your-site-name.vercel.app`

### Step 3: Update Firebase Config in Web Panel

After deploying, make sure your Firebase config in `web/admin.html` and `web/login.html` is correct. It should already be configured, but verify:

```javascript
const FIREBASE_CONFIG = {
    apiKey: "AIzaSyAa-268Fx-XfJTsJLGznwcztd82r2vdf3Q",
    authDomain: "marketsafe-e57cf.firebaseapp.com",
    projectId: "marketsafe-e57cf",
    storageBucket: "marketsafe-e57cf.appspot.com",
    messagingSenderId: "123456789",
    appId: "1:123456789:web:abcdef"
};
```

**✅ Save your web panel URL** - You'll share this with admins!

---

## Part 3: Update Flutter App with Public Backend URL

### Step 1: Update Backend URL in Flutter Code

Edit `lib/services/production_face_recognition_service.dart`:

Find line ~34:
```dart
defaultValue: 'https://your-backend-domain.com', // TODO: Replace with your backend URL
```

Replace with your actual backend URL:
```dart
defaultValue: 'https://your-app-name.up.railway.app', // Your deployed backend URL
```

### Step 2: Build Release APK

```bash
# Navigate to your project root
cd C:\marketsafe

# Build release APK
flutter build apk --release
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

### Step 3: Test the APK

1. Install the APK on a test device
2. Test signup and login
3. Verify face recognition works
4. Test from different network (not your local WiFi)

---

## Part 4: Share Your App & Admin Panel

### For Users (App):
- Share the APK file: `build/app/outputs/flutter-apk/app-release.apk`
- Users can install it on any Android device
- They only need internet connection (no localhost needed)

### For Admins (Web Panel):
- Share the login URL: `https://your-web-panel-url.com/login.html`
- Admins can access from any browser, anywhere
- They need manager/admin credentials

---

## Quick Checklist

### Backend Deployment:
- [ ] Deployed backend to Railway/Render/Fly.io
- [ ] Tested backend health endpoint
- [ ] Saved backend URL

### Web Panel Deployment:
- [ ] Deployed web panel to Firebase Hosting/Netlify/Vercel
- [ ] Tested login page
- [ ] Tested admin panel access
- [ ] Saved web panel URL

### Flutter App:
- [ ] Updated backend URL in `production_face_recognition_service.dart`
- [ ] Built release APK
- [ ] Tested APK on device
- [ ] Verified face recognition works

---

## Important Notes

✅ **Firebase is already global** - Your Firebase project works worldwide automatically

✅ **Backend must be HTTPS** - All hosting services provide HTTPS automatically

✅ **CORS is configured** - Your backend already allows all origins (`ALLOWED_ORIGINS=*`)

✅ **No localhost needed** - Users only need internet connection

✅ **Web panel is accessible from anywhere** - Admins can log in from any browser

---

## Troubleshooting

### Backend Issues:
**"Backend URL not configured" error:**
- Make sure you updated the `defaultValue` in `production_face_recognition_service.dart`
- Verify the URL has no trailing slash

**"Backend server not reachable":**
- Check if backend is deployed and running
- Test with: `curl https://your-backend-url.com/api/health`
- Check backend logs in hosting dashboard

### Web Panel Issues:
**"Firebase config error":**
- Verify Firebase config in `admin.html` and `login.html`
- Make sure Firebase project is set up correctly

**"Cannot access admin panel":**
- Check if files are deployed correctly
- Verify URLs are correct (no typos)
- Check browser console for errors

### App Issues:
**"Network error" in app:**
- Check device has internet connection
- Verify backend URL is correct
- Check backend logs for errors

---

## Security Checklist

- ✅ Luxand API key is on server (not in app)
- ✅ Backend uses HTTPS
- ✅ Firebase is configured
- ✅ No hardcoded localhost IPs in app
- ✅ Admin panel requires authentication
- ✅ CORS is properly configured

---

## After Deployment

1. **Monitor backend logs** for errors
2. **Check hosting dashboard** for usage
3. **Set up alerts** if backend goes down
4. **Share URLs** with users and admins
5. **Consider upgrading** hosting plan if you get many users

---

## Support

If you encounter issues:
1. Check hosting service logs
2. Check browser console (F12) for web panel
3. Check Flutter logs for app
4. Verify all URLs are correct
5. Test backend health endpoint

---

## Example URLs (After Deployment)

- **Backend API**: `https://marketsafe-backend.up.railway.app`
- **Admin Login**: `https://marketsafe-e57cf.web.app/login.html`
- **Admin Panel**: `https://marketsafe-e57cf.web.app/admin.html`
- **App APK**: Share the file from `build/app/outputs/flutter-apk/app-release.apk`

Good luck with your public release! 🚀

