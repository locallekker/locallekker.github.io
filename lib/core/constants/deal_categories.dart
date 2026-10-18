/// Canonical deal category list shared by member filters and partner deal forms.
const String kFreshLocalCategory = 'Fresh & Local';

/// Locally produced wines and alcohol. Age restricted (18+).
const String kLocalSipsCategory = 'Local Sips';

/// Food and beverage trusted partners.
const String kLocalEatsCategory = 'Local Eats';
const String kFoodBusinessCategory = 'Food & Beverage';
const String kRestaurantBusinessCategory = 'Restaurant';

/// Business categories (businesses.category) that belong to Local Eats.
/// These partners may only create the restaurant deal types.
const List<String> kLocalEatsBusinessCategories = [
  kFoodBusinessCategory,
  kRestaurantBusinessCategory,
];

/// Local sports, fitness and active-lifestyle partners (clubs, coaches, gyms).
const String kLocallyActiveCategory = 'Locally Active';

const List<String> kDealCategories = [
  'Food and Drink',
  'Entertainment',
  'Grocery and necessities',
  'Retail',
  'Beauty',
  'Home',
  'Health and Fitness',
  kFreshLocalCategory,
  kLocalSipsCategory,
  kLocalEatsCategory,
  kLocallyActiveCategory,
  'Other',
];
