# Simple Supabase Webhook Capture Test
# This script sends a test webhook and provides instructions for verification

$WEBHOOK_URL = "https://qdrotavcmmevhgveodcp.supabase.co/functions/v1/paystack-webhook"
$SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkcm90YXZjbW1ldmhndmVvZGNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc1MjAxMzUsImV4cCI6MjA3MzA5NjEzNX0.dbEFbk8StiMbldSjvlMrFs8X3mCpNpGG3wdgxXg8mqo"

# Generate unique test reference
$TEST_REFERENCE = "test_capture_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Test data for charge.success event
$CHARGE_SUCCESS_DATA = @"
{
  "event": "charge.success",
  "data": {
    "reference": "$TEST_REFERENCE",
    "amount": 50000,
    "customer": {
      "email": "test_capture@example.com"
    },
    "metadata": {
      "user_id": "test_capture_user",
      "payment_type": "subscription",
      "plan_name": "premium"
    }
  }
}
"@

Write-Host "=== SUPABASE WEBHOOK CAPTURE TEST ===" -ForegroundColor Cyan
Write-Host "Test Reference: $TEST_REFERENCE" -ForegroundColor Yellow
Write-Host ""

# Send test webhook
Write-Host "Sending test webhook..." -ForegroundColor Green
try {
    $response = Invoke-RestMethod -Uri $WEBHOOK_URL -Method POST -Headers @{
        "Content-Type"         = "application/json"
        "x-paystack-signature" = "test_signature"
        "Authorization"        = "Bearer $SUPABASE_ANON_KEY"
    } -Body $CHARGE_SUCCESS_DATA

    Write-Host "✓ Webhook sent successfully!" -ForegroundColor Green
    Write-Host "Response: $($response | ConvertTo-Json)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Webhook failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== VERIFICATION STEPS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. CHECK FUNCTION LOGS:" -ForegroundColor Yellow
Write-Host "   Go to: https://supabase.com/dashboard/project/qdrotavcmmevhgveodcp/functions" -ForegroundColor White
Write-Host "   Click on 'paystack-webhook' function" -ForegroundColor White
Write-Host "   Look for these log entries:" -ForegroundColor White
Write-Host "   - 'Paystack webhook received: charge.success'" -ForegroundColor Gray
Write-Host "   - 'Processing successful charge: $TEST_REFERENCE'" -ForegroundColor Gray
Write-Host ""
Write-Host "2. CHECK DATABASE RECORDS:" -ForegroundColor Yellow
Write-Host "   Go to: https://supabase.com/dashboard/project/qdrotavcmmevhgveodcp/editor" -ForegroundColor White
Write-Host "   Run these SQL queries:" -ForegroundColor White
Write-Host ""
Write-Host "   Check payments table:" -ForegroundColor Cyan
Write-Host "   SELECT * FROM payments WHERE reference = '$TEST_REFERENCE';" -ForegroundColor Gray
Write-Host ""
Write-Host "   Check user membership:" -ForegroundColor Cyan
Write-Host "   SELECT id, membership_role FROM profiles WHERE id = 'test_capture_user';" -ForegroundColor Gray
Write-Host ""
Write-Host "   Check QR codes:" -ForegroundColor Cyan
Write-Host "   SELECT * FROM user_qr_codes WHERE user_id = 'test_capture_user';" -ForegroundColor Gray
Write-Host ""
Write-Host "3. EXPECTED RESULTS:" -ForegroundColor Yellow
Write-Host "   ✓ Function logs should show webhook processing" -ForegroundColor Green
Write-Host "   ✓ Payments table should have 1 new record" -ForegroundColor Green
Write-Host "   ✓ User membership should be updated to 'premium'" -ForegroundColor Green
Write-Host "   ✓ QR code should be activated for the user" -ForegroundColor Green
Write-Host ""
Write-Host "=== TEST COMPLETED ===" -ForegroundColor Cyan
Write-Host "Test Reference: $TEST_REFERENCE" -ForegroundColor Yellow