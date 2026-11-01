# Creator Logo - Watermark Setup

## 📁 Where to Place Your Logo

**Location:** `c:\Users\clyde\local_lekker\assets\images\creator_logo.png`

### Logo Requirements:
- **Format:** PNG (with transparency recommended)
- **Recommended Size:** 120x120 pixels (or similar small size)
- **Aspect Ratio:** Square or horizontal logo works best
- **Background:** Transparent PNG preferred for clean watermark effect
- **File Name:** Must be named `creator_logo.png` (exact name)

## 📝 How to Add the Logo

1. **Prepare your logo image:**
   - Make sure it's a PNG file
   - Resize to approximately 120x120 pixels (small size)
   - If possible, use transparent background

2. **Copy to the assets folder:**
   ```
   Copy your logo file to:
   c:\Users\clyde\local_lekker\assets\images\creator_logo.png
   ```

3. **Verify the file:**
   - Check that the file is named exactly `creator_logo.png`
   - Check that it's in the `assets/images/` folder

## 🎨 How to Use the Watermark

### Option 1: Standard Watermark (with optional "Powered by" text)
```dart
import 'package:local_lekker/widgets/creator_watermark.dart';

Scaffold(
  body: Column(
    children: [
      Expanded(
        child: YourMainContent(),
      ),
      CreatorWatermark(), // Adds small logo at bottom
    ],
  ),
)
```

### Option 2: With "Powered by" text
```dart
CreatorWatermark(
  showText: true, // Shows "Powered by [logo]"
  height: 35.0,   // Slightly larger
  opacity: 0.6,   // Slightly more visible
)
```

### Option 3: Compact Version (just icon, minimal space)
```dart
import 'package:local_lekker/widgets/creator_watermark.dart';

// Somewhere at the bottom of your widget tree
CompactWatermark(
  size: 24.0,     // Very small
  opacity: 0.4,   // More transparent
)
```

### Option 4: Inside a SafeArea (recommended for most screens)
```dart
Scaffold(
  body: SafeArea(
    child: Column(
      children: [
        Expanded(child: YourContent()),
        CreatorWatermark(), // Safe from bottom notches/bars
      ],
    ),
  ),
)
```

## 🔧 Customization Options

### CreatorWatermark Parameters:
- `height` (double): Height of the logo in pixels (default: 30.0)
- `opacity` (double): Transparency 0.0-1.0 (default: 0.5)
- `padding` (EdgeInsetsGeometry): Space around watermark (default: 8.0 vertical)
- `showText` (bool): Show "Powered by" text (default: false)

### CompactWatermark Parameters:
- `size` (double): Size of the logo (default: 24.0)
- `opacity` (double): Transparency 0.0-1.0 (default: 0.4)

## 📱 Example Implementations

### Example 1: Add to Welcome Page
```dart
// lib/features/auth/welcome_page.dart
Scaffold(
  body: Column(
    children: [
      Expanded(
        child: Center(
          child: // Your welcome content
        ),
      ),
      CreatorWatermark(
        showText: true,
        height: 30.0,
        opacity: 0.5,
      ),
    ],
  ),
)
```

### Example 2: Add to Home Pages
```dart
// lib/features/auth/members_home_page.dart
Scaffold(
  body: SafeArea(
    child: Column(
      children: [
        Expanded(
          child: // Your home page content
        ),
        CompactWatermark(size: 24.0), // Minimal watermark
      ],
    ),
  ),
)
```

### Example 3: Add to Bottom Navigation Screens
```dart
Scaffold(
  body: Column(
    children: [
      Expanded(child: _pages[_currentIndex]),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CompactWatermark(size: 20.0, opacity: 0.3),
        ],
      ),
    ],
  ),
  bottomNavigationBar: BottomNavigationBar(...),
)
```

## 🚀 Apply to All Screens

If you want the watermark on **every screen**, you have two options:

### Option A: Add to individual screens (manual)
Add the watermark widget to each screen's layout as shown above.

### Option B: Create a wrapper widget (automated)
Create a reusable screen wrapper:

```dart
// lib/widgets/screen_with_watermark.dart
import 'package:flutter/material.dart';
import 'creator_watermark.dart';

class ScreenWithWatermark extends StatelessWidget {
  final Widget child;
  final bool showWatermark;

  const ScreenWithWatermark({
    super.key,
    required this.child,
    this.showWatermark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: child),
        if (showWatermark) const CompactWatermark(),
      ],
    );
  }
}
```

Then wrap your screens:
```dart
Scaffold(
  body: ScreenWithWatermark(
    child: YourScreenContent(),
  ),
)
```

## ❓ Troubleshooting

### Logo not showing:
1. Check file path: `assets/images/creator_logo.png`
2. Check file name is exactly `creator_logo.png` (lowercase, underscore)
3. Run `flutter clean` then `flutter pub get`
4. Restart the app

### Logo too large:
- Reduce the `height` or `size` parameter
- Default is 30px, try 20px or 24px

### Logo too visible:
- Reduce the `opacity` parameter
- Default is 0.5, try 0.3 or 0.4

### Logo doesn't fit design:
- Use `CompactWatermark` for minimal footprint
- Adjust `padding` to control spacing
- Set `opacity` lower (e.g., 0.2) for subtle effect

## 📐 Recommended Sizes

| Screen Type | Recommended Widget | Size | Opacity |
|-------------|-------------------|------|---------|
| Welcome/Auth | CreatorWatermark | 30px | 0.5 |
| Home Pages | CompactWatermark | 24px | 0.4 |
| Profile Pages | CreatorWatermark | 28px | 0.5 |
| Settings Pages | CompactWatermark | 20px | 0.3 |
| Forms/Modals | CompactWatermark | 20px | 0.3 |

## 🎯 Next Steps

1. **Place your logo** in `assets/images/creator_logo.png`
2. **Test it** by adding to one screen first
3. **Adjust** the size and opacity to your preference
4. **Roll out** to other screens once satisfied

Need help? The watermark widget has built-in fallback (shows "Logo" text) if the image file is missing.
