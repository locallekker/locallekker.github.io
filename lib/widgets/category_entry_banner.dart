import 'package:flutter/material.dart';

/// Shared look and behaviour for the member-home category entry banners
/// (Partners, Fresh & Local, Local Sips).
///
/// [compact] renders a narrow, fixed-height card so two or three banners can
/// sit side by side in a single row; otherwise the card spans the full width.
class CategoryEntryBanner extends StatefulWidget {
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Light -> mid -> dark, used for the background gradient.
  final List<Color> gradientColors;
  final Color shadowColor;

  /// Optional decorative backdrop drawn behind the text.
  final Widget? background;

  /// Small corner tag, e.g. "18+".
  final String? tag;

  final int newDealCount;
  final int partnerCount;
  final int dealCount;
  final bool compact;

  const CategoryEntryBanner({
    super.key,
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.shadowColor,
    this.background,
    this.tag,
    this.newDealCount = 0,
    this.partnerCount = 0,
    this.dealCount = 0,
    this.compact = false,
  });

  @override
  State<CategoryEntryBanner> createState() => _CategoryEntryBannerState();
}

class _CategoryEntryBannerState extends State<CategoryEntryBanner>
    with SingleTickerProviderStateMixin {
  /// Keeps the three compact cards the same height regardless of content.
  static const double compactHeight = 132;

  late final AnimationController _pulseController;

  Color get _mid => widget.gradientColors[widget.gradientColors.length ~/ 2];
  Color get _dark => widget.gradientColors.last;

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
  void didUpdateWidget(covariant CategoryEntryBanner oldWidget) {
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
    // Horizontal inset leaves room for the shadow and for the pulse to grow
    // without overflowing the parent.
    final card = Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 2 : 4),
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
    final radius = widget.compact ? 16.0 : 20.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final t = _hasNewDeals
            ? Curves.easeInOut.transform(_pulseController.value)
            : 0.0;
        // Decoration sits outermost so the shadow follows the rounded corners.
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: widget.shadowColor.withValues(
                  alpha: 0.28 + (0.16 * t),
                ),
                blurRadius: (widget.compact ? 18 : 30) + (16 * t),
                spreadRadius: -2 + (3 * t),
                offset: Offset(0, widget.compact ? 8 : 14),
              ),
              BoxShadow(
                color: _dark.withValues(alpha: 0.34 + (0.22 * t)),
                blurRadius: (widget.compact ? 8 : 12) + (8 * t),
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
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.gradientColors,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            child: SizedBox(
              height: widget.compact ? compactHeight : null,
              child: Stack(
                children: [
                  if (widget.background != null)
                    Positioned.fill(child: widget.background!),
                  // Softens the backdrop behind the text so it stays readable.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: widget.compact
                              ? Alignment.topCenter
                              : Alignment.centerLeft,
                          end: widget.compact
                              ? Alignment.bottomCenter
                              : Alignment.centerRight,
                          colors: [
                            _dark.withValues(alpha: 0.58),
                            _mid.withValues(alpha: 0.20),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.45, 0.80],
                        ),
                      ),
                    ),
                  ),
                  widget.compact ? _buildCompactBody() : _buildWideBody(),
                  if (widget.tag != null)
                    Positioned(top: 6, right: 6, child: _buildTag()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: [
          _buildIconCircle(64, 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title, style: _titleStyle(19)),
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
    );
  }

  Widget _buildCompactBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildIconCircle(40, 24),
          const SizedBox(height: 8),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle(13),
          ),
          const SizedBox(height: 4),
          Text(
            _compactCountsLabel(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
              shadows: const [
                Shadow(color: Color(0x55000000), blurRadius: 3),
              ],
            ),
          ),
          if (_hasNewDeals) ...[
            const SizedBox(height: 5),
            _buildCompactNewDot(),
          ],
        ],
      ),
    );
  }

  Widget _buildIconCircle(double size, double iconSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 2,
        ),
      ),
      child: Icon(widget.icon, size: iconSize, color: _dark),
    );
  }

  Widget _buildTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        widget.tag!,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: _dark,
        ),
      ),
    );
  }

  TextStyle _titleStyle(double size) => TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    letterSpacing: 0.2,
    shadows: const [
      Shadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1)),
    ],
  );

  String _compactCountsLabel() {
    if (widget.partnerCount == 0) return widget.subtitle;
    final partners = '${widget.partnerCount} partner'
        '${widget.partnerCount == 1 ? '' : 's'}';
    if (widget.dealCount == 0) return partners;
    return '$partners · ${widget.dealCount} deal'
        '${widget.dealCount == 1 ? '' : 's'}';
  }

  Widget _buildCountsRow() {
    // Before the counts land, keep the descriptive strapline in their place.
    if (widget.partnerCount == 0) {
      return Text(
        widget.subtitle,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.95),
          shadows: const [
            Shadow(
              color: Color(0x55000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
      );
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
                  color: Color(0x55000000),
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

  Widget _buildNewDealsBadge() {
    final count = widget.newDealCount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: widget.shadowColor.withValues(alpha: 0.25),
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
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: _dark,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactNewDot() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFD32F2F),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '${widget.newDealCount} new',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single scattered emoji sticker, positioned as a fraction of the card.
class BannerSticker {
  final String emoji;
  final double x;
  final double y;
  final double size;
  final double angle;

  const BannerSticker(this.emoji, this.x, this.y, this.size, this.angle);
}

/// Scattered emoji "sticker bomb" backdrop shared by the category banners.
class StickerBomb extends StatelessWidget {
  final List<BannerSticker> stickers;
  final double opacity;

  const StickerBomb({super.key, required this.stickers, this.opacity = 0.2});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // One opacity layer for the whole sheet keeps the wash uniform.
        return Opacity(
          opacity: opacity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final s in stickers)
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
