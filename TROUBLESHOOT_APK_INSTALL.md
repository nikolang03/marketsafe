# Troubleshooting "Package Appears to be Invalid" Error

## Common Causes & Solutions

### 1. **Uninstall Existing App First** ⚠️ MOST COMMON
If you have an older version installed with a different signature:
- Go to Settings → Apps → Find "marketsafe" → Uninstall
- Then try installing the new APK

### 2. **Check Device Compatibility**
- **Minimum Android Version:** Android 10 (API 29) or higher
- **Architecture:** 64-bit ARM (arm64-v8a) only
- Check your device: Settings → About Phone → Android Version

### 3. **Enable Unknown Sources**
- Settings → Security → Enable "Install from Unknown Sources"
- Or Settings → Apps → Special Access → Install Unknown Apps → Select your file manager → Enable

### 4. **Check APK File Integrity**
- Make sure the APK file wasn't corrupted during transfer
- Try downloading/copying again
- File size should be ~57.5 MB

### 5. **Clear Device Storage**
- Ensure you have at least 100 MB free storage
- Settings → Storage → Check available space

### 6. **Try Different Installation Method**
- Transfer APK via USB, email, or cloud storage
- Use ADB: `adb install marketsafe.apk`
- Try installing from different file manager app

### 7. **Reboot Device**
- Sometimes a simple reboot fixes installation issues

## Quick Fix Commands

### Check APK Signature:
```bash
apksigner verify --print-certs marketsafe.apk
```

### Install via ADB (if device connected):
```bash
adb install marketsafe.apk
```

### Force Install (if app exists):
```bash
adb install -r marketsafe.apk
```

## If Still Not Working

The APK might need to be rebuilt with different settings. Contact support with:
- Device model and Android version
- Exact error message
- Whether you had a previous version installed


