# PowerShell script to download TFLite face recognition models
Write-Host "Downloading TFLite face recognition models..."

# Create models directory if it doesn't exist
if (!(Test-Path "assets\models")) {
    New-Item -ItemType Directory -Path "assets\models" -Force
}

# Download MobileFaceNet model
Write-Host "Downloading MobileFaceNet model..."
try {
    $url = "https://github.com/deepinsight/insightface/releases/download/v0.7/mobilefacenet.tflite"
    Invoke-WebRequest -Uri $url -OutFile "assets\models\mobilefacenet.tflite" -TimeoutSec 30
    Write-Host "✅ MobileFaceNet model downloaded successfully"
} catch {
    Write-Host "❌ Failed to download MobileFaceNet: $($_.Exception.Message)"
}

# Check file sizes
Write-Host "`nChecking downloaded files:"
Get-ChildItem "assets\models" | ForEach-Object {
    $sizeKB = [math]::Round($_.Length / 1KB, 2)
    Write-Host "  $($_.Name): $sizeKB KB"
}

Write-Host "`nNote: Valid TFLite models should be several MB in size (not KB)"

