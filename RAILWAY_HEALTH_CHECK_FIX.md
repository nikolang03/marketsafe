# Railway Health Check Configuration Fix

## The Problem

Your server starts successfully and receives health check requests, but Railway still sends `SIGTERM` and kills the container. This means Railway's health check is **not configured correctly in the dashboard**.

## The Solution: Configure Health Check in Railway Dashboard

Railway needs the health check to be **explicitly configured in the dashboard**, not just in code.

### Step-by-Step Instructions:

1. **Go to Railway Dashboard**
   - Open: https://railway.app
   - Navigate to your project

2. **Open Your Service**
   - Click on your backend service (the one that's getting SIGTERM)

3. **Go to Settings**
   - Click the **"Settings"** tab
   - Scroll down to find **"Healthcheck"** section

4. **Configure Health Check**
   - **Healthcheck Path**: Set to `/` (or `/api/health`)
   - **Healthcheck Timeout**: Set to `100` (milliseconds) or higher
   - **Healthcheck Interval**: Set to `10` (seconds) or higher
   - **Healthcheck Grace Period**: Set to `30` (seconds) or higher

5. **Save Changes**
   - Click **"Save"** or **"Update"**
   - Railway will automatically redeploy

### Alternative: Disable Health Check (Not Recommended)

If you can't configure the health check:
1. Go to **Settings** → **Healthcheck**
2. **Disable** the health check temporarily
3. This will prevent Railway from killing your container

⚠️ **Warning**: Disabling health checks means Railway won't know if your server is actually running.

---

## What Should Happen After Configuration

After configuring the health check in Railway:

1. ✅ Server starts
2. ✅ Railway checks `/` endpoint
3. ✅ Server responds with `200 OK`
4. ✅ Railway sees the response and **keeps the container running**
5. ✅ No more SIGTERM!

---

## Verify It's Working

After Railway redeploys, check the logs:

**Good signs:**
- `🏥 Health check: GET /`
- `✅ Health check responded: 200 (Xms)`
- No `SIGTERM` after health check

**Bad signs:**
- `SIGTERM received` immediately after health check
- Health check timeout errors
- Connection refused errors

---

## Still Not Working?

If it still fails after configuring the health check:

1. **Check Railway Logs**
   - Look for health check timeout messages
   - Look for connection errors

2. **Try Different Health Check Path**
   - Try `/api/health` instead of `/`
   - Make sure the endpoint responds quickly

3. **Increase Timeout**
   - Increase health check timeout to `500` or `1000` ms
   - Some servers need more time to respond

4. **Check Port Configuration**
   - Make sure Railway's `PORT` environment variable is set
   - Your server should listen on `process.env.PORT`

---

## Quick Checklist

- [ ] Health check path configured in Railway dashboard
- [ ] Health check timeout set (100ms or higher)
- [ ] Server responds to `/` with 200 OK
- [ ] Server listens on `0.0.0.0` (all interfaces)
- [ ] Server uses `process.env.PORT` for port
- [ ] No errors in Railway logs

---

Let me know what you see after configuring the health check in Railway's dashboard!

