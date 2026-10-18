# New Deal Types Implementation - Integration Guide

## Restaurant Buy One Get One Free pricing

The shared [restaurant deal form](lib/features/business/restaurant_deal_dialog.dart)
offers TP and admin users two mutually exclusive checkboxes for the `restaurant_bogo`
deal type:

- **Fixed price** (the default, including existing deals without `pricing_mode`):
  enter one price when creating the deal. Existing redemption/payment behavior stays unchanged.
- **Price entered at checkout** (`custom_data.pricing_mode = checkout`):
  no creation-time price is required. The TP scans the member QR, selects the deal,
  and enters the normal price of every qualifying item, including the free items.
  The app and database independently calculate the eligible free quantity from
  `buy_qty`, `free_qty`, and `max_free`, then discount that many of the cheapest
  items across the qualifying items on the bill. Incomplete groups do not earn
  another free item. Item totals cannot exceed the original bill.

For example, R95 + R75 cocktails give a R75 discount; with four cocktails priced
R120, R100, R80 and R60, buy-one-get-one gives R140 off (R60 + R80).
Checkout-priced deals are redeemed and paid in store through a verified partner
QR session; members cannot enter the prices or initiate Paystack payment for them.
The prices are stored in `bill_data.restaurant.inputs.item_prices` for reporting.

Apply only [migration 20261018170000](supabase/migrations/20261018170000_add_bogo_checkout_pricing.sql)
before testing checkout-priced deals. Do not run a blanket migration push: the
held-back in-app payment enforcement migration must not be applied early.
The migration does not convert existing deals or alter Paystack logic.
Regression checks: run `flutter test test/restaurant_deal_test.dart
test/restaurant_deal_dialog_test.dart test/partner_qr_redemption_test.dart`.
The [SQL regression tests](supabase/tests/bogo_checkout_pricing.sql) exercise the
server calculator, creation-time validation, and calculator permissions using
temporary test objects and roll back all changes.

## Completed Tasks ✓
1. **Database Layer** - `add_new_deal_types.sql`
   - Added `deal_type`, `custom_data`, `requires_manual_price` to `trusted_partner_discounts`
   - Added `member_entered_price`, `applied_discount_amount`, `deal_type`, `deal_snapshot` to `deal_authorizations`

2. **Model Layer** 
   - Updated `Discount.dart` with new fields and type-aware getters
   - Updated `DealAuthorization.dart` with manual pricing snapshot fields
   - Added `isBuyGet` and `isPercentItem` convenience getters

3. **Service Layer**
   - Updated `discount_service.dart` to persist new metadata fields
   - Updated `deal_authorization_service.dart` to capture snapshots
   - Updated `deal_authorization_request_page.dart` with manual price input and calculation

4. **Member UI**
   - Deal selection/browse shows new deal type badges (purple for "Buy/Get", indigo for "% Off Item")
   - Deal authorization request page now:
     - Prompts for item price on "% Off Item" deals
     - Calculates discount and total price dynamically
     - Sends manual price snapshot to backend

## Remaining Tasks

### 1. Complete Add Deal Dialog (`discount_management_page.dart` - `_AddDiscountDialogState`)

Add UI sections for new deal types after the "Exclusions Section" (around line 910):

```dart
// BUY-GET DEAL FIELDS
if (_selectedType == DiscountType.buyGet) ...[
  // Fields: Buy Item Name, Buy Price, Free Item Name, Free Item Price, Total Price
  // See implementation guide below
],

// PERCENT-ITEM DEAL FIELDS  
if (_selectedType == DiscountType.percentItem) ...[
  // Field: Discount Percentage
  // Note: Member enters price at request time
],
```

### 2. Update Form Submission (`_submit` method in `_AddDiscountDialogState`)

Map new deal types to database fields:

```dart
} else if (_selectedType == DiscountType.buyGet) {
  final buyPrice = double.tryParse(_buyItemPriceController.text) ?? 0.0;
  final freeValue = double.tryParse(_freeItemPriceController.text) ?? 0.0;
  final totalPrice = double.tryParse(_totalBuyGetPriceController.text) ?? 0.0;
  
  customData = {
    'buy_item_name': _buyItemNameController.text.trim(),
    'buy_item_price': buyPrice,
    'free_item_name': _freeItemNameController.text.trim(),
    'free_item_value': freeValue,
    'total_price': totalPrice,
  };
  
  // Set itemPrice to total for display purposes
  itemPrice = totalPrice;
  dealType = 'buy_get';
  
} else if (_selectedType == DiscountType.percentItem) {
  percentage = double.tryParse(_percentDiscountController.text) ?? 0.0;
  requiresManualPrice = true;
  dealType = 'percent_item';
  itemPrice = 0.0; // Will be set by member
}
```

### 3. Update Edit Dialog (`_EditDiscountDialogState`)

Mirror new deal type handling in initState and build methods.

### 4. Update createDiscount calls in UI

When calling `DiscountService.createDiscount()`, pass new parameters:

```dart
await _discountService.createDiscount(
  // ... existing params ...
  dealType: dealTypeEnum.toDbValue(), // 'standard', 'buy_get', 'percent_item', etc.
  customData: customData,
  requiresManualPrice: requiresManualPrice,
);
```

### 5. Update Deal Type Display Labels

Deal selection page now uses:
- `'buy_get'` → "Buy/Get"
- `'percent_item'` → "% Off Item"
- `'standard'` → "Standard Deal"
- `'bill_discount'` → "Bill Discount"
- `'once_off'` → "Once-Off Deal"
- `'weight'` → "Weight-Based"

## Key Implementation Details

### Buy-Get Deal (`buy_get`)
- Member selects item: "Buy Coffee (R75) Get Pastry Free (normally R45) for R99"
- Admin sets: buy item name, buy price, free item name, free item value, total combo price
- Member submits with quantity (qty × combo)
- Custom data structure:
  ```json
  {
    "buy_item_name": "Coffee",
    "buy_item_price": 75.00,
    "free_item_name": "Pastry",
    "free_item_value": 45.00,
    "total_price": 99.00
  }
  ```

### Percent-Item Deal (`percent_item`)
- Admin sets: item category, discount percentage
- Member enters: item price at request time (e.g., "This sweater costs R299, apply 20% off")
- Savings = member_price × (percentage / 100)
- Amount = member_price - savings
- Custom data: empty (pricing data comes from member at request time)
- `requires_manual_price = true`

### Deal Authorization Snapshot
When member requests a deal, we capture:
- `member_entered_price`: Only for `percent_item` deals
- `applied_discount_amount`: Calculated savings snapshot
- `deal_type`: Type at request time
- `deal_snapshot`: Full deal data for audit trail

## Testing Checklist

- [ ] Admin can create "Buy this get that" deal
- [ ] Admin can create "% off item" deal
- [ ] Member sees new deal type badges in browse
- [ ] Member can request "Buy/Get" deal with quantity
- [ ] Member prompted to enter price for "% off item" deals
- [ ] Calculations correct for both types
- [ ] Deal snapshot saved to DB
- [ ] Edit dialog loads and saves new types
- [ ] Deal type filter works with new types

## Database Schema Verification

```sql
-- Check new columns exist
SELECT column_name FROM information_schema.columns 
WHERE table_name = 'trusted_partner_discounts'
  AND column_name IN ('deal_type', 'custom_data', 'requires_manual_price');

SELECT column_name FROM information_schema.columns 
WHERE table_name = 'deal_authorizations'
  AND column_name IN ('member_entered_price', 'applied_discount_amount', 
                      'deal_type', 'deal_snapshot');
```
