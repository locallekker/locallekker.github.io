import 'package:flutter/material.dart';

/// A small watermark widget displaying the creator's logo at the bottom of screens.
///
/// Usage:
/// ```dart
/// Scaffold(
///   body: Column(
///     children: [
///       Expanded(child: YourContent()),
///       CreatorWatermark(), // Add at bottom
///     ],
///   ),
/// )
/// ```
class CreatorWatermark extends StatelessWidget {
  final double height;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final bool showText;

  const CreatorWatermark({
    super.key,
    this.height = 30.0, // Small height for watermark
    this.opacity = 0.5, // Semi-transparent
    this.padding = const EdgeInsets.symmetric(vertical: 8.0),
    this.showText = false, // Optional "Powered by" text
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showText) ...[
                Text(
                  'Powered by ',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              // Logo image
              Image.asset(
                'assets/creator_logo.png',
                height: height,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback if image not found
                  return Container(
                    height: height,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'Logo',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alternative compact version - just the logo, no padding
class CompactWatermark extends StatelessWidget {
  final double size;
  final double opacity;

  const CompactWatermark({super.key, this.size = 24.0, this.opacity = 0.4});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Image.asset(
        'assets/creator_logo.png',
        height: size,
        width: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(Icons.copyright, size: size, color: Colors.grey.shade400);
        },
      ),
    );
  }
}
