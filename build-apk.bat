@echo off
REM Flutter APK Build Script
REM This script builds a release APK for your app

echo.
echo ========================================
echo MarketSafe APK Builder
echo ========================================
echo.

REM Check if Flutter is installed
where flutter >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter is not installed or not in PATH!
    echo.
    echo Please install Flutter first:
    echo   https://flutter.dev/docs/get-started/install
    echo.
    pause
    exit /b 1
)

echo [1/3] Checking Flutter installation...
flutter doctor
if %ERRORLEVEL% NEQ 0 (
    echo [WARNING] Flutter doctor shows issues. Continue anyway? (Y/N)
    set /p continue="> "
    if /i not "%continue%"=="Y" (
        exit /b 1
    )
)

echo.
echo [2/3] Getting Flutter dependencies...
flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to get dependencies!
    pause
    exit /b 1
)

echo.
echo [3/3] Building release APK...
echo.
echo NOTE: Make sure you've updated the backend URL in:
echo   lib/services/production_face_recognition_service.dart
echo.
pause

flutter build apk --release

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo ✅ APK Build Successful!
    echo ========================================
    echo.
    echo Your APK is located at:
    echo   build\app\outputs\flutter-apk\app-release.apk
    echo.
    echo You can now share this APK with users!
    echo.
) else (
    echo.
    echo ========================================
    echo ❌ APK Build Failed!
    echo ========================================
    echo.
    echo Please check the error messages above.
    echo.
)

pause

