# Backend Server Setup Guide

## Overview

Your Flutter app uses a secure backend server to communicate with Luxand Cloud API. This keeps your API key secure on the server.

**Flow:** Flutter → Your Backend → Luxand Cloud → Response

## Step 1: Deploy Your Backend Server

Deploy the Node.js backend server (from the provided code) to:
- Heroku
- Google Cloud Platform (GCP)
- AWS
- Azure
- Or any Node.js hosting service

### Backend Environment Variables

Set these on your backend server:
```
LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1
FIREBASE_PROJECT_ID=your-firebase-project-id
GOOGLE_APPLICATION_CREDENTIALS=/path/to/firebase-adminsdk.json
SIMILARITY_THRESHOLD=0.85
LIVENESS_THRESHOLD=0.90
PORT=4000
```

## Step 2: Configure Backend URL in Flutter (Option A - Environment Variable)

### For Development (Run/Debug)

**Windows (PowerShell):**
```powershell
$env:FACE_AUTH_BACKEND_URL="https://your-backend.com"; flutter run
```

**Windows (CMD):**
```cmd
set FACE_AUTH_BACKEND_URL=https://your-backend.com && flutter run
```

**macOS/Linux:**
```bash
export FACE_AUTH_BACKEND_URL=https://your-backend.com
flutter run
```

**Or use --dart-define:**
```bash
flutter run --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend.com
```

### For Android Build

**Debug:**
```bash
flutter build apk --debug --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend.com
```

**Release:**
```bash
flutter build apk --release --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend.com
```

### For iOS Build

**Debug:**
```bash
flutter build ios --debug --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend.com
```

**Release:**
```bash
flutter build ios --release --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend.com
```

### For VS Code Launch Configuration

Create or update `.vscode/launch.json`:
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "MarketSafe",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=FACE_AUTH_BACKEND_URL=https://your-backend.com"
      ]
    }
  ]
}
```

### For Android Studio Run Configuration

1. Go to Run → Edit Configurations
2. Add to "Additional run args":
   ```
   --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend.com
   ```

## Step 3: Verify Configuration

The app will log the backend URL on startup. Check console logs for:
```
🔍 Backend URL: https://your-backend.com
```

## Backend Endpoints Required

Your backend must implement:

1. **POST /api/enroll**
   - Input: `{ email, photoBase64 }`
   - Output: `{ ok: true, uuid: "luxand-uuid" }`
   - Backend: Runs liveness check → Calls Luxand /photo → Stores uuid in Firestore

2. **POST /api/verify**
   - Input: `{ email, photoBase64 }`
   - Output: `{ ok: true/false, similarity: 0.85, threshold: 0.85, message: "verified" }`
   - Backend: Runs liveness check → Calls Luxand /compare → Returns result

3. **GET /api/health**
   - Output: `{ ok: true, time: "2024-01-01T00:00:00Z" }`

## Testing

1. Deploy your backend server
2. Test health endpoint: `curl https://your-backend.com/api/health`
3. Configure Flutter with backend URL
4. Run the app and test enrollment/verification

## Troubleshooting

**Error: "Backend URL not configured"**
- Make sure you set `FACE_AUTH_BACKEND_URL` environment variable
- Or update the default URL in `production_face_recognition_service.dart` line 34

**Error: "Backend server not reachable"**
- Check your backend is deployed and accessible
- Verify the URL is correct (no trailing slash)
- Check HTTPS is enabled

**Error: "Network error"**
- Check internet connection
- Verify backend CORS settings allow your app origin
- Check backend logs for errors



