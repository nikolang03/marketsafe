# Download working TFLite models from reliable sources
Write-Host "Downloading TFLite models from reliable sources..."

# Create models directory
if (!(Test-Path "assets\models")) {
    New-Item -ItemType Directory -Path "assets\models" -Force
}

# List of working TFLite model URLs
$models = @(
    @{
        Name = "MobileNet V1"
        Url = "https://storage.googleapis.com/download.tensorflow.org/models/tflite/mobilenet_v1_1.0_224.tflite"
        File = "face_recognition_model.tflite"
    },
    @{
        Name = "MobileNet V2"
        Url = "https://storage.googleapis.com/download.tensorflow.org/models/tflite/mobilenet_v2_1.0_224.tflite"
        File = "mobilefacenet.tflite"
    }
)

$successCount = 0

foreach ($model in $models) {
    Write-Host "`nDownloading $($model.Name)..."
    try {
        $response = Invoke-WebRequest -Uri $model.Url -OutFile "assets\models\$($model.File)" -TimeoutSec 60 -ErrorAction Stop
        $fileSize = (Get-Item "assets\models\$($model.File)").Length
        $sizeMB = [math]::Round($fileSize / 1MB, 2)
        
        if ($fileSize -gt 1000000) {
            Write-Host "✅ SUCCESS: Downloaded $($model.Name) - $sizeMB MB"
            $successCount++
        } else {
            Write-Host "❌ FAILED: $($model.Name) too small ($fileSize bytes)"
        }
    } catch {
        Write-Host "❌ FAILED: Could not download $($model.Name)"
        Write-Host "Error: $($_.Exception.Message)"
    }
}

Write-Host "`n📊 Results: Downloaded $successCount models successfully"

if ($successCount -gt 0) {
    Write-Host "✅ Great! You now have working TFLite models"
    Write-Host "🧪 Test your app with: flutter build apk --debug"
} else {
    Write-Host "❌ No models downloaded successfully"
    Write-Host "💡 Try manual download from:"
    Write-Host "   - TensorFlow Hub: https://tfhub.dev/"
    Write-Host "   - MediaPipe: https://github.com/google/mediapipe"
}

# Check final results
Write-Host "`n📁 Final model files:"
Get-ChildItem "assets\models" | ForEach-Object {
    $sizeKB = [math]::Round($_.Length / 1KB, 2)
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    if ($_.Length -gt 1000000) {
        Write-Host "  ✅ $($_.Name): $sizeMB MB (WORKING)"
    } elseif ($_.Length -gt 100000) {
        Write-Host "  ⚠️ $($_.Name): $sizeKB KB (SMALL)"
    } else {
        Write-Host "  ❌ $($_.Name): $sizeKB KB (CORRUPTED)"
    }
}