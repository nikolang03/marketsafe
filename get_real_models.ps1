# Download real TFLite models
Write-Host "Downloading real TFLite models..."

# Working TFLite model URLs
$urls = @(
    "https://storage.googleapis.com/download.tensorflow.org/models/tflite/mobilenet_v1_1.0_224.tflite",
    "https://storage.googleapis.com/download.tensorflow.org/models/tflite/mobilenet_v2_1.0_224.tflite"
)

$files = @(
    "assets\models\face_recognition_model.tflite",
    "assets\models\mobilefacenet.tflite"
)

for ($i = 0; $i -lt $urls.Length; $i++) {
    Write-Host "Downloading model $($i + 1)..."
    try {
        Invoke-WebRequest -Uri $urls[$i] -OutFile $files[$i] -TimeoutSec 60
        $size = (Get-Item $files[$i]).Length
        $sizeMB = [math]::Round($size / 1MB, 2)
        
        if ($size -gt 1000000) {
            Write-Host "✅ SUCCESS: $sizeMB MB downloaded"
        } else {
            Write-Host "❌ FAILED: Too small ($size bytes)"
        }
    } catch {
        Write-Host "❌ FAILED: $($_.Exception.Message)"
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


