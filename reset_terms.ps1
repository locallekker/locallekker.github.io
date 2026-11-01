# Reset terms for fuelbean@gmail.com
$email = "fuelbean@gmail.com"
$supabaseUrl = "https://qdrotavcmmevhgveodcp.supabase.co"
$anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkcm90YXZjbW1ldmhndmVvZGNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc1MjAxMzUsImV4cCI6MjA3MzA5NjEzNX0.dbEFbk8StiMbldSjvlMrFs8X3mCpNpGG3wdgxXg8mqo"

$filter = "email=eq.$email"
$url = "$supabaseUrl/rest/v1/profiles?$filter"

$headers = @{
    "Authorization" = "Bearer $anonKey"
    "Content-Type"  = "application/json"
    "apikey"        = $anonKey
}

$body = @{
    partner_terms_accepted    = $false
    partner_terms_accepted_at = $null
} | ConvertTo-Json

Write-Host "============================="
Write-Host "Resetting Terms & Conditions"
Write-Host "============================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Step 1: Resetting partner_terms_accepted to false..."
Write-Host "URL: $url" -ForegroundColor Yellow

try {
    $response = Invoke-WebRequest -Uri $url -Headers $headers -Method PATCH -Body $body -UseBasicParsing
    Write-Host "✅ Update request sent" -ForegroundColor Green
    Write-Host "Response Code: $($response.StatusCode)"
}
catch {
    Write-Host "Error during update: $($_)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Step 2: Verifying reset..."

$selectUrl = "$supabaseUrl/rest/v1/profiles?$filter&select=id,email,role,partner_terms_accepted,partner_terms_accepted_at"

try {
    $response = Invoke-WebRequest -Uri $selectUrl -Headers $headers -Method GET -UseBasicParsing
    $data = $response.Content | ConvertFrom-Json
    
    if ($data.Count -gt 0 -or $data -is [object]) {
        $user = if ($data -is [array]) { $data[0] } else { $data }
        Write-Host "✅ Current Profile State:" -ForegroundColor Green
        Write-Host "   Email: $($user.email)"
        Write-Host "   Role: $($user.role)"
        Write-Host "   partner_terms_accepted: $($user.partner_terms_accepted)"
        Write-Host ""
        
        if ($user.partner_terms_accepted -eq $false) {
            Write-Host "✅ SUCCESS! Terms reset to false" -ForegroundColor Green
        }
        else {
            Write-Host "⚠ WARNING: Terms might not have been reset" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "Error during verification: $($_)" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================="
Write-Host "Now sign in to http://localhost:8080"
Write-Host "You should see the Terms & Conditions page!"
Write-Host "============================" -ForegroundColor Cyan
