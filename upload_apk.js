const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'marketsafe-e57cf.firebasestorage.app'
});

const bucket = admin.storage().bucket();

async function uploadAPK() {
  try {
    const apkPath = path.join(__dirname, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
    
    if (!fs.existsSync(apkPath)) {
      console.error('❌ APK file not found at:', apkPath);
      process.exit(1);
    }

    console.log('📦 Uploading APK to Firebase Storage...');
    console.log('📁 File:', apkPath);

    const destination = 'app/marketsafe.apk';
    await bucket.upload(apkPath, {
      destination: destination,
      metadata: {
        contentType: 'application/vnd.android.package-archive',
        cacheControl: 'public, max-age=3600',
      },
    });

    console.log('✅ APK uploaded successfully!');
    console.log('🔗 Download URL: https://firebasestorage.googleapis.com/v0/b/marketsafe-e57cf.firebasestorage.app/o/app%2Fmarketsafe.apk?alt=media');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error uploading APK:', error);
    process.exit(1);
  }
}

uploadAPK();


