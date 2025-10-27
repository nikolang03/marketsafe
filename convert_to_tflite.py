#!/usr/bin/env python3
"""
Convert FaceNet SavedModel to TFLite format
"""

import tensorflow as tf
import os
import numpy as np

def convert_facenet_to_tflite():
    """Convert FaceNet SavedModel to TFLite"""
    print("Converting FaceNet SavedModel to TFLite...")
    
    try:
        # Find the saved model directory
        model_dir = None
        for item in os.listdir("assets/models"):
            if os.path.isdir(os.path.join("assets/models", item)) and "facenet" in item.lower():
                model_dir = os.path.join("assets/models", item)
                break
        
        if not model_dir:
            print("❌ Could not find FaceNet model directory")
            return False
        
        print(f"📁 Found model directory: {model_dir}")
        
        # Load the SavedModel
        print("📥 Loading SavedModel...")
        model = tf.saved_model.load(model_dir)
        
        # Get the inference function
        infer = model.signatures['serving_default']
        
        # Create a concrete function for conversion
        print("🔄 Creating concrete function...")
        concrete_func = infer.get_concrete_function(
            tf.TensorSpec(shape=[None, 160, 160, 3], dtype=tf.float32, name='input')
        )
        
        # Convert to TFLite
        print("🔄 Converting to TFLite...")
        converter = tf.lite.TFLiteConverter.from_concrete_functions([concrete_func])
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]
        
        tflite_model = converter.convert()
        
        # Save the TFLite model
        output_path = "assets/models/face_recognition_model.tflite"
        with open(output_path, 'wb') as f:
            f.write(tflite_model)
        
        print(f"✅ TFLite model saved to: {output_path}")
        print(f"📊 Model size: {len(tflite_model) / 1024:.2f} KB")
        
        # Also save as mobilefacenet.tflite
        mobilefacenet_path = "assets/models/mobilefacenet.tflite"
        with open(mobilefacenet_path, 'wb') as f:
            f.write(tflite_model)
        
        print(f"✅ MobileFaceNet model saved to: {mobilefacenet_path}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error converting model: {e}")
        return False

if __name__ == "__main__":
    success = convert_facenet_to_tflite()
    if success:
        print("\n🎉 FaceNet model converted to TFLite successfully!")
        print("📁 Check assets/models/ for the new .tflite files")
    else:
        print("\n❌ Failed to convert model")


