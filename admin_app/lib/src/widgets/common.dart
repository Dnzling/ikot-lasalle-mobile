import 'dart:math' as math;
import 'package:flutter/material.dart';

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: Color(0xFF68756E))),
          ],
        ),
      ),
      ?action,
    ],
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.good = true});
  final String text;
  final bool good;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: good ? const Color(0xFFE4F6EA) : const Color(0xFFFFF2DA),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: good ? const Color(0xFF08783E) : const Color(0xFF9A6100),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class MiniChart extends StatelessWidget {
  const MiniChart({
    super.key,
    required this.values,
    this.color = const Color(0xFF0A8A4B),
    this.height = 190,
  });
  final List<double> values;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(painter: _ChartPainter(values, color)),
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFEAF0EC)
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] / 100 * size.height);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: .01)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class MapCanvas extends StatefulWidget {
  const MapCanvas({
    super.key,
    this.interactivePin = false,
    this.label = 'Jeep 01 • A-101',
    this.initialPin,
    this.onPinChanged,
  });
  final bool interactivePin;
  final String label;
  final Offset? initialPin;
  final ValueChanged<Offset>? onPinChanged;
  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> {
  Offset pin = const Offset(.57, .48);
  @override
  void initState() {
    super.initState();
    pin = widget.initialPin ?? pin;
  }

  void _setPin(Offset value) {
    setState(() => pin = value);
    widget.onPinChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => GestureDetector(
      onPanUpdate: widget.interactivePin
          ? (d) => _setPin(
              Offset(
                (pin.dx + d.delta.dx / box.maxWidth).clamp(.04, .96),
                (pin.dy + d.delta.dy / box.maxHeight).clamp(.08, .92),
              ),
            )
          : null,
      onTapDown: widget.interactivePin
          ? (d) => _setPin(
              Offset(
                d.localPosition.dx / box.maxWidth,
                d.localPosition.dy / box.maxHeight,
              ),
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            Positioned(
              left: pin.dx * box.maxWidth - 20,
              top: pin.dy * box.maxHeight - 42,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF073F28),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      widget.interactivePin ? 'Drop point' : widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.location_on,
                    color: Color(0xFF08783E),
                    size: 34,
                  ),
                ],
              ),
            ),
            const Positioned(
              left: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(7)),
                ),
                child: Padding(
                  padding: EdgeInsets.all(7),
                  child: Row(
                    children: [
                      Icon(Icons.layers_outlined, size: 16),
                      SizedBox(width: 5),
                      Text(
                        'Mapbox ready',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFE9EFE9));
    final blocks = Paint()..color = const Color(0xFFD5E0D7);
    for (var i = 0; i < 15; i++) {
      final x = ((i * 83) % 100) / 100 * s.width;
      final y = ((i * 47) % 100) / 100 * s.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 45 + i % 3 * 18, 28 + i % 4 * 9),
          const Radius.circular(3),
        ),
        blocks,
      );
    }
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 13
      ..style = PaintingStyle.stroke;
    final line = Path()
      ..moveTo(-20, s.height * .72)
      ..cubicTo(
        s.width * .23,
        s.height * .55,
        s.width * .48,
        s.height * .68,
        s.width + 20,
        s.height * .25,
      );
    canvas.drawPath(line, road);
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFFF2C94C)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(
        Offset(
          math.Random(i).nextDouble() * s.width,
          math.Random(i + 9).nextDouble() * s.height,
        ),
        12,
        Paint()..color = const Color(0xFFBCD4C2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FormFieldBox extends StatelessWidget {
  const FormFieldBox(this.label, {super.key, this.hint, this.controller});
  final String label;
  final String? hint;
  final TextEditingController? controller;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label, hintText: hint),
  );
}

Future<void> showFormDialog(
  BuildContext context, {
  required String title,
  required List<Widget> fields,
  required String action,
  VoidCallback? onSave,
}) => showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              fields[i],
              if (i < fields.length - 1) const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          onSave?.call();
          Navigator.pop(context);
        },
        child: Text(action),
      ),
    ],
  ),
);
