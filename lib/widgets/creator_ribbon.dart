import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Global bottom ribbon with creator logo and app version.
class CreatorRibbon extends StatefulWidget {
  const CreatorRibbon({super.key, this.height = 28});

  final double height;

  @override
  State<CreatorRibbon> createState() => _CreatorRibbonState();
}

class _CreatorRibbonState extends State<CreatorRibbon> {
  static String? _cachedVersion; // cache across rebuilds

  @override
  void initState() {
    super.initState();
    _initVersion();
  }

  Future<void> _initVersion() async {
    if (_cachedVersion != null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _cachedVersion = 'v${info.version}';
      });
    } catch (_) {
      setState(() {
        _cachedVersion = 'v1.0.0';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: IgnorePointer(
        child: Container(
          height: widget.height,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.92),
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Creator logo
                Image.asset(
                  'assets/creator_logo.png',
                  height: 16,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 10),
                Text(
                  _cachedVersion ?? '...',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
