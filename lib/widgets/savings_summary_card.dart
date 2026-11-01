import 'package:flutter/material.dart';

/// A beautiful card displaying total savings statistics from deal authorizations
/// Matches the Local Lekker brand with teal/green colors
class SavingsSummaryCard extends StatefulWidget {
  final double totalSpent;
  final double totalSaved;
  final double totalPaid;
  final double totalTips;
  final int totalDeals;
  final bool isLoading;
  final VoidCallback? onBrowseDeals;
  final VoidCallback? onViewReceipts;

  const SavingsSummaryCard({
    super.key,
    required this.totalSpent,
    required this.totalSaved,
    required this.totalPaid,
    required this.totalTips,
    required this.totalDeals,
    this.isLoading = false,
    this.onBrowseDeals,
    this.onViewReceipts,
  });

  @override
  State<SavingsSummaryCard> createState() => _SavingsSummaryCardState();
}

class _SavingsSummaryCardState extends State<SavingsSummaryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savingsPercentage = widget.totalSpent > 0
        ? (widget.totalSaved / widget.totalSpent) * 100
        : 0.0;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.savings, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your Savings Summary',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Pulsing button for viewing receipts - always clickable
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Material(
                        color: Colors.transparent,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(25),
                        child: InkWell(
                          onTap: widget.onViewReceipts,
                          borderRadius: BorderRadius.circular(25),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E5BA0).withValues(
                                alpha: 0.95,
                              ),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0E5BA0).withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long,
                                  color: Colors.white,
                                  size: 12,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${widget.totalDeals} deal${widget.totalDeals != 1 ? 's' : ''} redeemed',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Main savings amount - Big and prominent
          Center(
            child: Column(
              children: [
                const Text(
                  'Total Saved',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'R',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.totalSaved.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
                if (savingsPercentage > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${savingsPercentage.toStringAsFixed(1)}% savings rate',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Divider
          Container(height: 1, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          // Breakdown section - 2x2 grid
          Column(
            children: [
              // First row
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      'Original Total',
                      'R${widget.totalSpent.toStringAsFixed(2)}',
                      Icons.receipt_long,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 35,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  Expanded(
                    child: _buildStatItem(
                      'You Paid',
                      'R${(widget.totalPaid - widget.totalTips).toStringAsFixed(2)}',
                      Icons.check_circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Divider between rows
              Container(height: 1, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 8),
              // Second row
              Row(
                children: [
                  Expanded(
                    child: _buildStatItem(
                      'Tips Paid',
                      'R${widget.totalTips.toStringAsFixed(2)}',
                      Icons.volunteer_activism,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Floating, clickable, pulsing button for deals - always visible
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Center(
              child: ScaleTransition(
                scale: _pulseAnimation,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(30),
                  child: InkWell(
                    onTap: widget.onBrowseDeals,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4B400).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF4B400).withValues(
                              alpha: 0.5,
                            ),
                            blurRadius: 16,
                            spreadRadius: 2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_offer,
                            color: Colors.black87,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              widget.totalSaved > 0
                                  ? 'Keep using Local Lekker to maximize your savings!'
                                  : 'Click to start saving with Local Lekker\'s Trusted partners',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward,
                            color: Colors.black54,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    // Special 3D glowing heart effect for Tips Paid icon
    final isHeartIcon = icon == Icons.volunteer_activism;

    return Column(
      children: [
        isHeartIcon
            ? Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE03C31).withValues(alpha: 0.6),
                      blurRadius: 12,
                      spreadRadius: 3,
                    ),
                    BoxShadow(
                      color: const Color(0xFFE03C31).withValues(alpha: 0.4),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFE03C31),
                        Color(0xFFE03C31),
                        Color(0xFFB02A22),
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ).createShader(bounds);
                  },
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 24,
                    shadows: const [
                      Shadow(
                        color: Colors.black45,
                        offset: Offset(2, 2),
                        blurRadius: 4,
                      ),
                      Shadow(
                        color: Color(0xFFE03C31),
                        offset: Offset(-1, -1),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              )
            : Icon(icon, color: Colors.white, size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
