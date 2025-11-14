# Script to delete an orphaned face from Luxand
# Usage: .\delete_orphaned_face.ps1 -Email "email@example.com"

param(
    [Parameter(Mandatory=$true)]
    [string]$Email
)

$backendUrl = "https://marketsafe-production.up.railway.app"

Write-Host "🗑️  Deleting face for: $Email" -ForegroundColor Yellow
Write-Host ""

$body = @{
    email = $Email
} | ConvertTo-Json

try {
    $response = Invoke-WebRequest -Uri "$backendUrl/api/delete-persons-by-email" `
        -Method POST `
        -ContentType "application/json" `
        -Body $body
    
    $result = $response.Content | ConvertFrom-Json
    
    if ($result.ok) {
        Write-Host "✅ Successfully deleted $($result.deletedCount) face(s) for $Email" -ForegroundColor Green
        if ($result.uuids) {
            Write-Host "   Deleted UUIDs:" -ForegroundColor Gray
            $result.uuids | ForEach-Object { Write-Host "   - $_" -ForegroundColor Gray }
        }
    } else {
        Write-Host "❌ Error: $($result.error)" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
}

