import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';

enum EditMode { select, draw }

/// Foto parkiran dengan kotak slot di atasnya.
///
/// Semua koordinat (slot, mobil) memakai piksel foto asli, sama seperti yang
/// dipakai YOLO di backend; widget ini yang mengubahnya ke ukuran layar.
class SlotCanvas extends StatefulWidget {
  const SlotCanvas({
    super.key,
    required this.imageUrl,
    required this.imageSize,
    required this.slots,
    required this.selected,
    required this.mode,
    required this.onSelect,
    required this.onAdd,
    required this.onChange,
    this.statuses,
    this.cars = const [],
    this.imageBytes,
    this.readOnly = false,
    this.mono = false,
  });

  /// Tampilan hasil untuk pengunjung: tanpa gestur, warna monokrom sesuai wireframe.
  const SlotCanvas.result({
    super.key,
    required this.imageSize,
    required this.slots,
    required List<String> this.statuses,
    this.imageUrl = '',
    this.imageBytes,
  }) : selected = null,
       mode = EditMode.select,
       onSelect = _noSelect,
       onAdd = _noAdd,
       onChange = _noChange,
       cars = const [],
       readOnly = true,
       mono = true;

  static void _noSelect(int? _) {}
  static void _noAdd(Rect _) {}
  static void _noChange(int _, Rect _) {}

  final String imageUrl;
  final Uint8List? imageBytes;
  final bool readOnly;
  final bool mono;
  final Size imageSize;
  final List<Slot> slots;
  final int? selected;
  final EditMode mode;
  final List<String>? statuses;
  final List<Rect> cars;
  final ValueChanged<int?> onSelect;
  final ValueChanged<Rect> onAdd;
  final void Function(int index, Rect rect) onChange;

  @override
  State<SlotCanvas> createState() => _SlotCanvasState();
}

enum _Drag { none, draw, move, resize }

class _SlotCanvasState extends State<SlotCanvas> {
  static const _handleRadius = 10.0; // dalam piksel layar
  static const _minSize = 4.0; // dalam piksel foto

  double _scale = 1;
  _Drag _drag = _Drag.none;
  Offset _start = Offset.zero;
  Offset _current = Offset.zero;
  Rect _rectAtStart = Rect.zero;
  Offset _fixedCorner = Offset.zero;
  int? _dragIndex;

  Offset _toImage(Offset local) => Offset(
    (local.dx / _scale).clamp(0, widget.imageSize.width),
    (local.dy / _scale).clamp(0, widget.imageSize.height),
  );

  int? _slotAt(Offset p) {
    for (var i = widget.slots.length - 1; i >= 0; i--) {
      if (widget.slots[i].rect.contains(p)) return i;
    }
    return null;
  }

  List<Offset> _corners(Rect r) => [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];

  void _onPanStart(DragStartDetails d) {
    final p = _toImage(d.localPosition);
    _start = _current = p;
    if (widget.mode == EditMode.draw) {
      setState(() => _drag = _Drag.draw);
      return;
    }
    final sel = widget.selected;
    if (sel != null && sel < widget.slots.length) {
      final rect = widget.slots[sel].rect;
      final corners = _corners(rect);
      for (var c = 0; c < 4; c++) {
        if ((corners[c] - p).distance <= _handleRadius / _scale) {
          _drag = _Drag.resize;
          _dragIndex = sel;
          _fixedCorner = corners[3 - c];
          return;
        }
      }
      if (rect.contains(p)) {
        _drag = _Drag.move;
        _dragIndex = sel;
        _rectAtStart = rect;
        return;
      }
    }
    final hit = _slotAt(p);
    if (hit != null) {
      widget.onSelect(hit);
      _drag = _Drag.move;
      _dragIndex = hit;
      _rectAtStart = widget.slots[hit].rect;
    } else {
      _drag = _Drag.none;
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final p = _toImage(d.localPosition);
    final size = widget.imageSize;
    switch (_drag) {
      case _Drag.draw:
        setState(() => _current = p);
      case _Drag.move:
        var r = _rectAtStart.shift(p - _start);
        final dx = r.left < 0 ? -r.left : (r.right > size.width ? size.width - r.right : 0.0);
        final dy = r.top < 0 ? -r.top : (r.bottom > size.height ? size.height - r.bottom : 0.0);
        r = r.shift(Offset(dx, dy));
        widget.onChange(_dragIndex!, r);
      case _Drag.resize:
        final r = Rect.fromPoints(_fixedCorner, p);
        if (r.width >= _minSize && r.height >= _minSize) widget.onChange(_dragIndex!, r);
      case _Drag.none:
        break;
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_drag == _Drag.draw) {
      final r = Rect.fromPoints(_start, _current);
      if (r.width >= _minSize && r.height >= _minSize) widget.onAdd(r);
    }
    setState(() {
      _drag = _Drag.none;
      _dragIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final img = widget.imageSize;
        _scale = [constraints.maxWidth / img.width, constraints.maxHeight / img.height].reduce((a, b) => a < b ? a : b);
        final display = Size(img.width * _scale, img.height * _scale);
        return Center(
          child: MouseRegion(
            cursor: widget.mode == EditMode.draw ? SystemMouseCursors.precise : SystemMouseCursors.basic,
            child: GestureDetector(
              // Posisi awal geser = titik mouse ditekan, bukan titik saat geser dikenali,
              // supaya sudut slot tepat kena dan kotak mengikuti kursor.
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: !widget.readOnly && widget.mode == EditMode.select
                  ? (d) => widget.onSelect(_slotAt(_toImage(d.localPosition)))
                  : null,
              onPanStart: widget.readOnly ? null : _onPanStart,
              onPanUpdate: widget.readOnly ? null : _onPanUpdate,
              onPanEnd: widget.readOnly ? null : _onPanEnd,
              child: SizedBox.fromSize(
                size: display,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.imageBytes != null)
                      Image.memory(widget.imageBytes!, fit: BoxFit.fill)
                    else
                      Image.network(
                        widget.imageUrl,
                        fit: BoxFit.fill,
                        loadingBuilder: (_, child, progress) =>
                            progress == null ? child : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (_, _, _) => const Center(child: Text('Foto gagal dimuat')),
                      ),
                    CustomPaint(
                      painter: _SlotPainter(
                        scale: _scale,
                        slots: widget.slots,
                        selected: widget.selected,
                        statuses: widget.statuses,
                        cars: widget.cars,
                        drawing: _drag == _Drag.draw ? Rect.fromPoints(_start, _current) : null,
                        handleRadius: _handleRadius,
                        mono: widget.mono,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SlotPainter extends CustomPainter {
  _SlotPainter({
    required this.scale,
    required this.slots,
    required this.selected,
    required this.statuses,
    required this.cars,
    required this.drawing,
    required this.handleRadius,
    this.mono = false,
  });

  final bool mono;
  final double scale;
  final List<Slot> slots;
  final int? selected;
  final List<String>? statuses;
  final List<Rect> cars;
  final Rect? drawing;
  final double handleRadius;

  static const _neutral = Color(0xFF3B6EF0);
  static const _car = Color(0xFF00B8D9);

  Rect _toScreen(Rect r) => Rect.fromLTRB(r.left * scale, r.top * scale, r.right * scale, r.bottom * scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (mono) {
      _paintMono(canvas);
      return;
    }
    final carPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _car.withValues(alpha: 0.9);
    for (final car in cars) {
      canvas.drawRect(_toScreen(car), carPaint);
    }

    for (var i = 0; i < slots.length; i++) {
      final isSelected = i == selected;
      final status = statuses != null && i < statuses!.length ? statuses![i] : null;
      final color = statusColors[status] ?? _neutral;
      final r = _toScreen(slots[i].rect);
      canvas.drawRect(r, Paint()..color = color.withValues(alpha: isSelected ? 0.35 : 0.18));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3 : 2
          ..color = color,
      );
      _label(canvas, slots[i].label, r.topLeft, color);
      if (isSelected) {
        for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
          final h = Rect.fromCenter(center: c, width: handleRadius, height: handleRadius);
          canvas.drawRect(h, Paint()..color = Colors.white);
          canvas.drawRect(
            h,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = color,
          );
        }
      }
    }

    final d = drawing;
    if (d != null) {
      final r = _toScreen(d);
      canvas.drawRect(r, Paint()..color = _neutral.withValues(alpha: 0.2));
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _neutral,
      );
    }
  }

  /// Gaya wireframe: terisi = gelap, kosong = putih, anomali = putih dengan tanda "!".
  void _paintMono(Canvas canvas) {
    const ink = Color(0xFF262626);
    for (var i = 0; i < slots.length; i++) {
      final status = statuses != null && i < statuses!.length ? statuses![i] : 'empty';
      final r = _toScreen(slots[i].rect);
      final occupied = status == 'occupied';
      canvas.drawRect(r, Paint()..color = (occupied ? ink : Colors.white).withValues(alpha: occupied ? 0.55 : 0.3));
      canvas.drawRect(
        r.inflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = occupied ? Colors.white : ink,
      );
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = occupied ? ink : Colors.white,
      );
      final text = status == 'anomaly' ? '! ${slots[i].label}' : slots[i].label;
      _label(canvas, text, r.topLeft, occupied ? ink : Colors.white, textColor: occupied ? Colors.white : ink);
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color, {Color textColor = Colors.white}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bg = Rect.fromLTWH(at.dx, at.dy - tp.height - 2, tp.width + 6, tp.height + 2);
    final box = bg.top < 0 ? bg.shift(Offset(0, -bg.top)) : bg;
    canvas.drawRect(box, Paint()..color = color);
    tp.paint(canvas, box.topLeft + const Offset(3, 1));
  }

  @override
  bool shouldRepaint(covariant _SlotPainter old) => true;
}
