# 🎯 Simple Setup Guide - Step by Step

Don't worry! I'll guide you through everything step by step.

## ✅ What You Have Now

I just created a complete backend server for you in the `backend` folder! You don't need to write any code.

## 📋 Step-by-Step Instructions

### Step 1: Check if Node.js is Installed

1. Open PowerShell (Windows) or Terminal (Mac/Linux)
2. Type: `node --version`
3. If you see a version number (like `v18.0.0`), you're good! ✅
4. If you see "command not found", install Node.js:
   - Go to: https://nodejs.org/
   - Download and install the LTS version

### Step 2: Install Backend Dependencies

1. Open PowerShell/Terminal
2. Go to your project folder:
   ```bash
   cd c:\marketsafe\backend
   ```
3. Install packages:
   ```bash
   npm install
   ```
4. Wait for it to finish (takes 1-2 minutes)

### Step 3: Create Environment File

1. In the `backend` folder, copy `.env.example` to `.env`:
   
   **Windows (PowerShell):**
   ```powershell
   copy .env.example .env
   ```
   
   **Windows (CMD):**
   ```cmd
   copy .env.example .env
   ```
   
   **Mac/Linux:**
   ```bash
   cp .env.example .env
   ```

2. Open the `.env` file (it's in the `backend` folder)
3. Your Luxand API key is already there! ✅
4. Save the file

### Step 4: Start the Backend Server

1. In PowerShell/Terminal, make sure you're in the `backend` folder:
   ```bash
   cd c:\marketsafe\backend
   ```

2. Start the server:
   ```bash
   npm start
   ```

3. You should see:
   ```
   🚀 Server running on port 4000
   🚀 Health check: http://localhost:4000/api/health
   ```

4. **Keep this window open!** The server needs to keep running.

### Step 5: Test the Backend

1. Open a web browser
2. Go to: `http://localhost:4000/api/health`
3. You should see: `{"ok":true,"time":"...","service":"Face Auth Backend"}`

If you see this, your backend is working! ✅

### Step 6: Connect Flutter App

Now you need to tell your Flutter app where the backend is.

**For Local Testing (Backend on your computer):**

1. Find your computer's IP address:
   - **Windows:** Open PowerShell, type: `ipconfig`
   - Look for "IPv4 Address" (something like `192.168.1.100`)
   
2. Run Flutter with your IP:
   ```bash
   flutter run --dart-define=FACE_AUTH_BACKEND_URL=http://YOUR_IP:4000
   ```
   
   Example:
   ```bash
   flutter run --dart-define=FACE_AUTH_BACKEND_URL=http://192.168.1.100:4000
   ```

**For Production (Deploy to Cloud):**

See `backend/README.md` for deployment options (Heroku, Railway, etc.)

## 🎉 That's It!

Once the backend is running and Flutter is connected, your face authentication will work!

## 🆘 Need Help?

**Backend won't start?**
- Make sure Node.js is installed: `node --version`
- Make sure you ran `npm install` in the `backend` folder
- Check if port 4000 is already in use (try changing PORT in `.env`)

**Flutter can't connect?**
- Make sure backend is running (Step 4)
- Check the URL is correct (use your IP, not `localhost`)
- Make sure both devices are on the same network (for local testing)

**Still stuck?**
- Check `backend/README.md` for more details
- Make sure `.env` file exists and has `LUXAND_API_KEY`

## 📁 What I Created For You

- ✅ `backend/app.js` - Main server file
- ✅ `backend/luxandService.js` - Luxand API helper
- ✅ `backend/package.json` - Dependencies
- ✅ `backend/.env.example` - Configuration template
- ✅ `backend/README.md` - Detailed documentation

Everything is ready! Just follow the steps above. 🚀



