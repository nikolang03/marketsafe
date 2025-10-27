# PowerShell script to download working TFLite models
Write-Host "Downloading TFLite face recognition models..."

# Create models directory
if (!(Test-Path "assets\models")) {
    New-Item -ItemType Directory -Path "assets\models" -Force
}

# List of TFLite models to try
$models = @(
    @{
        Name = "MobileNetV1"
        Url = "https://storage.googleapis.com/download.tensorflow.org/models/tflite/mobilenet_v1_1.0_224.tflite"
        File = "mobilenet_v1.tflite"
    },
    @{
        Name = "Face Detector"
        Url = "https://storage.googleapis.com/mediapipe-models/face_detector/face_detector/float16/1/face_detector.tflite"
        File = "face_detector.tflite"
    }
)

$successCount = 0

foreach ($model in $models) {
    Write-Host "Downloading $($model.Name)..."
    try {
        $response = Invoke-WebRequest -Uri $model.Url -OutFile "assets\models\$($model.File)" -TimeoutSec 60 -ErrorAction Stop
        $fileSize = (Get-Item "assets\models\$($model.File)").Length
        $sizeMB = [math]::Round($fileSize / 1MB, 2)
        
        if ($fileSize -gt 100000) {
            Write-Host "Downloaded $($model.Name): $sizeMB MB"
            $successCount++
        } else {
            Write-Host "$($model.Name) too small - likely corrupted"
        }
    } catch {
        Write-Host "Failed to download $($model.Name)"
    }
}

Write-Host "Downloaded $successCount models successfully"

# Check final results
Write-Host "Final model files:"
Get-ChildItem "assets\models" | ForEach-Object {
    $sizeKB = [math]::Round($_.Length / 1KB, 2)
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    if ($_.Length -gt 1000000) {
        Write-Host "  $($_.Name): $sizeMB MB (Valid size)"
    } elseif ($_.Length -gt 100000) {
        Write-Host "  $($_.Name): $sizeKB KB (Small but might work)"
    } else {
        Write-Host "  $($_.Name): $sizeKB KB (Too small - corrupted)"
    }
}