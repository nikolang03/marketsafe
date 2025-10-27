# TFLite Face Recognition Models - Download Instructions

## Current Status
- ✅ `face_landmarker.task`: 3.58 MB (Valid MediaPipe model)
- ❌ `face_recognition_model.tflite`: 0.29 KB (Corrupted)
- ❌ `mobilefacenet.tflite`: 0.2 KB (Corrupted)

## Manual Download Options

### Option 1: TensorFlow Hub
1. Go to: https://tfhub.dev/s?q=face%20recognition
2. Download any face recognition model
3. Convert to TFLite format if needed
4. Place in `assets/models/`

### Option 2: MediaPipe Models
1. Go to: https://github.com/google/mediapipe
2. Download face detection/recognition models
3. Place in `assets/models/`

### Option 3: ONNX Model Zoo
1. Go to: https://github.com/onnx/models
2. Download face recognition models
3. Convert to TFLite format
4. Place in `assets/models/`

## Quick Fix
Replace the corrupted files with any working TFLite model:
- `face_recognition_model.tflite` (should be several MB)
- `mobilefacenet.tflite` (should be several MB)

## Testing
After downloading valid models:
1. Run `flutter build apk --debug`
2. Test face recognition
3. Check logs for successful model loading

## Expected Log Output
```
✅ Production face recognition model initialized successfully
📊 Model input shape: [1, 112, 112, 3]
📊 Model output shape: [1, 512]
```

