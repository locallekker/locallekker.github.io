# Test script for Paystack webhook functionality
# This script sends test webhook data to the deployed function

$WEBHOOK_URL = "https://qdrotavcmmevhgveodcp.supabase.co/functions/v1/paystack-webhook"
$SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkcm90YXZjbW1ldmhndmVvZGNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc1MjAxMzUsImV4cCI6MjA3MzA5NjEzNX0.dbEFbk8StiMbldSjvlMrFs8X3mCpNpGG3wdgxXg8mqo"

# Test data for charge.success event
$CHARGE_SUCCESS_DATA = '{
  "event": "charge.success",
  "data": {
    "reference": "test_ref_12345",
    "amount": 50000,
    "customer": {
      "email": "test@example.com"
    },
    "metadata": {
      "user_id": "test-user-id",
      "payment_type": "subscription",
      "plan_name": "premium"
    }
  }
}'

Write-Host "Testing Paystack webhook with charge.success event..."
Write-Host "Webhook URL: $WEBHOOK_URL"
Write-Host "Test Data: $CHARGE_SUCCESS_DATA"

# Send test webhook
try {
    $response = Invoke-RestMethod -Uri $WEBHOOK_URL -Method POST -Headers @{
        "Content-Type"         = "application/json"
        "x-paystack-signature" = "test_signature"
        "Authorization"        = "Bearer $SUPABASE_ANON_KEY"
    } -Body $CHARGE_SUCCESS_DATA

    Write-Host "Response: $response"
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Status Code: $($_.Exception.Response.StatusCode)"
}

Write-Host "`n`nWebhook test completed. Check Supabase function logs for processing details."