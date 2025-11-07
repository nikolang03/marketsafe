# Face Auth Backend Server

Simple Node.js backend server for MarketSafe face authentication using Luxand Cloud API.

## 🚀 Quick Start

### Step 1: Install Node.js
Make sure you have Node.js 18+ installed:
- Download from: https://nodejs.org/
- Or check: `node --version` (should be 18+)

### Step 2: Install Dependencies
Open terminal in the `backend` folder and run:
```bash
npm install
```

### Step 3: Configure Environment
1. Copy `.env.example` to `.env`:
   ```bash
   copy .env.example .env
   ```
   (On Mac/Linux: `cp .env.example .env`)

2. Open `.env` file and your Luxand API key is already there:
   ```
   LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1
   ```

### Step 4: Start the Server
```bash
npm start
```

You should see:
```
🚀 Server running on port 4000
🚀 Health check: http://localhost:4000/api/health
```

### Step 5: Test It
Open browser and go to:
```
http://localhost:4000/api/health
```

You should see: `{"ok":true,"time":"...","service":"Face Auth Backend"}`

## 📱 Connect Flutter App

### Option 1: Local Testing (Backend on your computer)
1. Make sure backend is running (Step 4 above)
2. Find your computer's IP address:
   - Windows: Open PowerShell, run: `ipconfig` (look for IPv4 Address)
   - Mac/Linux: Run: `ifconfig` or `ip addr`
3. Update Flutter to use your IP:
   ```bash
   flutter run --dart-define=FACE_AUTH_BACKEND_URL=http://YOUR_IP:4000
   ```
   Example: `flutter run --dart-define=FACE_AUTH_BACKEND_URL=http://192.168.1.100:4000`

### Option 2: Deploy to Cloud (Recommended for Production)

#### Deploy to Heroku (Free tier available):
1. Create account at https://heroku.com
2. Install Heroku CLI: https://devcenter.heroku.com/articles/heroku-cli
3. In the `backend` folder, run:
   ```bash
   heroku create your-app-name
   heroku config:set LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1
   git push heroku main
   ```
4. Get your URL: `https://your-app-name.herokuapp.com`
5. Use in Flutter:
   ```bash
   flutter run --dart-define=FACE_AUTH_BACKEND_URL=https://your-app-name.herokuapp.com
   ```

#### Deploy to Railway (Easy):
1. Go to https://railway.app
2. Click "New Project" → "Deploy from GitHub"
3. Select your backend folder
4. Add environment variable: `LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1`
5. Get your URL and use in Flutter

## 🔧 Configuration

Edit `.env` file to change:
- `PORT` - Server port (default: 4000)
- `SIMILARITY_THRESHOLD` - Face match threshold (0.0-1.0, default: 0.85)
- `LIVENESS_THRESHOLD` - Liveness check threshold (0.0-1.0, default: 0.90)
- `ALLOWED_ORIGINS` - CORS allowed origins (default: *)

## 📡 API Endpoints

### POST /api/enroll
Enroll a face photo.
- Body: `{ email: string, photoBase64: string }`
- Returns: `{ ok: true, uuid: string }`

### POST /api/verify
Verify a face photo.
- Body: `{ email: string, photoBase64: string }`
- Returns: `{ ok: true/false, similarity: number, message: string }`

### GET /api/health
Health check.
- Returns: `{ ok: true, time: string }`

## 🐛 Troubleshooting

**"Missing LUXAND_API_KEY"**
- Make sure `.env` file exists and has `LUXAND_API_KEY=...`

**"Port already in use"**
- Change `PORT` in `.env` to another number (e.g., 4001)

**"Cannot connect from Flutter"**
- Make sure backend is running
- Check firewall allows port 4000
- For local testing, use your computer's IP, not `localhost`

## 📝 Notes

- The backend keeps your Luxand API key secure (not in Flutter app)
- All face images are sent as Base64 strings
- Backend handles liveness checks and Luxand API calls
- No database needed - Luxand stores the faces



