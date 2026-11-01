import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ProfilePhotoShape { circle, roundedRect }

class ProfilePhoto extends StatefulWidget {
  final String? imageUrl;
  final Uint8List? memoryBytes;
  final String? displayName;
  final double size;
  final ProfilePhotoShape shape;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final String? fallbackAssetPath;
  final IconData fallbackIcon;
  final BoxFit fit;
  final bool adaptiveBox;
  final double minAdaptiveWidthFactor;
  final double maxAdaptiveWidthFactor;
  final double minAdaptiveHeightFactor;
  final double maxAdaptiveHeightFactor;
  final double adaptiveTargetAreaFactor;
  final double adaptiveMinAspectRatio;
  final double adaptiveMaxAspectRatio;
  final double adaptiveCornerRadiusFactor;
  final Color? borderColor;
  final double borderWidth;

  const ProfilePhoto({
    super.key,
    this.imageUrl,
    this.memoryBytes,
    this.displayName,
    required this.size,
    this.shape = ProfilePhotoShape.circle,
    this.borderRadius = 16,
    this.backgroundColor,
    this.foregroundColor,
    this.fallbackAssetPath,
    this.fallbackIcon = Icons.person,
    this.fit = BoxFit.contain,
    this.adaptiveBox = false,
    this.minAdaptiveWidthFactor = 0.72,
    this.maxAdaptiveWidthFactor = 1.65,
    this.minAdaptiveHeightFactor = 0.72,
    this.maxAdaptiveHeightFactor = 1.0,
    this.adaptiveTargetAreaFactor = 0.48,
    this.adaptiveMinAspectRatio = 0.6,
    this.adaptiveMaxAspectRatio = 1.8,
    this.adaptiveCornerRadiusFactor = 0.26,
    this.borderColor,
    this.borderWidth = 0,
  });

  @override
  State<ProfilePhoto> createState() => _ProfilePhotoState();
}

class _ProfilePhotoState extends State<ProfilePhoto> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  double? _resolvedAspectRatio;

  @override
  void initState() {
    super.initState();
    _resolveAspectRatio();
  }

  @override
  void didUpdateWidget(covariant ProfilePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.memoryBytes != widget.memoryBytes ||
        oldWidget.fallbackAssetPath != widget.fallbackAssetPath ||
        oldWidget.adaptiveBox != widget.adaptiveBox) {
      _resolveAspectRatio();
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  void _removeImageListener() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  ImageProvider<Object>? _currentImageProvider() {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) {
      return MemoryImage(widget.memoryBytes!);
    }

    final trimmedUrl = widget.imageUrl?.trim();
    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      return NetworkImage(trimmedUrl);
    }

    if (widget.fallbackAssetPath != null && widget.fallbackAssetPath!.isNotEmpty) {
      return AssetImage(widget.fallbackAssetPath!);
    }

    return null;
  }

  void _resolveAspectRatio() {
    if (!widget.adaptiveBox || widget.shape != ProfilePhotoShape.roundedRect) {
      _removeImageListener();
      if (_resolvedAspectRatio != null && mounted) {
        setState(() => _resolvedAspectRatio = null);
      } else {
        _resolvedAspectRatio = null;
      }
      return;
    }

    final provider = _currentImageProvider();
    if (provider == null) {
      _removeImageListener();
      if (_resolvedAspectRatio != null && mounted) {
        setState(() => _resolvedAspectRatio = null);
      } else {
        _resolvedAspectRatio = null;
      }
      return;
    }

    _removeImageListener();
    final stream = provider.resolve(const ImageConfiguration());
    final listener = ImageStreamListener((imageInfo, _) {
      final width = imageInfo.image.width.toDouble();
      final height = imageInfo.image.height.toDouble();
      if (width <= 0 || height <= 0) return;
      final ratio = width / height;
      if (!mounted) {
        _resolvedAspectRatio = ratio;
        return;
      }
      if (_resolvedAspectRatio == ratio) return;
      setState(() => _resolvedAspectRatio = ratio);
    });

    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  ({double width, double height}) _effectiveSize() {
    if (!widget.adaptiveBox || widget.shape != ProfilePhotoShape.roundedRect) {
      return (width: widget.size, height: widget.size);
    }

    final ratio = _resolvedAspectRatio;
    if (ratio == null || !ratio.isFinite || ratio <= 0) {
      return (width: widget.size, height: widget.size);
    }

    final safeAspectRatio = ratio
        .clamp(widget.adaptiveMinAspectRatio, widget.adaptiveMaxAspectRatio)
        .toDouble();
    final minWidth = widget.size * widget.minAdaptiveWidthFactor;
    final maxWidth = widget.size * widget.maxAdaptiveWidthFactor;
    final minHeight = widget.size * widget.minAdaptiveHeightFactor;
    final maxHeight = widget.size * widget.maxAdaptiveHeightFactor;

    final targetArea = widget.size * widget.size * widget.adaptiveTargetAreaFactor;
    final width = math
        .sqrt(targetArea * safeAspectRatio)
        .clamp(minWidth, maxWidth)
        .toDouble();
    final height = math
        .sqrt(targetArea / safeAspectRatio)
        .clamp(minHeight, maxHeight)
        .toDouble();

    return (width: width, height: height);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.backgroundColor ?? Theme.of(context).colorScheme.surfaceContainerHighest;
    final fgColor = widget.foregroundColor ?? Theme.of(context).colorScheme.primary;
    final child = _buildContent(fgColor);

    if (widget.shape == ProfilePhotoShape.circle) {
      return CircleAvatar(
        radius: widget.size / 2,
        backgroundColor: bgColor,
        child: ClipOval(
          child: SizedBox(width: widget.size, height: widget.size, child: child),
        ),
      );
    }

    final effectiveSize = _effectiveSize();
    final effectiveRadius = widget.adaptiveBox
        ? (effectiveSize.width < effectiveSize.height
              ? effectiveSize.width
              : effectiveSize.height) *
            widget.adaptiveCornerRadiusFactor
        : widget.borderRadius;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: effectiveSize.width,
      height: effectiveSize.height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(effectiveRadius),
        border: widget.borderWidth > 0
            ? Border.all(
                color: widget.borderColor ?? Colors.transparent,
                width: widget.borderWidth,
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildContent(Color fgColor) {
    if (widget.memoryBytes != null && widget.memoryBytes!.isNotEmpty) {
      return Image.memory(
        widget.memoryBytes!,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
      );
    }

    final trimmedUrl = widget.imageUrl?.trim();
    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      return Image.network(
        trimmedUrl,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildFallback(fgColor),
      );
    }

    if (widget.fallbackAssetPath != null && widget.fallbackAssetPath!.isNotEmpty) {
      return Image.asset(
        widget.fallbackAssetPath!,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
      );
    }

    return _buildFallback(fgColor);
  }

  Widget _buildFallback(Color fgColor) {
    final initials = _buildInitials(widget.displayName);
    if (initials != null) {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
            color: fgColor,
            fontWeight: FontWeight.w700,
            fontSize: widget.size * 0.32,
          ),
        ),
      );
    }

    return Center(
      child: Icon(widget.fallbackIcon, color: fgColor, size: widget.size * 0.42),
    );
  }

  String? _buildInitials(String? rawName) {
    final parts = rawName
        ?.trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts == null || parts.isEmpty) return null;
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1).toUpperCase()}${parts.last.substring(0, 1).toUpperCase()}';
  }
}