import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import 'package:flutter/foundation.dart';

class CustomQrCode extends StatefulWidget {
  final String data;
  final String logoAssetPath;
  final double size;

  const CustomQrCode({
    super.key,
    required this.data,
    required this.logoAssetPath,
    this.size = 1000.0,
  });

  @override
  State<CustomQrCode> createState() => _CustomQrCodeState();
}

class _CustomQrCodeState extends State<CustomQrCode> {
  ui.Image? _logoImage;

  @override
  void initState() {
    super.initState();
    _loadLogoImage();
  }

  @override
  void didUpdateWidget(CustomQrCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoAssetPath != widget.logoAssetPath) {
      _loadLogoImage();
    }
  }

  Future<void> _loadLogoImage() async {
    try {
      final ByteData data = await rootBundle.load(widget.logoAssetPath);
      final Uint8List bytes = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      setState(() {
        _logoImage = frameInfo.image;
      });
    } catch (e) {
      debugPrint(
        'Logo image not found or failed to load: ${widget.logoAssetPath}',
      );
      // Logo will remain null and won't be displayed
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _QrCodePainter(
          data: widget.data,
          logoImage: _logoImage,
          size: widget.size,
        ),
      ),
    );
  }
}

class _QrCodePainter extends CustomPainter {
  final String data;
  final ui.Image? logoImage;
  final double size;

  _QrCodePainter({
    required this.data,
    required this.logoImage,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Try different QR code versions until one fits
    int version = 4;
    QrCode? qrCode;
    QrImage? qrImage;

    while (version <= 40) {
      try {
        qrCode = QrCode(version, QrErrorCorrectLevel.H)..addData(data);
        qrImage = QrImage(qrCode);
        break;
      } catch (e) {
        version++;
      }
    }

    if (qrCode == null || qrImage == null) {
      debugPrint('Failed to create QR code with any version');
      return;
    }

    // Calculate module size (accounting for quiet zone)
    final quietZoneModules = 4; // 4 modules quiet zone as required
    final totalModules = qrImage.moduleCount + (quietZoneModules * 2);
    final moduleSize = this.size / totalModules;

    // Paint white background
    final backgroundPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, this.size, this.size), backgroundPaint);

    // Paint QR code modules
    final modulePaint = Paint()..color = Colors.black;

    for (int x = 0; x < qrImage.moduleCount; x++) {
      for (int y = 0; y < qrImage.moduleCount; y++) {
        if (qrImage.isDark(y, x)) {
          final left = (x + quietZoneModules) * moduleSize;
          final top = (y + quietZoneModules) * moduleSize;
          final rect = Rect.fromLTWH(left, top, moduleSize, moduleSize);
          canvas.drawRect(rect, modulePaint);
        }
      }
    }

    // Draw logo if available
    if (logoImage != null) {
      _drawLogo(canvas, size);
    }
  }

  void _drawLogo(Canvas canvas, Size size) {
    // Logo should be 25% of QR code width
    final logoSize = size.width * 0.25;

    // Center the logo
    final logoLeft = (size.width - logoSize) / 2;
    final logoTop = (size.height - logoSize) / 2;
    final logoRect = Rect.fromLTWH(logoLeft, logoTop, logoSize, logoSize);

    // Create a paint that preserves transparency
    final logoPaint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    // Draw the logo image
    canvas.drawImageRect(
      logoImage!,
      Rect.fromLTWH(
        0,
        0,
        logoImage!.width.toDouble(),
        logoImage!.height.toDouble(),
      ),
      logoRect,
      logoPaint,
    );
  }

  @override
  bool shouldRepaint(_QrCodePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.logoImage != logoImage ||
        oldDelegate.size != size;
  }
}
