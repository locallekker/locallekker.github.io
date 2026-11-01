# Simple Supabase Webhook Capture Test

$WEBHOOK_URL = "https://qdrotavcmmevhgveodcp.supabase.co/functions/v1/paystack-webhook"
$SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkcm90YXZjbW1ldmhndmVvZGNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc1MjAxMzUsImV4cCI6MjA3MzA5NjEzNX0.dbEFbk8StiMbldSjvlMrFs8X3mCpNpGG3wdgxXg8mqo"

# Generate unique test reference (NOT starting with 'test_' to trigger database operations)
$TEST_REFERENCE = "capture_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Use a test user ID that will trigger database operations
$TEST_USER_ID = "123e4567-e89b-12d3-a456-426614174000"

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
      "user_id": "$TEST_USER_ID",
      "payment_type": "subscription",
      "plan_name": "premium"
    }
  }
}
"@

Write-Host "=== SUPABASE WEBHOOK CAPTURE TEST ==="
Write-Host "Test Reference: $TEST_REFERENCE"
Write-Host ""

# Send test webhook
Write-Host "Sending test webhook..."
try {
    $response = Invoke-RestMethod -Uri $WEBHOOK_URL -Method POST -Headers @{
        "Content-Type"         = "application/json"
        "x-paystack-signature" = "test_signature"
        "Authorization"        = "Bearer $SUPABASE_ANON_KEY"
    } -Body $CHARGE_SUCCESS_DATA

    Write-Host "SUCCESS: Webhook sent successfully!"
    Write-Host "Response: $($response | ConvertTo-Json)"
}
catch {
    Write-Host "FAILED: Webhook failed: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "=== VERIFICATION STEPS ==="
Write-Host ""
Write-Host "1. CHECK FUNCTION LOGS:"
Write-Host "   Go to: https://supabase.com/dashboard/project/qdrotavcmmevhgveodcp/functions"
Write-Host "   Click on 'paystack-webhook' function"
Write-Host "   Look for these log entries:"
Write-Host "   - 'Paystack webhook received: charge.success'"
Write-Host "   - 'Processing successful charge: $TEST_REFERENCE'"
Write-Host ""
Write-Host "2. CHECK DATABASE RECORDS:"
Write-Host "   Go to: https://supabase.com/dashboard/project/qdrotavcmmevhgveodcp/editor"
Write-Host "   Run these SQL queries:"
Write-Host ""
Write-Host "   Check payments table:"
Write-Host "   SELECT * FROM payments WHERE reference = '$TEST_REFERENCE';"
Write-Host ""
Write-Host "   Check user membership:"
Write-Host "   SELECT user_id, role FROM memberships WHERE user_id = '$TEST_USER_ID';"
Write-Host ""
Write-Host "   Check QR codes:"
Write-Host "   SELECT * FROM user_qr_codes WHERE user_id = '$TEST_USER_ID';";
Write-Host ""
Write-Host "3. EXPECTED RESULTS:"
Write-Host "   - Function logs should show webhook processing"
Write-Host "   - Payments table should have 1 new record"
Write-Host "   - Memberships table should have role = 'member'"
Write-Host "   - QR code should be activated for the user"
Write-Host ""
Write-Host "=== TEST COMPLETED ==="
Write-Host "Test Reference: $TEST_REFERENCE"