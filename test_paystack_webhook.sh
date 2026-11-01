#!/bin/bash

# Test script for Paystack webhook functionality
# This script sends test webhook data to the deployed function

WEBHOOK_URL="https://qdrotavcmmevhgveodcp.supabase.co/functions/v1/paystack-webhook"

# Test data for charge.success event
CHARGE_SUCCESS_DATA='{
  "event": "charge.success",
  "data": {
    "reference": "test_ref_12345",
    "amount": 50000,
    "customer": {
      "email": "test@example.com"
    },
    "metadata": {
      "user_id": "123e4567-e89b-12d3-a456-426614174000",
      "payment_type": "subscription",
      "plan_name": "premium"
    }
  }
}'

echo "Testing Paystack webhook with charge.success event..."
echo "Webhook URL: $WEBHOOK_URL"
echo "Test Data: $CHARGE_SUCCESS_DATA"

# Send test webhook
curl -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "x-paystack-signature: test_signature" \
  -d "$CHARGE_SUCCESS_DATA"

echo -e "\n\nWebhook test completed. Check Supabase function logs for processing details."