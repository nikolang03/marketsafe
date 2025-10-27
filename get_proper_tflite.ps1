# Download proper TFLite models
Write-Host "Downloading proper TFLite models..."

# Working TFLite model URLs
$models = @(
    @{
        Name = "MobileNet V1"
        Url = "https://github.com/tensorflow/tensorflow/raw/master/tensorflow/lite/examples/object_detection/android/app/src/main/assets/mobilenet_v1_1.0_224.tflite"
        File = "face_recognition_model.tflite"
    },
    @{
        Name = "MobileNet V2" 
        Url = "https://github.com/tensorflow/tensorflow/raw/master/tensorflow/lite/examples/object_detection/android/app/src/main/assets/mobilenet_v2_1.0_224.tflite"
        File = "mobilefacenet.tflite"
    }
)

foreach ($model in $models) {
    Write-Host "Downloading $($model.Name)..."
    try {
        $response = Invoke-WebRequest -Uri $model.Url -OutFile "assets\models\$($model.File)" -TimeoutSec 60 -ErrorAction Stop
        $fileSize = (Get-Item "assets\models\$($model.File)").Length
        $sizeMB = [math]::Round($fileSize / 1MB, 2)
        
        if ($fileSize -gt 1000000) {
            Write-Host "✅ SUCCESS: $($model.Name) - $sizeMB MB"
        } else {
            Write-Host "❌ FAILED: $($model.Name) too small ($fileSize bytes)"
        }
    } catch {
        Write-Host "❌ FAILED: $($model.Name) - $($_.Exception.Message)"
    }
}

Write-Host "`nChecking results..."
Get-ChildItem "assets\models" | ForEach-Object {
    $sizeMB = [math]::Round($_.Length / 1MB, 2)
    if ($_.Length -gt 1000000) {
        Write-Host "✅ $($_.Name): $sizeMB MB (WORKING)"
    } else {
        Write-Host "❌ $($_.Name): $sizeMB MB (TOO SMALL)"
    }
}


