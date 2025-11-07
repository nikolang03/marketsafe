# Global APK Release Guide

## Quick Steps to Release Your App Globally

### Step 1: Deploy Backend to Public Hosting (FREE Options)

Choose one of these free hosting services:

#### Option A: Railway (Recommended - Easiest)
1. Go to https://railway.app
2. Sign up with GitHub
3. Click "New Project" → "Deploy from GitHub repo"
4. Select your `backend` folder
5. Add environment variables:
   - `LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1`
   - `PORT=4000` (optional, Railway auto-assigns)
   - `SIMILARITY_THRESHOLD=0.85` (optional)
   - `LIVENESS_THRESHOLD=0.90` (optional)
6. Railway will give you a URL like: `https://your-app-name.up.railway.app`
7. **Copy this URL** - you'll need it for Step 2

#### Option B: Render
1. Go to https://render.com
2. Sign up with GitHub
3. Click "New" → "Web Service"
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

### Step 3: Update Flutter App with Backend URL

You have 2 options:

#### Option A: Hardcode Backend URL (Easiest for APK)

Edit `lib/services/production_face_recognition_service.dart`:

Find line 34:
```dart
defaultValue: 'https://your-backend-domain.com', // TODO: Replace with your backend URL
```

Replace with your actual backend URL:
```dart
defaultValue: 'https://your-app-name.up.railway.app', // Your deployed backend URL
```

#### Option B: Build APK with Environment Variable (More Flexible)

Build your APK with:
```bash
flutter build apk --release --dart-define=FACE_AUTH_BACKEND_URL=https://your-app-name.up.railway.app
```

### Step 4: Build Release APK

```bash
# Navigate to your project root
cd C:\marketsafe

# Build release APK
flutter build apk --release --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend-url.com
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

### Step 5: Test the APK

1. Install the APK on a test device
2. Test signup and login
3. Verify face recognition works
4. Test from different network (not your local WiFi)

## Important Notes

✅ **Firebase is already global** - Your Firebase project works worldwide automatically

✅ **Backend must be HTTPS** - All hosting services provide HTTPS automatically

✅ **CORS is configured** - Your backend already allows all origins (`ALLOWED_ORIGINS=*`)

✅ **No localhost needed** - Users only need internet connection

## Troubleshooting

**"Backend URL not configured" error:**
- Make sure you updated the `defaultValue` in `production_face_recognition_service.dart`
- Or use `--dart-define` when building

**"Backend server not reachable":**
- Check if backend is deployed and running
- Test with: `curl https://your-backend-url.com/api/health`
- Verify the URL has no trailing slash

**"Network error" in app:**
- Check device has internet connection
- Verify backend URL is correct
- Check backend logs for errors

## Security Checklist

- ✅ Luxand API key is on server (not in app)
- ✅ Backend uses HTTPS
- ✅ Firebase is configured
- ✅ No hardcoded localhost IPs in app

## After Release

1. Monitor backend logs for errors
2. Check Railway/Render dashboard for usage
3. Set up alerts if backend goes down
4. Consider upgrading hosting plan if you get many users

