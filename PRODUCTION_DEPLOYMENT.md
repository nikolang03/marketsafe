# Production Deployment Guide

## Problem
The current backend URL (`http://192.168.68.186:4000`) only works on your local network. When you release an APK, devices on different networks won't be able to connect.

## Solution: Deploy Backend to Public Server

### ⚠️ Free Options (2024)

**Heroku**: ❌ No longer free (discontinued in 2022) - Paid plans start at ~$5/month

**Free Options Available**:
1. **Railway** - $5 free credit/month (usually enough for small apps)
2. **Render** - Free tier (services sleep after 15 min inactivity, wakes on request)
3. **Fly.io** - Free tier with generous limits
4. **AWS/GCP/Azure** - Free tiers (more complex setup)

### Option 1: Railway (Recommended - Free Credit)

**Cost**: $5 free credit/month (usually enough for small apps)

1. **Sign up**: https://railway.app (use GitHub/Google to sign up)

2. **Create new project**:
   - Click "New Project"
   - Select "Deploy from GitHub repo" or "Empty Project"

3. **Add service**:
   - Click "New" → "GitHub Repo" (or upload `backend/` folder)
   - Select your repo or upload files

4. **Set environment variables**:
   - Go to your service → Variables tab
   - Add:
     ```
     LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1
     SIMILARITY_THRESHOLD=0.85
     LIVENESS_THRESHOLD=0.90
     ALLOWED_ORIGINS=*
     PORT=4000
     ```

5. **Deploy**:
   - Railway auto-detects Node.js and deploys
   - Get your backend URL from the service (e.g., `https://your-app.up.railway.app`)

### Option 2: Render (Free Tier - Sleeps After Inactivity)

**Cost**: Free (but service sleeps after 15 min inactivity, wakes on first request)

1. **Sign up**: https://render.com

2. **Create new Web Service**:
   - Connect GitHub repo or upload `backend/` folder
   - Select "Node" as environment

3. **Set environment variables**:
   - Add all environment variables in dashboard

4. **Deploy**:
   - Render auto-deploys
   - Get URL: `https://your-app.onrender.com`

**Note**: First request after sleep takes ~30 seconds (cold start)

### Option 3: Fly.io (Free Tier)

**Cost**: Free tier with generous limits

1. **Install Fly CLI**: https://fly.io/docs/getting-started/installing-flyctl/

2. **Sign up**: `fly auth signup`

3. **Navigate to backend folder**:
   ```bash
   cd backend
   ```

4. **Launch app**:
   ```bash
   fly launch
   ```

5. **Set secrets**:
   ```bash
   fly secrets set LUXAND_API_KEY=f14339daa2d74d26a7ed103f5d84a0f1
   fly secrets set SIMILARITY_THRESHOLD=0.85
   fly secrets set LIVENESS_THRESHOLD=0.90
   fly secrets set ALLOWED_ORIGINS=*
   ```

6. **Deploy**:
   ```bash
   fly deploy
   ```

7. **Get URL**: `https://your-app.fly.dev`

### Option 4: Heroku (Paid - $5/month)

**Note**: Heroku no longer offers free tier. Paid plans start at ~$5/month.

If you want to use Heroku:
1. Sign up at https://heroku.com
2. Install Heroku CLI
3. Follow similar steps as Railway/Render
4. Set environment variables via `heroku config:set`
5. Deploy via `git push heroku main`

### Option 5: AWS/GCP/Azure (Free Tier - More Complex)

These have free tiers but require more setup:
- **AWS**: EC2 free tier (12 months), then pay-as-you-go
- **GCP**: $300 free credit (90 days)
- **Azure**: $200 free credit (30 days)

**Recommendation**: Use Railway or Render for simplicity

## Step 2: Build APK with Public Backend URL

### For Release APK:

```bash
flutter build apk --release --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend-url.com
```

**Example (if using Heroku):**
```bash
flutter build apk --release --dart-define=FACE_AUTH_BACKEND_URL=https://your-app-name.herokuapp.com
```

### For App Bundle (Google Play Store):

```bash
flutter build appbundle --release --dart-define=FACE_AUTH_BACKEND_URL=https://your-backend-url.com
```

## Step 3: Update Launch Configuration (Optional)

Update `.vscode/launch.json` for development:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "MarketSafe (Development)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=FACE_AUTH_BACKEND_URL=http://192.168.68.186:4000"
      ]
    },
    {
      "name": "MarketSafe (Production)",
      "request": "launch",
      "type": "dart",
      "args": [
        "--dart-define=FACE_AUTH_BACKEND_URL=https://your-backend-url.com"
      ]
    }
  ]
}
```

## Important Notes

1. **Backend must be running 24/7** - Users need to access it anytime
2. **HTTPS required** - Use `https://` not `http://` for production
3. **CORS configured** - Backend already allows all origins (`ALLOWED_ORIGINS=*`)
4. **Environment variables** - Keep your Luxand API key secure on the server
5. **Testing** - Test the public backend URL before releasing APK

## Quick Test

After deploying, test your backend:
```bash
curl https://your-backend-url.com/api/health
```

Should return: `{"ok":true,...}`

## Troubleshooting

- **Connection timeout**: Check if backend is deployed and running
- **CORS errors**: Verify `ALLOWED_ORIGINS=*` is set
- **401 errors**: Check if `LUXAND_API_KEY` is set correctly
- **Port issues**: Heroku/Railway/Render handle ports automatically

