import 'package:flutter/material.dart';
import '../core/constants/deal_categories.dart';
import 'category_entry_banner.dart';

/// Prominent entry point to the Fresh & Local produce section.
/// Shared by the member home and the trusted partner's member view.
/// Pulses and shows a badge while [newDealCount] is greater than zero.
class FreshLocalBanner extends StatefulWidget {
  final VoidCallback onTap;
  final int newDealCount;
  final int partnerCount;
  final int dealCount;

  /// Narrow, fixed-height card for the multi-slot category row.
  final bool compact;

  const FreshLocalBanner({
    super.key,
    required this.onTap,
    this.newDealCount = 0,
    this.partnerCount = 0,
    this.dealCount = 0,
    this.compact = false,
  });

  @override
  State<FreshLocalBanner> createState() => _FreshLocalBannerState();
}

class _FreshLocalBannerState extends State<FreshLocalBanner>
    with SingleTickerProviderStateMixin {
  static const Color _limeDark = Color(0xFF4B7F1F);
  static const Color _limeMid = Color(0xFF7CB342);
  static const Color _limeLight = Color(0xFFB4EC51);

  late final AnimationController _pulseController;

  bool get _hasNewDeals => widget.newDealCount > 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (_hasNewDeals) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant FreshLocalBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasNewDeals && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!_hasNewDeals && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return CategoryEntryBanner(
        onTap: widget.onTap,
        title: kFreshLocalCategory,
        subtitle: 'Fresh produce near you',
        icon: Icons.eco,
        gradientColors: const [_limeLight, _limeMid, _limeDark],
        shadowColor: const Color(0xFF2E5511),
        background: const _ProduceStickerBomb(),
        newDealCount: widget.newDealCount,
        partnerCount: widget.partnerCount,
        dealCount: widget.dealCount,
        compact: true,
      );
    }

    // Horizontal inset leaves room for the shadow and for the pulse to grow
    // without overflowing the parent.
    final card = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: _buildCard(),
    );
    if (!_hasNewDeals) return card;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_pulseController.value);
        return Transform.scale(scale: 1 + (0.008 * t), child: child);
      },
      child: card,
    );
  }

  Widget _buildCard() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final t = _hasNewDeals
            ? Curves.easeInOut.transform(_pulseController.value)
            : 0.0;
        // Decoration sits outermost so the shadow follows the rounded corners.
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              // Wide ambient shadow lifts the card off the page.
              BoxShadow(
                color: const Color(
                  0xFF2E5511,
                ).withValues(alpha: 0.28 + (0.16 * t)),
                blurRadius: 30 + (16 * t),
                spreadRadius: -2 + (3 * t),
                offset: const Offset(0, 14),
              ),
              // Tighter key shadow for contact definition.
              BoxShadow(
                color: _limeDark.withValues(alpha: 0.34 + (0.22 * t)),
                blurRadius: 12 + (8 * t),
                spreadRadius: -1,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_limeLight, _limeMid, _limeDark],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            child: Stack(
              children: [
                const Positioned.fill(child: _ProduceStickerBomb()),
                // Softens the stickers behind the text so it stays readable.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          _limeDark.withValues(alpha: 0.58),
                          _limeMid.withValues(alpha: 0.20),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 0.80],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.eco,
                          size: 38,
                          color: _limeDark,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              kFreshLocalCategory,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.2,
                                shadows: [
                                  Shadow(
                                    color: Color(0x662E5511),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildCountsRow(),
                            if (_hasNewDeals) ...[
                              const SizedBox(height: 6),
                              _buildNewDealsBadge(),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountsRow() {
    // Before the counts land, keep the descriptive strapline in their place.
    if (widget.partnerCount == 0) {
      return _subtitleText('Locally sourced fresh produce near you');
    }

    final partners = widget.partnerCount == 1
        ? '1 partner'
        : '${widget.partnerCount} partners';
    final deals = widget.dealCount == 1
        ? '1 deal'
        : '${widget.dealCount} deals';

    return Row(
      children: [
        _countChip(Icons.storefront_rounded, partners),
        const SizedBox(width: 6),
        _countChip(Icons.local_offer_rounded, deals),
      ],
    );
  }

  Widget _countChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Color(0x552E5511),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtitleText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.95),
        shadows: const [
          Shadow(color: Color(0x552E5511), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
    );
  }

  Widget _buildNewDealsBadge() {
    final count = widget.newDealCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E5511).withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFD32F2F),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            count > 1 ? '$count new deals added' : 'New deals added',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _limeDark,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single scattered produce sticker, positioned as a fraction of the card.
class _Sticker {
  final String emoji;
  final double x;
  final double y;
  final double size;
  final double angle;

  const _Sticker(this.emoji, this.x, this.y, this.size, this.angle);
}

/// Scattered fresh-produce "sticker bomb" backdrop for the Fresh & Local card.
class _ProduceStickerBomb extends StatelessWidget {
  const _ProduceStickerBomb();

  static const double _opacity = 0.2;

  // Hand-placed so the pattern reads evenly and never reflows between builds.
  static const List<_Sticker> _stickers = [
    // Band 1
    _Sticker('🥬', -0.03, -0.28, 27, -0.28),
    _Sticker('🍅', 0.04, -0.20, 23, 0.20),
    _Sticker('🌽', 0.11, -0.30, 25, 0.34),
    _Sticker('🥩', 0.18, -0.18, 26, -0.22),
    _Sticker('🥦', 0.25, -0.28, 24, 0.38),
    _Sticker('🥛', 0.32, -0.20, 23, -0.32),
    _Sticker('🍗', 0.39, -0.30, 26, 0.16),
    _Sticker('🧀', 0.46, -0.18, 24, 0.42),
    _Sticker('🍎', 0.53, -0.28, 23, -0.18),
    _Sticker('🥕', 0.60, -0.20, 24, 0.30),
    _Sticker('🥚', 0.67, -0.30, 21, -0.36),
    _Sticker('🍇', 0.74, -0.18, 24, 0.24),
    _Sticker('🥒', 0.81, -0.28, 25, -0.26),
    _Sticker('🐓', 0.88, -0.20, 22, 0.18),
    _Sticker('🫑', 0.95, -0.30, 22, -0.34),
    // Band 2
    _Sticker('🍆', 0.00, 0.04, 23, 0.28),
    _Sticker('🥔', 0.07, 0.12, 21, -0.20),
    _Sticker('🥗', 0.14, 0.02, 23, 0.36),
    _Sticker('🍞', 0.21, 0.12, 23, -0.28),
    _Sticker('🧅', 0.28, 0.02, 22, 0.22),
    _Sticker('🥓', 0.35, 0.12, 24, -0.38),
    _Sticker('🍐', 0.42, 0.02, 23, 0.32),
    _Sticker('🍋', 0.49, 0.12, 22, -0.24),
    _Sticker('🥜', 0.56, 0.02, 22, 0.18),
    _Sticker('🍠', 0.63, 0.12, 24, 0.30),
    _Sticker('🍊', 0.70, 0.02, 23, -0.26),
    _Sticker('🥑', 0.77, 0.12, 23, 0.22),
    _Sticker('🍓', 0.84, 0.02, 22, -0.34),
    _Sticker('🥬', 0.91, 0.12, 25, 0.26),
    _Sticker('🍗', 0.98, 0.02, 25, -0.18),
    // Band 3
    _Sticker('🌽', -0.02, 0.34, 24, 0.40),
    _Sticker('🥩', 0.05, 0.44, 25, -0.30),
    _Sticker('🍅', 0.12, 0.34, 23, 0.20),
    _Sticker('🥛', 0.19, 0.44, 23, -0.40),
    _Sticker('🥦', 0.26, 0.34, 24, 0.28),
    _Sticker('🧀', 0.33, 0.44, 23, -0.22),
    _Sticker('🍎', 0.40, 0.34, 23, 0.34),
    _Sticker('🥕', 0.47, 0.44, 24, -0.26),
    _Sticker('🥚', 0.54, 0.34, 21, 0.18),
    _Sticker('🍇', 0.61, 0.44, 24, -0.36),
    _Sticker('🥒', 0.68, 0.34, 25, 0.24),
    _Sticker('🐓', 0.75, 0.44, 22, -0.20),
    _Sticker('🫑', 0.82, 0.34, 22, 0.38),
    _Sticker('🍆', 0.89, 0.44, 23, -0.28),
    _Sticker('🥔', 0.96, 0.34, 21, 0.22),
    // Band 4
    _Sticker('🥗', 0.00, 0.66, 23, -0.32),
    _Sticker('🍞', 0.07, 0.76, 23, 0.26),
    _Sticker('🧅', 0.14, 0.66, 22, -0.18),
    _Sticker('🥓', 0.21, 0.76, 24, 0.36),
    _Sticker('🍐', 0.28, 0.66, 23, -0.24),
    _Sticker('🍋', 0.35, 0.76, 22, 0.30),
    _Sticker('🥜', 0.42, 0.66, 22, -0.38),
    _Sticker('🍠', 0.49, 0.76, 24, 0.20),
    _Sticker('🍊', 0.56, 0.66, 23, -0.28),
    _Sticker('🥑', 0.63, 0.76, 23, 0.34),
    _Sticker('🍓', 0.70, 0.66, 22, -0.22),
    _Sticker('🥬', 0.77, 0.76, 25, 0.28),
    _Sticker('🍗', 0.84, 0.66, 25, -0.34),
    _Sticker('🌽', 0.91, 0.76, 24, 0.18),
    _Sticker('🥩', 0.98, 0.66, 25, -0.26),
    // Band 5 (bleeds off the bottom edge)
    _Sticker('🍅', 0.03, 0.96, 23, 0.24),
    _Sticker('🥛', 0.17, 0.96, 23, -0.30),
    _Sticker('🥦', 0.31, 0.96, 24, 0.32),
    _Sticker('🧀', 0.45, 0.96, 23, -0.20),
    _Sticker('🍎', 0.59, 0.96, 23, 0.36),
    _Sticker('🥕', 0.73, 0.96, 24, -0.24),
    _Sticker('🍇', 0.87, 0.96, 24, 0.28),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // One opacity layer for the whole sheet keeps the wash uniform.
        return Opacity(
          opacity: _opacity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final s in _stickers)
                Positioned(
                  left: w * s.x,
                  top: h * s.y,
                  child: Transform.rotate(
                    angle: s.angle,
                    child: Text(
                      s.emoji,
                      style: TextStyle(fontSize: s.size, height: 1),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
