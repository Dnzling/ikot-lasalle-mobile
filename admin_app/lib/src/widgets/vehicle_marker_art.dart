import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Small isometric vehicle illustrations for Mapbox symbols. These are drawn
/// at runtime so the same marker works on Android and in the web map.
class VehicleMarkerArt {
  const VehicleMarkerArt._();

  static Future<Uint8List> make({required bool electric}) async {
    const width = 112;
    const height = 84;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    final body = electric ? const Color(0xFF13A9A0) : const Color(0xFFF4A524);
    final dark = electric ? const Color(0xFF08776F) : const Color(0xFFC87911);
    final roof = electric ? const Color(0xFF9BE8DD) : const Color(0xFFFFD574);

    paint.color = const Color(0x44000000);
    canvas.drawOval(const Rect.fromLTWH(12, 62, 90, 14), paint);

    // Rear and front wheels sit below the side panel to give the icon depth.
    for (final x in [29.0, 82.0]) {
      paint.color = const Color(0xFF263444);
      canvas.drawOval(Rect.fromLTWH(x, 54, 17, 19), paint);
      paint.color = const Color(0xFFCAD5D9);
      canvas.drawOval(Rect.fromLTWH(x + 5, 59, 7, 8), paint);
    }

    _polygon(canvas, paint, dark, [
      const Offset(17, 31),
      const Offset(79, 31),
      const Offset(101, 42),
      const Offset(101, 61),
      const Offset(79, 54),
      const Offset(17, 54),
    ]);
    _polygon(canvas, paint, body, [
      const Offset(13, 28),
      const Offset(77, 28),
      const Offset(77, 58),
      const Offset(13, 58),
    ]);
    _polygon(canvas, paint, roof, [
      const Offset(13, 28),
      const Offset(34, 15),
      const Offset(79, 15),
      const Offset(101, 28),
      const Offset(77, 29),
    ]);
    _polygon(canvas, paint, const Color(0xFF255B70), [
      const Offset(19, 31),
      const Offset(35, 20),
      const Offset(47, 20),
      const Offset(47, 40),
      const Offset(19, 40),
    ]);
    _polygon(canvas, paint, const Color(0xFF255B70), [
      const Offset(51, 20),
      const Offset(75, 20),
      const Offset(75, 40),
      const Offset(51, 40),
    ]);
    _polygon(canvas, paint, const Color(0xFF2F7185), [
      const Offset(81, 22),
      const Offset(96, 29),
      const Offset(96, 40),
      const Offset(81, 35),
    ]);
    paint.color = Colors.white.withValues(alpha: .42);
    canvas.drawRect(const Rect.fromLTWH(22, 47, 51, 4), paint);
    paint.color = const Color(0xFFFFF4C5);
    canvas.drawOval(const Rect.fromLTWH(91, 44, 8, 6), paint);
    paint.color = const Color(0xFF1F3A43);
    canvas.drawRect(const Rect.fromLTWH(14, 40, 2, 17), paint);

    if (electric) {
      _polygon(canvas, paint, const Color(0xFFFFFF8B), [
        const Offset(62, 43),
        const Offset(56, 50),
        const Offset(61, 50),
        const Offset(58, 57),
        const Offset(69, 47),
        const Offset(64, 47),
        const Offset(68, 43),
      ]);
    } else {
      paint.color = const Color(0xFF543B22);
      canvas.drawRect(const Rect.fromLTWH(52, 44, 19, 3), paint);
    }

    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  static void _polygon(
    Canvas canvas,
    Paint paint,
    Color color,
    List<Offset> points,
  ) {
    paint.color = color;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path..close(), paint);
  }
}
