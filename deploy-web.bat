@echo off
REM Admin Web Panel Deployment Script for Firebase Hosting
REM This script deploys your admin web panel to Firebase Hosting

echo.
echo ========================================
echo MarketSafe Admin Web Panel Deployment
echo ========================================
echo.

REM Check if Firebase CLI is installed
where firebase >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Firebase CLI is not installed!
    echo.
    echo Please install it first:
    echo   npm install -g firebase-tools
    echo.
    pause
    exit /b 1
)

echo [1/4] Checking Firebase login status...
firebase projects:list >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Not logged in. Please login...
    firebase login
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Firebase login failed!
        pause
        exit /b 1
    )
)

echo [2/4] Checking Firebase hosting configuration...
if not exist "firebase.json" (
    echo [ERROR] firebase.json not found!
    pause
    exit /b 1
)

echo [3/4] Building web files...
if not exist "web" (
    echo [ERROR] web folder not found!
    pause
    exit /b 1
)

echo [4/4] Deploying to Firebase Hosting...
firebase deploy --only hosting

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo ✅ Deployment Successful!
    echo ========================================
    echo.
    echo Your admin panel is now live at:
    echo   https://marketsafe-e57cf.web.app/login.html
    echo.
    echo Share this URL with your admins!
    echo.
) else (
    echo.
    echo ========================================
    echo ❌ Deployment Failed!
    echo ========================================
    echo.
    echo Please check the error messages above.
    echo.
)

pause

