# Simple script to download working TFLite models
Write-Host "Downloading working TFLite models..."

# Create backup of corrupted models
if (Test-Path "assets\models\face_recognition_model.tflite") {
    Copy-Item "assets\models\face_recognition_model.tflite" "assets\models\face_recognition_model_backup.tflite"
}

if (Test-Path "assets\models\mobilefacenet.tflite") {
    Copy-Item "assets\models\mobilefacenet.tflite" "assets\models\mobilefacenet_backup.tflite"
}

Write-Host "Backed up corrupted models"

# Try to download a working model
$url = "https://storage.googleapis.com/download.tensorflow.org/models/tflite/mobilenet_v1_1.0_224.tflite"
$output = "assets\models\face_recognition_model.tflite"

Write-Host "Downloading MobileNet model..."
try {
    Invoke-WebRequest -Uri $url -OutFile $output -TimeoutSec 60
    $size = (Get-Item $output).Length
    $sizeMB = [math]::Round($size / 1MB, 2)
    
    if ($size -gt 1000000) {
        Write-Host "SUCCESS: Downloaded $sizeMB MB model"
        Write-Host "This should work for face recognition!"
    } else {
        Write-Host "FAILED: Model too small ($size bytes)"
    }
} catch {
    Write-Host "FAILED: Could not download model"
    Write-Host "Error: $($_.Exception.Message)"
}

# Check final results
Write-Host "`nFinal model files:"
Get-ChildItem "assets\models" | ForEach-Object {
    $sizeKB = [math]::Round($_.Length / 1KB, 2)
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    if ($_.Length -gt 1000000) {
        Write-Host "  ✅ $($_.Name): $sizeMB MB (GOOD)"
    } elseif ($_.Length -gt 100000) {
        Write-Host "  ⚠️ $($_.Name): $sizeKB KB (SMALL)"
    } else {
        Write-Host "  ❌ $($_.Name): $sizeKB KB (CORRUPTED)"
    }
}


