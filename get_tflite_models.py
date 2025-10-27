#!/usr/bin/env python3
"""
Script to download working TFLite face recognition models
"""

import urllib.request
import os
import sys

def download_file(url, filename):
    """Download a file from URL"""
    try:
        print(f"📥 Downloading {filename}...")
        urllib.request.urlretrieve(url, filename)
        
        # Check file size
        size = os.path.getsize(filename)
        size_mb = size / (1024 * 1024)
        
        if size > 100000:  # More than 100KB
            print(f"✅ Downloaded {filename}: {size_mb:.2f} MB")
            return True
        else:
            print(f"❌ {filename} too small ({size} bytes) - likely corrupted")
            return False
            
    except Exception as e:
        print(f"❌ Failed to download {filename}: {e}")
        return False

def main():
    print("🚀 Downloading TFLite face recognition models...")
    
    # Create models directory
    os.makedirs("assets/models", exist_ok=True)
    
    # List of TFLite models to try
    models = [
        {
            "name": "MobileNetV1",
            "url": "https://storage.googleapis.com/download.tensorflow.org/models/tflite/mobilenet_v1_1.0_224.tflite",
            "file": "assets/models/mobilenet_v1.tflite"
        },
        {
            "name": "Face Detection",
            "url": "https://storage.googleapis.com/mediapipe-models/face_detector/face_detector/float16/1/face_detector.tflite",
            "file": "assets/models/face_detector.tflite"
        },
        {
            "name": "Face Landmarks",
            "url": "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.tflite",
            "file": "assets/models/face_landmarker.tflite"
        }
    ]
    
    success_count = 0
    
    for model in models:
        if download_file(model["url"], model["file"]):
            success_count += 1
    
    print(f"\n📊 Downloaded {success_count}/{len(models)} models successfully")
    
    if success_count > 0:
        print("✅ TFLite models are ready to use!")
        print("📁 Check assets/models/ directory for the downloaded models")
    else:
        print("❌ No valid models were downloaded")
        print("💡 You may need to download models manually from:")
        print("   - TensorFlow Hub: https://tfhub.dev/")
        print("   - MediaPipe: https://github.com/google/mediapipe")
        print("   - ONNX Model Zoo: https://github.com/onnx/models")

if __name__ == "__main__":
    main()

