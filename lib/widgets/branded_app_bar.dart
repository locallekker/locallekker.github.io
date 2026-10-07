import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../features/chat/chat_list_page.dart';
import '../services/supabase_service.dart';

/// Drop-in replacement for [AppBar] that renders the Local Lekker
/// wordmark with a consistent light logo block on a clean header.
///
/// Design:
///   * Background is a soft white→cream gradient so the dark serif
///     logo (which has a transparent background) is fully legible
///     without any container.
///   * The logo lives in the AppBar's reserved [leading] slot and uses
///     the same block size and position as the TP dashboard standard.
///   * A thin brand-coloured accent strip sits along the bottom edge
///     for visual definition against the page content.
///   * Icons and title text default to the brand primary colour so
///     they read clearly on the light surface.
class BrandedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final IconThemeData? iconTheme;
  final IconThemeData? actionsIconTheme;
  final bool? centerTitle;
  final double? elevation;
  final double? toolbarHeight;
  final PreferredSizeWidget? bottom;
  final Widget? flexibleSpace;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final double? titleSpacing;
  final TextStyle? titleTextStyle;
  final ShapeBorder? shape;
  final double? leadingWidth;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final bool primary;
  final bool showChatButton;

  const BrandedAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.foregroundColor,
    this.iconTheme,
    this.actionsIconTheme,
    this.centerTitle,
    this.elevation,
    this.toolbarHeight,
    this.bottom,
    this.flexibleSpace,
    this.systemOverlayStyle,
    this.titleSpacing,
    this.titleTextStyle,
    this.shape,
    this.leadingWidth,
    this.shadowColor,
    this.surfaceTintColor,
    this.primary = true,
    this.showChatButton = true,
  });

  /// Rendered logo height used across TP and TP-member screens.
  static const double _logoHeight = 64;

  /// Approximate width reserved for the logo image.
  static const double _logoWidth = 104;

  /// Fixed outer size of the light logo block.
  static const double _logoBlockWidth = 132;
  static const double _logoBlockHeight = 84;

  /// Zoom factor used to crop transparent padding inside the logo asset
  /// so the visible mark appears larger while the outer block stays fixed.
  static const double _logoZoom = 3.0;

  /// Reserved width of the leading slot (logo + a small gap).
  static const double _leadingSlotWidth = 146;

  /// Reserved width of the leading slot when a caller-supplied [leading]
  /// (e.g. a back button) needs to sit beside the logo.
  static const double _leadingSlotWidthWithBack = 262;

  /// Toolbar height tall enough to house the larger logo comfortably.
  static const double _defaultToolbarHeight = 96;

  /// Height of the thin brand accent strip rendered along the bottom
  /// edge of the bar.
  static const double _accentStripHeight = 3;

  double get _effectiveToolbarHeight => toolbarHeight ?? _defaultToolbarHeight;
  double get _bottomHeight =>
      (bottom?.preferredSize.height ?? 0) + _accentStripHeight;

  @override
  Size get preferredSize =>
      Size.fromHeight(_effectiveToolbarHeight + _bottomHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;

    // Default surface for the brand bar: a soft, slightly warm white
    // gradient that makes the dark serif logo pop without a chip.
    const Color defaultBg = Colors.white;
    final Color bg = backgroundColor ?? appBarTheme.backgroundColor ?? defaultBg;
    final bool isLightBg = ThemeData.estimateBrightnessForColor(bg) ==
        Brightness.light;

    // Foreground (icons + title) defaults to the brand primary on the
    // light surface so everything stays readable and on-brand.
    final Color fg = foregroundColor ??
        (isLightBg ? AppColors.primary : Colors.white);

    final overlay = systemOverlayStyle ??
        appBarTheme.systemOverlayStyle ??
        (isLightBg
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light);

    final Widget logo = ClipRect(
      child: SizedBox(
        height: _logoBlockHeight,
        width: _logoBlockWidth,
        child: FittedBox(
          fit: BoxFit.none,
          alignment: Alignment.center,
          child: SizedBox(
            height: _logoHeight * _logoZoom,
            width: _logoWidth * _logoZoom,
            child: Image.asset(
              'assets/locallekker_logo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );

    // Place the logo in the AppBar's reserved [leading] slot so it
    // cannot be squeezed out by a long [actions] list. When the caller
    // supplies their own [leading] (typically a back button) — or when
    // one would normally be auto-implied because we can pop — stack it
    // next to the logo inside the same slot.
    final ModalRoute<dynamic>? parentRoute = ModalRoute.of(context);
    final bool canPop = parentRoute?.canPop ?? false;
    Widget? effectiveLeading = leading;
    if (effectiveLeading == null && automaticallyImplyLeading && canPop) {
      effectiveLeading = BackButton(color: fg);
    }

    final Widget leadingWithBrand = effectiveLeading == null
        ? Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Align(alignment: Alignment.centerLeft, child: logo),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: kToolbarHeight,
                child: Center(child: effectiveLeading),
              ),
              logo,
            ],
          );

    final double effectiveLeadingWidth = leadingWidth ??
        (effectiveLeading == null
            ? _leadingSlotWidth
            : _leadingSlotWidthWithBack);

    final IconThemeData effectiveIconTheme =
        iconTheme ?? IconThemeData(color: fg);
    final IconThemeData effectiveActionsIconTheme =
        actionsIconTheme ?? IconThemeData(color: fg, size: 22);

    // Compact-density wrapper for action widgets so multiple icons,
    // toggles and popup menus can sit next to the larger logo on
    // narrow phone screens without overlapping it.
    final currentUser = SupabaseService.instance.getCurrentUser();
    final List<Widget> effectiveActions = [
      if (showChatButton && currentUser != null)
        IconButton(
          tooltip: 'Messages',
          icon: const Icon(Icons.forum_outlined),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatListPage()),
            );
          },
        ),
      ...?actions,
    ];

    List<Widget>? compactActions;
    if (effectiveActions.isNotEmpty) {
      compactActions = [
        IconTheme.merge(
          data: IconThemeData(size: 21, color: fg),
          child: Row(mainAxisSize: MainAxisSize.min, children: effectiveActions),
        ),
        const SizedBox(width: 0),
      ];
    }

    // A thin brand accent strip along the bottom gives the light bar
    // crisp definition against the page below it and keeps the
    // colourful brand identity present even without a coloured bg.
    final PreferredSizeWidget accentStrip = PreferredSize(
      preferredSize: const Size.fromHeight(_accentStripHeight),
      child: Container(
        height: _accentStripHeight,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary,
              AppColors.accent,
              AppColors.primary,
            ],
          ),
        ),
      ),
    );

    final PreferredSizeWidget effectiveBottom = bottom == null
        ? accentStrip
        : PreferredSize(
            preferredSize: Size.fromHeight(
                bottom!.preferredSize.height + _accentStripHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [bottom!, accentStrip],
            ),
          );

    // Soft warm-white gradient backdrop. Only applied when no custom
    // backgroundColor is supplied so callers can still tint the bar.
    final Widget? gradientBackdrop = backgroundColor == null
        ? const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Color(0xFFFFF8EF), // very soft cream
                ],
              ),
            ),
          )
        : null;

    // Wrap the title in a FittedBox so long labels (e.g. "Edit Partner",
    // a long business name) scale down to fit the remaining toolbar
    // width instead of being truncated with an ellipsis next to the
    // large brand logo.
    final Widget? fittedTitle = title == null
        ? null
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: (centerTitle ?? false)
                ? Alignment.center
                : Alignment.centerLeft,
            child: title,
          );

    return AppBar(
      primary: primary,
      automaticallyImplyLeading: false,
      leading: leadingWithBrand,
      leadingWidth: effectiveLeadingWidth,
      title: fittedTitle,
      centerTitle: centerTitle ?? false,
      titleSpacing: titleSpacing ?? 4,
      actions: compactActions,
      backgroundColor: backgroundColor == null ? Colors.transparent : bg,
      foregroundColor: fg,
      iconTheme: effectiveIconTheme,
      actionsIconTheme: effectiveActionsIconTheme,
      elevation: elevation ?? 0,
      scrolledUnderElevation: 0,
      toolbarHeight: _effectiveToolbarHeight,
      flexibleSpace: flexibleSpace ?? gradientBackdrop,
      systemOverlayStyle: overlay,
      titleTextStyle: titleTextStyle ??
          TextStyle(
            color: fg,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
      shape: shape,
      shadowColor: shadowColor,
      surfaceTintColor: surfaceTintColor ?? Colors.transparent,
      bottom: effectiveBottom,
    );
  }
}
