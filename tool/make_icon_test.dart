// Genera el icono de la app (Android e iOS).
// Uso: flutter test tool/make_icon_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

enum Layer { full, background, foreground }

/// Fondo: oscuridad violácea con lluvia fina.
void paintBackground(Canvas c, double s) {
  final r = Rect.fromLTWH(0, 0, s, s);
  c.drawRect(
    r,
    Paint()
      ..shader = ui.Gradient.radial(Offset(s * 0.5, s * 0.62), s * 0.75,
          [const Color(0xFF2A1240), const Color(0xFF0C0614), const Color(0xFF030205)], [0, 0.55, 1]),
  );
  final rng = Random(3);
  final rain = Paint()
    ..color = const Color(0x22B8B0D8)
    ..strokeWidth = s * 0.003;
  for (var i = 0; i < 60; i++) {
    final x = rng.nextDouble() * s, y = rng.nextDouble() * s;
    c.drawLine(Offset(x, y), Offset(x - s * 0.01, y + s * 0.05), rain);
  }
}

/// Primer plano: la Caja de Otros Mundos abriéndose y dos ojos rojos acechando.
void paintForeground(Canvas c, double s) {
  final cx = s * 0.5;
  final top = s * 0.50; // centro de la cara superior
  final w = s * 0.30, h = s * 0.15, depth = s * 0.24;

  // Haz de luz violeta que sale de la caja
  final beam = Path()
    ..moveTo(cx - w * 0.75, top)
    ..lineTo(cx + w * 0.75, top)
    ..lineTo(cx + w * 1.6, s * 0.02)
    ..lineTo(cx - w * 1.6, s * 0.02)
    ..close();
  c.drawPath(
    beam,
    Paint()
      ..shader = ui.Gradient.linear(Offset(cx, top), Offset(cx, s * 0.02),
          [const Color(0xCCC77DFF), const Color(0x00B04CFF)]),
  );
  c.drawCircle(
    Offset(cx, top),
    s * 0.33,
    Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(Offset(cx, top), s * 0.33, [const Color(0x99B04CFF), const Color(0x00B04CFF)]),
  );

  // Caja isométrica
  final t = Offset(cx, top - h), rgt = Offset(cx + w, top), b = Offset(cx, top + h), lft = Offset(cx - w, top);
  final leftFace = Path()..addPolygon([lft, b, b + Offset(0, depth), lft + Offset(0, depth)], true);
  final rightFace = Path()..addPolygon([b, rgt, rgt + Offset(0, depth), b + Offset(0, depth)], true);
  c.drawPath(leftFace, Paint()..color = const Color(0xFF3A1F4A));
  c.drawPath(rightFace, Paint()..color = const Color(0xFF26132F));
  // Ribetes dorados
  final gold = Paint()
    ..color = const Color(0xFFD4AF37)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.012
    ..strokeJoin = StrokeJoin.round;
  c.drawPath(leftFace, gold);
  c.drawPath(rightFace, gold);
  // Runa en la cara frontal
  final rune = Paint()
    ..color = const Color(0xFFE6B3FF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.01;
  final rc = Offset(cx - w * 0.5, top + h * 0.5 + depth * 0.5);
  c.drawCircle(rc, s * 0.04, rune);
  c.drawLine(rc + Offset(0, -s * 0.065), rc + Offset(0, s * 0.065), rune);
  final rc2 = Offset(cx + w * 0.5, top + h * 0.5 + depth * 0.5);
  c.drawPath(
      Path()
        ..moveTo(rc2.dx - s * 0.04, rc2.dy + s * 0.04)
        ..lineTo(rc2.dx, rc2.dy - s * 0.05)
        ..lineTo(rc2.dx + s * 0.04, rc2.dy + s * 0.04),
      rune);
  // Boca de la caja: portal brillante
  final mouth = Path()..addPolygon([t, rgt, b, lft], true);
  c.drawPath(
    mouth,
    Paint()
      ..shader = ui.Gradient.radial(Offset(cx, top), w,
          [const Color(0xFFFFF0FF), const Color(0xFFD9A0FF), const Color(0xFF7A2AB8)], [0, 0.35, 1]),
  );
  c.drawPath(mouth, gold);
  // Tapa entreabierta, levantada hacia atrás
  final lidLift = s * 0.11;
  final lid = Path()
    ..addPolygon([
      t + Offset(0, -lidLift),
      rgt + Offset(0, -lidLift * 0.55),
      rgt + Offset(0, -lidLift * 0.55 - s * 0.035),
      t + Offset(0, -lidLift - s * 0.035),
      lft + Offset(0, -lidLift * 0.55 - s * 0.035),
      lft + Offset(0, -lidLift * 0.55),
    ], true);
  c.drawPath(lid, Paint()..color = const Color(0xFF2A1636));
  c.drawPath(lid, gold..strokeWidth = s * 0.009);

  // Ojos rojos en la oscuridad
  for (final (ex, ey, k) in [(0.24, 0.24, 1.0), (0.78, 0.30, 0.7)]) {
    for (final dx in [-0.035, 0.035]) {
      final o = Offset(s * (ex + dx * k), s * ey);
      c.drawCircle(
        o,
        s * 0.05 * k,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(o, s * 0.05 * k, [const Color(0x99FF1010), const Color(0x00FF1010)]),
      );
      c.drawOval(Rect.fromCenter(center: o, width: s * 0.03 * k, height: s * 0.016 * k),
          Paint()..color = const Color(0xFFFF4040));
    }
  }
}

Future<void> render(String path, int size, Layer layer, {double inset = 1}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final s = size.toDouble();
  if (layer != Layer.foreground) paintBackground(c, s);
  if (layer != Layer.background) {
    c.save();
    c.translate(s * (1 - inset) / 2, s * (1 - inset) / 2);
    paintForeground(c, s * inset);
    c.restore();
  }
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  testWidgets('icono', (tester) async {
    await tester.runAsync(() async {
      const res = 'android/app/src/main/res';
      const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final e in legacy.entries) {
        await render('$res/mipmap-${e.key}/ic_launcher.png', e.value, Layer.full);
        // Iconos adaptativos (Android 8+): 108dp con zona segura de 66dp.
        final a = e.value * 108 ~/ 48;
        await render('$res/mipmap-${e.key}/ic_launcher_foreground.png', a, Layer.foreground, inset: 0.62);
        await render('$res/mipmap-${e.key}/ic_launcher_background.png', a, Layer.background);
      }
      File('$res/mipmap-anydpi-v26/ic_launcher.xml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''');
      const ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final re = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png');
      for (final f in Directory(ios).listSync().whereType<File>()) {
        final m = re.firstMatch(f.uri.pathSegments.last);
        if (m == null) continue;
        final px = (double.parse(m.group(1)!) * int.parse(m.group(2)!)).round();
        await render(f.path, px, Layer.full);
      }
      await render('build/icon_preview.png', 512, Layer.full);
    });
  });
}
