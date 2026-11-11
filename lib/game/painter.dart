import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'fp_view.dart';
import 'game.dart';
import 'sprites.dart';
import 'thug_art.dart';
import 'world.dart';

class GamePainter extends CustomPainter {
  final Game g;
  GamePainter(this.g);

  static final Random _fx = Random();
  static final FpView _view = FpView();

  @override
  void paint(Canvas canvas, Size size) {
    final shake = g.shake > 0
        ? Offset((_fx.nextDouble() * 2 - 1) * g.shake, (_fx.nextDouble() * 2 - 1) * g.shake)
        : Offset.zero;
    _view.paint(canvas, size, g, shake);
    if (g.fi == roofFloor) _drawRain(canvas, size);
    _drawScreenFx(canvas, size, false);
  }

  /// Lluvia en diagonal sobre la azotea, con salpicaduras en el suelo.
  void _drawRain(Canvas canvas, Size size) {
    final t = g.time;
    final streak = Paint()
      ..color = const Color(0x55A8C0E0)
      ..strokeWidth = 1.5;
    const n = 140;
    for (var i = 0; i < n; i++) {
      final h1 = ((i * 2654435761) & 0xFFFF) / 0xFFFF;
      final h2 = ((i * 40503 + 12345) & 0xFFFF) / 0xFFFF;
      final speed = 900 + h1 * 500;
      final y = (h2 * size.height + t * speed) % (size.height + 40) - 20;
      final x = (h1 * size.width * 1.2 - y * 0.25 + t * 40) % size.width;
      final len = 14 + h2 * 16;
      canvas.drawLine(Offset(x, y), Offset(x - len * 0.25, y - len), streak);
    }
    // Salpicaduras: anillos que se abren y desaparecen.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 40; i++) {
      final phase = (t * 2.5 + i * 0.137) % 1;
      final slot = ((t * 2.5 + i * 0.137).floor() * 7919 + i * 104729) & 0xFFFF;
      final x = (slot % 997) / 997 * size.width;
      final y = size.height * (0.56 + 0.44 * ((slot * 31) % 991) / 991); // solo sobre el suelo
      ring.color = Color.fromRGBO(170, 195, 230, 0.35 * (1 - phase));
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 4 + phase * 16, height: 2 + phase * 7), ring);
    }
  }

  // --- Efectos de pantalla ------------------------------------------------------

  void _drawScreenFx(Canvas canvas, Size size, bool alive) {
    final full = Offset.zero & size;
    final p = g.p;

    // Viñeta.
    {
      canvas.drawRect(
        full,
        Paint()
          ..shader = ui.Gradient.radial(
            size.center(Offset.zero),
            size.longestSide * 0.62,
            [const Color(0x00000000), Color.fromRGBO(0, 0, 0, alive ? 0.25 : 0.85)],
            [0.45, 1],
          ),
      );
    }

    // Viñeta roja con poca salud o energía.
    final danger = min(p.hp, p.energy * 1.5);
    if (danger < 4 && !g.won) {
      final beat = pow((sin(g.time * (6 + (4 - danger))) + 1) / 2, 3).toDouble();
      final a = (0.25 + 0.35 * (1 - danger / 4)) * (0.5 + 0.5 * beat);
      canvas.drawRect(
        full,
        Paint()
          ..shader = ui.Gradient.radial(size.center(Offset.zero), size.longestSide * 0.6,
              [const Color(0x00FF0000), Color.fromRGBO(170, 0, 0, a)], [0.35, 1]),
      );
    }
    if (p.darkWound && !g.won) {
      final a = 0.25 + 0.15 * sin(g.time * 2);
      canvas.drawRect(
        full,
        Paint()
          ..shader = ui.Gradient.radial(size.center(Offset.zero), size.longestSide * 0.6,
              [const Color(0x00400060), Color.fromRGBO(70, 0, 110, a)], [0.5, 1]),
      );
    }

    if (g.redFlash > 0) {
      canvas.drawRect(full, Paint()..color = Color.fromRGBO(200, 0, 0, (g.redFlash * 0.55).clamp(0.0, 1.0)));
    }
    // Con las gafas puestas todo se ve ámbar.
    if (p.wearingGlasses && !g.won) {
      canvas.drawRect(full, Paint()..color = const Color(0x30FFA020));
    }
    final boss = g.floor.boss;
    if (boss != null && boss.alive) _drawBossBar(canvas, size, boss);

    // Grano de película.
    if (!alive) {
      final gp = Paint();
      for (var i = 0; i < 140; i++) {
        gp.color = Color.fromRGBO(255, 255, 255, 0.03 + _fx.nextDouble() * 0.05);
        canvas.drawRect(
            Rect.fromLTWH(_fx.nextDouble() * size.width, _fx.nextDouble() * size.height, 2, 2), gp);
      }
    }

    if (g.glitch > 0) {
      final gp = Paint();
      for (var i = 0; i < 12; i++) {
        final y = _fx.nextDouble() * size.height;
        gp.color = [const Color(0x6600FF80), const Color(0x66FF0040), const Color(0x55FFFFFF)][i % 3];
        canvas.drawRect(Rect.fromLTWH(_fx.nextDouble() * 40 - 20, y, size.width, 3 + _fx.nextDouble() * 12), gp);
      }
    }

    if (g.hiding != null) _drawHidingView(canvas, size);
    _drawSearchPanel(canvas, size);

    if (g.faceScare > 0) _drawFace(canvas, size);

    if (g.bigTextT > 0 && g.bigText != null) {
      final a = min(1.0, g.bigTextT * 2);
      final jit = Offset((_fx.nextDouble() - 0.5) * 6, (_fx.nextDouble() - 0.5) * 6);
      final tp = TextPainter(
        text: TextSpan(
          text: g.bigText,
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w900,
            fontSize: size.shortestSide * 0.11,
            letterSpacing: 4,
            color: g.bigTextColor.withValues(alpha: a),
            shadows: [Shadow(color: Colors.black.withValues(alpha: a), blurRadius: 12)],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: size.width * 0.9);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height * 0.3 - tp.height / 2) + jit);
    }

    if (g.transition > 0) {
      final k = 1 - (g.transition - 0.45).abs() / 0.45;
      canvas.drawRect(full, Paint()..color = Color.fromRGBO(0, 0, 0, k.clamp(0.0, 1.0)));
    }

    if (g.whiteFlash > 0) {
      canvas.drawRect(full, Paint()..color = Color.fromRGBO(255, 250, 235, min(1.0, g.whiteFlash)));
    }
  }

  void _drawBossBar(Canvas canvas, Size size, Boss b) {
    final w = size.width * 0.4;
    final r = Rect.fromLTWH((size.width - w) / 2, 62, w, 10);
    canvas.drawRect(r.inflate(2), Paint()..color = const Color(0xCC000000));
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width * b.hp / bossHp, r.height), Paint()..color = const Color(0xFFB01010));
    final tp = TextPainter(
      text: const TextSpan(
        text: 'EL CARNICERO',
        style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 3, color: Color(0xFFFF6060)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, r.top - tp.height - 4));
  }

  /// Desde dentro del escondite: rendijas de la taquilla o la cortina del probador.
  void _drawHidingView(Canvas canvas, Size size) {
    final h = g.hiding!;
    final dark = Paint()..color = const Color(0xF2050505);
    if (h.kind == 0) {
      final slot = size.height / 9;
      for (var i = 0; i < 9; i++) {
        final y = i * slot;
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, slot * 0.6), dark);
      }
    } else {
      final w = size.width * 0.38;
      for (final left in [true, false]) {
        final r = left ? Rect.fromLTWH(0, 0, w, size.height) : Rect.fromLTWH(size.width - w, 0, w, size.height);
        canvas.drawRect(
          r,
          Paint()
            ..shader = ui.Gradient.linear(
              left ? r.centerLeft : r.centerRight,
              left ? r.centerRight : r.centerLeft,
              [const Color(0xF8200A18), const Color(0xF03A1A30), const Color(0x803A1A30)],
              [0, 0.85, 1],
            ),
        );
        // Pliegues de la cortina
        final fold = Paint()..color = const Color(0x40000000);
        for (var x = 0.0; x < w; x += w / 6) {
          final fx = left ? x : size.width - x;
          canvas.drawRect(Rect.fromLTWH(fx, 0, w / 24, size.height), fold);
        }
      }
    }
    final tp = TextPainter(
      text: TextSpan(
        text: g.hidingSeen ? 'TE HAN VISTO ENTRAR' : 'ESCONDIDO',
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          fontSize: 14,
          letterSpacing: 3,
          color: g.hidingSeen ? const Color(0xFFFF5050) : const Color(0x99FFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height * 0.12));
  }

  /// Animación al registrar: cosas que salen volando y, al final, lo encontrado.
  void _drawSearchPanel(Canvas canvas, Size size) {
    final searching = g.searching;
    final res = g.searchResult;
    if (searching == null && res == null) return;
    final sp = Sprites.i;
    final kind = searching?.kind ?? res!.kind;
    final fade = res == null ? 1.0 : (1 - (res.t - 1.4) / 0.4).clamp(0.0, 1.0);
    final panel = Rect.fromCenter(center: Offset(size.width / 2, size.height - 150), width: 380, height: 150);
    canvas.drawRRect(RRect.fromRectAndRadius(panel, const Radius.circular(6)),
        Paint()..color = Color.fromRGBO(12, 12, 16, 0.88 * fade));
    canvas.drawRRect(
        RRect.fromRectAndRadius(panel, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Color.fromRGBO(90, 80, 60, fade));

    void text(String s, Offset at, double fs, Color c) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: fs, color: c.withValues(alpha: fade)),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: panel.width - 20);
      tp.paint(canvas, at - Offset(tp.width / 2, 0));
    }

    // El mueble, que tiembla mientras rebuscas.
    final shakeX = searching != null ? sin(g.time * 45) * 2.5 : 0.0;
    final cratePos = Offset(panel.left + 75 + shakeX, panel.bottom - 22);
    sp.crates[kind].draw(canvas, cratePos, kind == carCrate ? 45 : 90, anchorY: 1, opacity: fade);

    if (searching != null) {
      final k = (g.searchT / Game.searchTime).clamp(0.0, 1.0);
      text('Registrando ${crateNames[kind]}...', Offset(panel.center.dx + 40, panel.top + 10), 13, const Color(0xFFCCCCCC));
      // Trastos que salen volando por encima del hombro.
      final origin = Offset(panel.left + 80, panel.top + 70);
      for (var i = 0; i < 6; i++) {
        final ph = (g.searchT * 1.3 + i / 6) % 1;
        final pos = origin + Offset(30 + ph * 230, -sin(ph * pi) * 55 + ph * 30);
        final a = (1 - ph).clamp(0.0, 1.0);
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(ph * 7 + i);
        final p = Paint();
        switch (i % 4) {
          case 0: // papel arrugado
            p.color = Color.fromRGBO(220, 215, 195, a);
            canvas.drawRect(const Rect.fromLTWH(-8, -6, 16, 12), p);
          case 1: // lata
            p.color = Color.fromRGBO(140, 140, 150, a);
            canvas.drawRect(const Rect.fromLTWH(-5, -8, 10, 16), p);
            p.color = Color.fromRGBO(180, 40, 40, a);
            canvas.drawRect(const Rect.fromLTWH(-5, -3, 10, 6), p);
          case 2: // botella vacía
            p.color = Color.fromRGBO(60, 130, 80, a * 0.8);
            canvas.drawRect(const Rect.fromLTWH(-4, -10, 8, 18), p);
            canvas.drawRect(const Rect.fromLTWH(-2, -14, 4, 5), p);
          default: // trapo
            p.color = Color.fromRGBO(110, 80, 60, a);
            canvas.drawRect(const Rect.fromLTWH(-9, -4, 18, 8), p);
        }
        canvas.restore();
      }
      final bar = Rect.fromLTWH(panel.left + 150, panel.bottom - 22, panel.width - 170, 8);
      canvas.drawRect(bar, Paint()..color = const Color(0xFF222222));
      canvas.drawRect(Rect.fromLTWH(bar.left, bar.top, bar.width * k, bar.height), Paint()..color = const Color(0xFFE8C468));
      return;
    }

    final r = res!;
    final center = Offset(panel.left + 255, panel.center.dy - 8);
    if (r.rat) {
      // La rata salta hacia la cara.
      final k = (r.t / 0.45).clamp(0.0, 1.0);
      final scale = 60 + k * 340;
      final pos = Offset.lerp(cratePos - const Offset(0, 50), Offset(size.width / 2, size.height / 2), k)!;
      final jit = Offset((_fx.nextDouble() - 0.5) * 8, (_fx.nextDouble() - 0.5) * 8);
      sp.icons['rat']!.draw(canvas, pos + jit, scale, opacity: fade * (r.t < 0.9 ? 1 : (1.4 - r.t).clamp(0.0, 1.0) * 2));
      text('¡UNA RATA!', Offset(center.dx, panel.top + 12), 18, const Color(0xFFFF7070));
      return;
    }
    if (r.item == null) {
      // Polvo.
      for (var i = 0; i < 10; i++) {
        final a = i * 0.63;
        final d = 10 + r.t * 50;
        canvas.drawCircle(center + Offset(cos(a), sin(a)) * d, 6 + r.t * 8,
            Paint()..color = Color.fromRGBO(140, 135, 125, (0.35 * (1 - r.t / 1.8)).clamp(0.0, 1.0) * fade));
      }
      text('Vacío', Offset(center.dx, center.dy - 10), 22, const Color(0xFF888888));
      return;
    }
    // Objeto encontrado: aparece con un destello y rayos girando.
    final pop = r.t < 0.35 ? 0.3 + 0.95 * sin(r.t / 0.35 * pi / 2) + 0.15 * sin(r.t / 0.35 * pi) : 1.0;
    final rays = Paint()..color = Color.fromRGBO(255, 225, 140, 0.18 * fade);
    for (var i = 0; i < 10; i++) {
      final a = g.time * 0.8 + i * pi / 5;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + cos(a - 0.12) * 70, center.dy + sin(a - 0.12) * 70)
        ..lineTo(center.dx + cos(a + 0.12) * 70, center.dy + sin(a + 0.12) * 70)
        ..close();
      canvas.drawPath(path, rays);
    }
    canvas.drawCircle(
      center,
      45,
      Paint()
        ..shader = ui.Gradient.radial(center, 45, [Color.fromRGBO(255, 230, 160, 0.45 * fade), const Color(0x00FFE6A0)]),
    );
    final icon = itemInfo[r.item]!.icon;
    if (sp.icons[icon] != null) {
      sp.icons[icon]!.draw(canvas, center, 64 * pop, opacity: fade);
    } else {
      ThugArt.drawIcon(canvas, icon, center, 80 * pop, opacity: fade);
    }
    text('¡${itemInfo[r.item]!.name}!', Offset(center.dx, panel.bottom - 30), 17, const Color(0xFFE8C468));
  }

  /// Cara pixelada del susto.
  void _drawFace(Canvas canvas, Size size) {
    const n = 32;
    final a = min(1.0, g.faceScare * 3);
    final scale = 1 + (0.7 - g.faceScare) * 0.6 + _fx.nextDouble() * 0.05;
    final cell = size.height / n * scale;
    final origin = Offset(size.width / 2 - cell * n / 2 + (_fx.nextDouble() - 0.5) * 20,
        size.height / 2 - cell * n / 2 + (_fx.nextDouble() - 0.5) * 20);
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, a));
    final paint = Paint()..isAntiAlias = false;
    final r = Random(13);
    bool inEll(double u, double v, double cx, double cy, double rx, double ry) =>
        pow((u - cx) / rx, 2) + pow((v - cy) / ry, 2) <= 1;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final u = (x + 0.5) / n, v = (y + 0.5) / n;
        Color? c;
        if (inEll(u, v, 0.5, 0.52, 0.3, 0.44)) {
          final shade = 0.75 + r.nextDouble() * 0.25 - (u - 0.5).abs() * 0.6;
          c = Color.fromRGBO((216 * shade).round(), (205 * shade).round(), (190 * shade).round(), 1);
          if (inEll(u, v, 0.37, 0.42, 0.08, 0.1) || inEll(u, v, 0.63, 0.42, 0.08, 0.1)) {
            c = const Color(0xFF000000);
            if (inEll(u, v, 0.37, 0.43, 0.02, 0.025) || inEll(u, v, 0.63, 0.43, 0.02, 0.025)) {
              c = const Color(0xFFFF1010);
            }
          }
          if (inEll(u, v, 0.5, 0.74, 0.09, 0.17)) {
            c = const Color(0xFF0A0000);
            if (v < 0.62 && x % 2 == 0) c = const Color(0xFFE8E0C8);
          }
          if ((x == 11 && y > 18 && y < 25) || (y == 9 && x > 17 && x < 22) || (x == 21 && y > 22 && y < 27)) {
            c = const Color(0xFF3A2A20);
          }
        }
        if (c == null) continue;
        paint.color = c.withValues(alpha: a);
        canvas.drawRect(Rect.fromLTWH(origin.dx + x * cell, origin.dy + y * cell, cell + 0.5, cell + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
