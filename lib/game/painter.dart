import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'game.dart';
import 'sprites.dart';
import 'world.dart';

class GamePainter extends CustomPainter {
  final Game g;
  GamePainter(this.g);

  static final Map<int, TileSet> _tileSets = {};
  static final Random _fx = Random();

  late Size _size;
  late double _s;
  late Offset _cam;
  late Offset _shakeOff;

  Offset toScreen(Offset w) => (w - _cam) * _s + Offset(_size.width / 2, _size.height / 2) + _shakeOff;

  @override
  void paint(Canvas canvas, Size size) {
    _size = size;
    // El final ya no es el centro comercial que revive, sino la huida de noche.
    final alive = g.won && g.endT > 0.8 && g.fi != roofFloor;
    final darkA = g.fi == roofFloor ? 0.72 : 1.0;
    final ts = _tileSets.putIfAbsent(
      alive ? 100 + g.fi : g.fi,
      () => TileSet.build(alive ? alivePalette : darkPalettes[g.fi], 1000 + g.fi * 17, alive: alive),
    );
    _s = size.shortestSide / 12 * (1 + 0.35 * g.zoomPunch * g.zoomPunch);
    _cam = g.p.pos;
    _shakeOff = g.shake > 0
        ? Offset((_fx.nextDouble() * 2 - 1) * g.shake, (_fx.nextDouble() * 2 - 1) * g.shake)
        : Offset.zero;

    _paintWorld(canvas, size, ts, alive, darkA);
    _drawScreenFx(canvas, size, alive);
  }

  void _paintWorld(Canvas canvas, Size size, TileSet ts, bool alive, double darkA) {
    canvas.drawRect(Offset.zero & size, Paint()..color = alive ? const Color(0xFF7FB8C9) : Colors.black);

    canvas.save();
    canvas.translate(size.width / 2 + _shakeOff.dx, size.height / 2 + _shakeOff.dy);
    canvas.scale(_s);
    canvas.translate(-_cam.dx, -_cam.dy);

    final hw = size.width / 2 / _s + 1.5, hh = size.height / 2 / _s + 1.5;
    final view = Rect.fromLTRB(_cam.dx - hw, _cam.dy - hh, _cam.dx + hw, _cam.dy + hh);

    _drawTiles(canvas, ts, view);
    _drawHelipad(canvas, view);
    _drawRubble(canvas, view, alive);
    if (!alive) _drawDecals(canvas, view);
    _drawObjects(canvas, view, alive);

    if (darkA > 0) _drawDarkness(canvas, view, darkA);
    _drawEmissive(canvas, view, alive);
    _drawHelicopter(canvas);

    canvas.restore();

    _drawSigns(canvas, view, alive);
    if (g.fi == roofFloor) _drawRain(canvas, size);
  }

  /// Motas de polvo flotando, visibles solo dentro del haz de la linterna.
  void _drawDust(Canvas canvas) {
    final cone = g.conePoly;
    if (cone.isEmpty || g.hiding != null || g.flashPower < 0.1) return;
    final p = g.p;
    final reach = g.coneLen;
    canvas.save();
    canvas.clipPath(Path()..addPolygon(cone, true));
    final paint = Paint()..blendMode = BlendMode.plus;
    final t = g.time;
    final x0 = (p.pos.dx - reach).floor(), x1 = (p.pos.dx + reach).ceil();
    final y0 = (p.pos.dy - reach).floor(), y1 = (p.pos.dy + reach).ceil();
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        for (var k = 0; k < 2; k++) {
          // Pseudoaleatorio estable por casilla: cada mota deriva despacio en su sitio.
          final h = ((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFFFF;
          final a = (h & 0xFF) / 255, b = ((h >> 8) & 0xFF) / 255, c = ((h >> 16) & 0xFF) / 255;
          final pos = Offset(
            x + (a + sin(t * (0.2 + c * 0.3) + c * 6) * 0.25) % 1,
            y + (b + t * (0.03 + a * 0.05)) % 1,
          );
          final d = (pos - p.pos).distance;
          if (d > reach) continue;
          final twinkle = 0.5 + 0.5 * sin(t * (1 + b * 2) + a * 9);
          final alpha = (1 - d / reach) * 0.55 * twinkle * g.flashPower;
          if (alpha < 0.03) continue;
          paint.color = Color.fromRGBO(255, 245, 220, alpha);
          final sz = 0.035 + c * 0.03;
          canvas.drawRect(Rect.fromCenter(center: pos, width: sz, height: sz), paint);
        }
      }
    }
    canvas.restore();
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
      final y = ((slot * 31) % 991) / 991 * size.height;
      ring.color = Color.fromRGBO(170, 195, 230, 0.35 * (1 - phase));
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 4 + phase * 16, height: 2 + phase * 7), ring);
    }
  }

  // --- Mundo -----------------------------------------------------------------

  void _drawTiles(Canvas canvas, TileSet ts, Rect view) {
    final f = g.floor;
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    const src = Rect.fromLTWH(0, 0, 16, 16);
    for (var y = max(0, view.top.floor()); y <= min(mapH - 1, view.bottom.ceil()); y++) {
      for (var x = max(0, view.left.floor()); x <= min(mapW - 1, view.right.ceil()); x++) {
        final t = f.at(x, y);
        final h = (x * 73856093) ^ (y * 19349663);
        final Sprite sp;
        switch (t) {
          case Tile.wall:
            final below = f.at(x, y + 1);
            if (below == Tile.wall || y == mapH - 1) {
              sp = ts.wallTop;
            } else {
              sp = ts.wallFace[below == Tile.shop ? 1 : 0];
            }
          case Tile.floor:
          case Tile.car:
            sp = ts.floor[h.abs() % 3];
          case Tile.elevator:
            sp = ts.elevator;
          case Tile.shop:
            sp = ts.shop[h.abs() % 2];
          case Tile.stairUp:
            sp = ts.stairUp;
          case Tile.stairDown:
            sp = ts.stairDown;
        }
        canvas.drawImageRect(sp.image, src, Rect.fromLTWH(x - 0.005, y - 0.005, 1.01, 1.01), paint);
      }
    }
  }

  void _drawRubble(Canvas canvas, Rect view, bool alive) {
    final paint = Paint()..isAntiAlias = false;
    for (final c in g.floor.rubble) {
      if (!view.contains(Offset(c.x + 0.5, c.y + 0.5))) continue;
      final r = Random(c.x * 977 + c.y * 31);
      paint.color = alive ? const Color(0xFFB0A898) : const Color(0xFF2A2622);
      canvas.drawRect(Rect.fromLTWH(c.x.toDouble(), c.y.toDouble(), 1, 1), paint);
      for (var i = 0; i < 7; i++) {
        final x = c.x + r.nextDouble() * 0.8, y = c.y + r.nextDouble() * 0.8;
        final w = 0.15 + r.nextDouble() * 0.35, h = 0.1 + r.nextDouble() * 0.25;
        paint.color = [const Color(0xFF4A4038), const Color(0xFF5A5650), const Color(0xFF3A2A1C), const Color(0xFF6A6A70)][r.nextInt(4)];
        if (alive) paint.color = Color.lerp(paint.color, Colors.white, 0.5)!;
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
      }
      // Tablón cruzado
      paint
        ..color = alive ? const Color(0xFFD9A066) : const Color(0xFF5A3E26)
        ..strokeWidth = 0.08;
      canvas.drawLine(Offset(c.x + 0.05, c.y + 0.2 + r.nextDouble() * 0.3), Offset(c.x + 0.95, c.y + 0.5 + r.nextDouble() * 0.4), paint);
    }
  }

  void _drawDecals(Canvas canvas, Rect view) {
    final paint = Paint()..isAntiAlias = false;
    for (final d in g.floor.decals) {
      if (!view.contains(d.pos)) continue;
      final r = Random(d.seed);
      switch (d.kind) {
        case 0:
          paint.color = const Color(0xAA4A0606);
          for (var i = 0; i < 5; i++) {
            final o = Offset(r.nextDouble() - 0.5, r.nextDouble() - 0.5) * d.size * 0.6;
            final px = d.size * (0.12 + r.nextDouble() * 0.15);
            canvas.drawRect(Rect.fromCenter(center: d.pos + o, width: px * 1.4, height: px), paint);
          }
        case 1:
          paint.color = const Color(0x66C8D8E0);
          for (var i = 0; i < 6; i++) {
            final o = Offset(r.nextDouble() - 0.5, r.nextDouble() - 0.5) * d.size;
            canvas.drawRect(Rect.fromCenter(center: d.pos + o, width: 0.05, height: 0.05), paint);
          }
        case 2:
          paint.color = const Color(0x55D8D0B8);
          canvas.save();
          canvas.translate(d.pos.dx, d.pos.dy);
          canvas.rotate(d.rot);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: d.size * 0.5, height: d.size * 0.35), paint);
          canvas.restore();
        default:
          const cols = [Color(0x66FF2D6F), Color(0x6630E0A0), Color(0x66E8E030)];
          paint.color = cols[d.seed % 3];
          for (var i = 0; i < 7; i++) {
            final o = Offset(i * 0.08 - 0.28, sin(i * 1.3 + d.seed) * 0.08);
            canvas.drawRect(Rect.fromCenter(center: d.pos + o, width: 0.07, height: 0.07), paint);
          }
      }
    }
  }

  Sprite _dirSprite(double angle, Sprite down, Sprite up, Sprite side, List<bool> flip) {
    final c = cos(angle), s = sin(angle);
    if (c.abs() > s.abs()) {
      flip[0] = c < 0;
      return side;
    }
    flip[0] = false;
    return s > 0 ? down : up;
  }

  /// Cae de lado desde los pies en 0,35 s.
  void _drawFall(Canvas canvas, Sprite s, Offset feet, double width, double t, bool right, double opacity) {
    final k = Curves.easeIn.transform((t / 0.35).clamp(0.0, 1.0));
    final bounce = t > 0.35 && t < 0.5 ? sin((t - 0.35) / 0.15 * pi) * 0.04 : 0.0;
    canvas.save();
    canvas.translate(feet.dx, feet.dy - bounce);
    canvas.rotate((right ? -1 : 1) * k * pi / 2);
    s.draw(canvas, Offset.zero, width, anchorY: 1, flipX: !right, opacity: opacity);
    canvas.restore();
  }

  /// Pistola en la mano, apuntando; con retroceso justo después del disparo.
  /// [aim]: la de un sicario a punto de disparar, con el destello rojo de aviso.
  void _drawGun(Canvas canvas, Offset feet, double angle, double recoil, {bool aim = false}) {
    final dir = Offset(cos(angle), sin(angle));
    final hand = feet + const Offset(0, -0.4) + dir * (0.28 - recoil * 0.08);
    canvas.save();
    canvas.translate(hand.dx, hand.dy);
    canvas.rotate(angle - recoil * 0.35);
    canvas.drawRect(const Rect.fromLTWH(0, -0.04, 0.26, 0.08), Paint()..color = const Color(0xFF1A1A1E));
    canvas.drawRect(const Rect.fromLTWH(0.02, -0.04, 0.06, 0.14), Paint()..color = const Color(0xFF2A2A30));
    canvas.restore();
    if (aim && (g.time * 8).floor() % 2 == 0) {
      canvas.drawCircle(hand + dir * 0.3, 0.05, Paint()..color = const Color(0xFFFF3030));
    }
  }

  /// Barra de hierro al hombro; al golpear, barre un arco delante.
  void _drawPipe(Canvas canvas, Offset feet, double angle, double swing) {
    final hand = feet + const Offset(0, -0.4) + Offset(cos(angle), sin(angle)) * 0.2;
    final a = swing > 0 ? angle + (swing - 0.5) * 2.2 : angle - 1.1;
    final tip = hand + Offset(cos(a), sin(a)) * 0.55;
    canvas.drawLine(hand, tip, Paint()
      ..color = const Color(0xFF6A6E74)
      ..strokeWidth = 0.08
      ..strokeCap = StrokeCap.square);
    if (swing > 0) {
      // Estela del golpe.
      final trail = Paint()
        ..color = Color.fromRGBO(220, 220, 230, 0.35 * swing)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05;
      canvas.drawArc(Rect.fromCircle(center: hand, radius: 0.5), angle - 1.1, 2.2 * (1 - swing), false, trail);
    }
  }

  void _drawObjects(Canvas canvas, Rect view, bool alive) {
    final sp = Sprites.i;
    final f = g.floor;
    final items = <(double, void Function())>[];
    final flip = [false];
    final shadowPaint = Paint()..color = const Color(0x66000000);

    void shadow(Offset feet, double w) {
      canvas.drawOval(Rect.fromCenter(center: feet, width: w, height: w * 0.35), shadowPaint);
    }

    for (final car in f.cars) {
      final c = car.center;
      if (!view.inflate(1).contains(c)) continue;
      items.add((
        c.dy + 0.95,
        () {
          final feet = c + const Offset(0, 0.97);
          sp.cars[car.color].draw(canvas, feet, 0.92, anchorY: 1);
          // Puerta entreabierta: se puede registrar.
          final cr = car.crate;
          if (cr != null && !cr.searched) {
            canvas.drawRect(Rect.fromLTWH(c.dx + 0.42, c.dy - 0.35, 0.08, 0.38), Paint()..color = const Color(0xFF9A9A90));
          }
        }
      ));
    }
    for (final c in f.crates) {
      if (c.kind == carCrate || !view.contains(c.pos)) continue;
      const widths = [0.95, 0.72, 0.95, 0.55, 0.6];
      items.add((
        c.pos.dy + 0.35,
        () {
          final feet = c.pos + const Offset(0, 0.38);
          shadow(feet, widths[c.kind]);
          sp.crates[c.kind].draw(canvas, feet, widths[c.kind], anchorY: 1, opacity: c.searched && !alive ? 0.55 : 1);
        }
      ));
    }
    for (final pc in f.pcs) {
      if (!view.contains(pc.pos)) continue;
      items.add((pc.pos.dy + 0.35, () => sp.pc.draw(canvas, pc.pos + const Offset(0, 0.35), 0.7, anchorY: 1)));
    }
    for (final r in f.rooms) {
      final sw = r.switchPos;
      if (sw == null || !view.contains(sw)) continue;
      items.add((
        sw.dy - 0.3,
        () {
          final box = Rect.fromCenter(center: sw + const Offset(0, -0.1), width: 0.26, height: 0.34);
          canvas.drawRect(box, Paint()..color = const Color(0xFF8A8A80));
          canvas.drawRect(box.deflate(0.04), Paint()..color = const Color(0xFFCFCFC0));
          canvas.drawRect(
              Rect.fromCenter(center: sw + Offset(0, r.lit ? -0.16 : -0.04), width: 0.08, height: 0.1),
              Paint()..color = const Color(0xFF404040));
        }
      ));
    }
    if (f.box != null && view.contains(f.box!)) {
      final b = f.box!;
      final bob = sin(g.time * 2) * 0.04;
      items.add((
        b.dy + 0.4,
        () {
          shadow(b + const Offset(0, 0.4), 0.8);
          sp.box.draw(canvas, b + Offset(0, 0.36 + bob), 0.85, anchorY: 1);
        }
      ));
    }
    for (final it in f.items) {
      if (!view.contains(it.pos)) continue;
      items.add((
        it.pos.dy,
        () => sp.icons[itemInfo[it.type]!.icon]!.draw(canvas, it.pos + Offset(0, sin(g.time * 4) * 0.04), 0.4),
      ));
    }
    for (final m in f.mannequins) {
      if (!view.contains(m.pos)) continue;
      items.add((
        m.pos.dy + 0.3,
        () {
          final feet = m.pos + const Offset(0, 0.3);
          shadow(feet, 0.5);
          if (m.fallen) {
            sp.manSide.draw(canvas, m.pos, 0.75, rotation: pi / 2);
          } else {
            final s = _dirSprite(m.angle, sp.manDown, sp.manUp, sp.manSide, flip);
            s.draw(canvas, feet, 0.9, anchorY: 1, flipX: flip[0]);
          }
        }
      ));
    }
    for (final e in f.enemies) {
      if (!view.contains(e.pos) || e.fade <= 0) continue;
      items.add((
        e.alive ? e.pos.dy + 0.3 : e.pos.dy - 0.5,
        () {
          final anim = sp.thugAnims[e.look];
          if (!e.alive) {
            if (!alive) {
              canvas.drawOval(
                  Rect.fromCenter(
                      center: e.pos + const Offset(0.05, 0.1), width: 0.5 + min(1.0, e.deadT) * 0.4, height: 0.4),
                  Paint()..color = const Color(0xAA4A0606));
            }
            _drawFall(canvas, anim.side[1], e.pos + const Offset(0, 0.3), 0.9, e.deadT, cos(e.angle) >= 0, e.fade);
            return;
          }
          final feet = e.pos + const Offset(0, 0.3);
          shadow(feet, 0.5);
          final fast = e.state == EState.chase || e.state == EState.flee;
          final frame = e.moving ? (g.time * (fast ? 11 : 6) + e.cigPhase).floor() : 0;
          final bob = e.moving ? -sin(g.time * (fast ? 17 : 9) + e.cigPhase).abs() * 0.04 : 0.0;
          final s = anim.pick(e.angle, frame, flip);
          final aiming = e.state == EState.aim;
          if (aiming && sin(e.angle) < 0) _drawGun(canvas, feet, e.angle, 0, aim: true);
          s.draw(canvas, feet + Offset(0, bob), 0.9, anchorY: 1, flipX: flip[0], opacity: e.fade);
          if (aiming && sin(e.angle) >= 0) _drawGun(canvas, feet, e.angle, 0, aim: true);
        }
      ));
    }
    final boss = f.boss;
    if (boss != null && view.contains(boss.pos)) {
      items.add((
        boss.alive ? boss.pos.dy + 0.35 : boss.pos.dy - 0.5,
        () {
          if (!boss.alive) {
            canvas.drawOval(
                Rect.fromCenter(
                    center: boss.pos + const Offset(0.05, 0.1), width: 0.7 + min(1.0, boss.deadT) * 0.6, height: 0.55),
                Paint()..color = const Color(0xAA4A0606));
            _drawFall(canvas, sp.bossAnim.side[1], boss.pos + const Offset(0, 0.35), 1.2, boss.deadT,
                cos(boss.angle) >= 0, 1);
            return;
          }
          final feet = boss.pos + const Offset(0, 0.35);
          shadow(feet, 0.75);
          final dir = Offset(cos(boss.angle), sin(boss.angle));
          final hurt = boss.hp < bossHp * 0.4;
          final frame = boss.moving ? (g.time * (hurt ? 6 : 8)).floor() : 0;
          var bob = boss.moving ? -sin(g.time * (hurt ? 9 : 12)).abs() * 0.06 : 0.0;
          // Cojea cuando está herido: un lado pesa más.
          final limp = boss.moving && hurt ? Offset(sin(g.time * 4.5) * 0.05, 0) : Offset.zero;
          // Echa el cuerpo atrás al preparar la puñalada y se lanza al soltarla.
          final windK = boss.windup > 0 ? 1 - boss.windup / 0.45 : 0.0;
          final strike = boss.cooldown > 0.82 ? (boss.cooldown - 0.82) / 0.18 : 0.0;
          final lunge = dir * (-0.12 * windK + 0.22 * strike);
          // Respira hondo cuando está quieto.
          final breath = boss.moving ? 0.0 : sin(g.time * 2.6) * 0.02;
          if (!boss.moving) bob -= breath * 0.5;
          final s = sp.bossAnim.pick(boss.angle, frame, flip);
          final op = boss.stagger > 0 && (g.time * 30).floor() % 2 == 0 ? 0.5 : 1.0;
          s.draw(canvas, feet + Offset(0, bob) + lunge + limp, 1.2 * (1 + breath), anchorY: 1, flipX: flip[0], opacity: op);
        }
      ));
    }
    for (final h in f.hideSpots) {
      if (!view.contains(h.pos)) continue;
      items.add((
        h.pos.dy + 0.4,
        () {
          final feet = h.pos + const Offset(0, 0.42);
          shadow(feet, 0.8);
          sp.hideSpots[h.kind].draw(canvas, feet, h.kind == 0 ? 0.7 : 0.85, anchorY: 1);
        }
      ));
    }
    final p = g.p;
    // Ya en el helicóptero: no se le ve en la azotea.
    if (g.hiding == null && !(g.won && g.fi == roofFloor)) {
      items.add((
      p.pos.dy + 0.3,
      () {
        final feet = p.pos + const Offset(0, 0.3);
        shadow(feet, 0.5);
        final bob = p.moving ? -sin(p.walkPhase * 3).abs() * 0.05 : 0.0;
        final frame = p.moving ? (p.walkPhase * 3 / pi).floor() : 0;
        final s = sp.playerAnim.pick(p.angle, frame, flip);
        final op = p.hurtT > 0 && (g.time * 20).floor() % 2 == 0 ? 0.4 : 1.0;
        final gun = p.hasPistol && p.ammo > 0;
        final pipe = !gun && p.hasPipe;
        final behind = sin(p.angle) < 0; // de espaldas, el arma queda detrás del cuerpo
        void weapon() {
          if (gun) _drawGun(canvas, feet + Offset(0, bob), p.angle, p.shotT / 0.18);
          if (pipe) _drawPipe(canvas, feet + Offset(0, bob), p.angle, p.swingT / 0.25);
        }

        if (behind) weapon();
        s.draw(canvas, feet + Offset(0, bob), 0.9, anchorY: 1, flipX: flip[0], opacity: op);
        if (!behind) weapon();
      }
      ));
    }

    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in items) {
      it.$2();
    }
  }

  // --- Oscuridad -------------------------------------------------------------

  void _cut(Canvas canvas, List<Offset> poly, Offset center, double radius, double intensity) {
    if (poly.length < 3 || intensity <= 0) return;
    final path = Path()..addPolygon(poly, true);
    final a = intensity.clamp(0.0, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [Color.fromRGBO(255, 255, 255, a), Color.fromRGBO(255, 255, 255, a * 0.75), const Color(0x00FFFFFF)],
          [0, 0.5, 1],
        ),
    );
  }

  void _drawDarkness(Canvas canvas, Rect view, double darkA) {
    final f = g.floor;
    canvas.saveLayer(view, Paint());
    canvas.drawRect(view, Paint()..color = Color.fromRGBO(0, 0, 0, 0.84 * darkA));
    final p = g.p;
    for (final r in f.rooms) {
      if (!r.lit || !view.overlaps(r.rect)) continue;
      canvas.drawRect(r.rect.inflate(0.15), Paint()
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0xE6FFFFFF));
    }
    for (final e in f.enemies) {
      if (!e.alive || e.light.isEmpty) continue;
      _cut(canvas, e.light, e.pos, 8, 0.7);
      canvas.drawCircle(e.pos, 1.1, Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.radial(e.pos, 1.1, [const Color(0x99FFFFFF), const Color(0x00FFFFFF)]));
    }
    _cut(canvas, g.ambientPoly, p.pos, g.ambientR * 1.2, 0.85);
    if (g.conePoly.isNotEmpty) _cut(canvas, g.conePoly, p.pos, g.coneLen, 0.97 * g.flashPower);
    for (final l in f.lamps) {
      if (!l.alive || l.level < 0.05) continue;
      if ((l.pos - p.pos).distance > 16) continue;
      _cut(canvas, l.poly, l.pos, l.radius, (l.mode == 3 ? 0.4 : (l.sign != null ? 0.55 : 0.75)) * l.level);
    }
    if (f.box != null) _cut(canvas, f.boxPoly, f.box!, 3.2, 0.5 + 0.15 * sin(g.time * 2.5));
    final boss = f.boss;
    if (boss != null && boss.alive) {
      canvas.drawCircle(boss.pos, 1.4, Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.radial(boss.pos, 1.4, [const Color(0x88FFFFFF), const Color(0x00FFFFFF)]));
    }
    final heli = f.helipad;
    if (heli != null && g.heliT >= 0) {
      canvas.drawCircle(heli, 3.5, Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = ui.Gradient.radial(heli, 3.5, [const Color(0xDDFFFFFF), const Color(0x00FFFFFF)]));
    }
    if (g.muzzleFlash > 0) _cut(canvas, g.flashPoly, p.pos, 7, g.muzzleFlash / 0.12);
    for (final fl in g.flashes) {
      _cut(canvas, fl.poly, fl.pos, 3.5, fl.t / 0.1);
    }
    if (g.magicFlash > 0) _cut(canvas, g.flashPoly, p.pos, 8, min(1.0, g.magicFlash));
    canvas.restore();
  }

  void _drawEmissive(Canvas canvas, Rect view, bool alive) {
    final f = g.floor;
    final p = g.p;
    final plus = Paint()..blendMode = BlendMode.plus;

    // Tinte de color de neones y lámparas.
    for (final l in f.lamps) {
      final level = alive ? 1.0 : l.level;
      if (!l.alive && !alive || level < 0.05) continue;
      if (!view.inflate(3).contains(l.pos)) continue;
      final a = (l.sign != null ? 0.22 : 0.08) * level;
      plus.shader = ui.Gradient.radial(
          l.pos, l.radius, [l.color.withValues(alpha: a), l.color.withValues(alpha: 0)], [0, 1]);
      canvas.drawPath(Path()..addPolygon(l.poly, true), plus);
    }
    plus.shader = null;

    if (f.box != null && view.inflate(3).contains(f.box!)) {
      final pulse = 0.35 + 0.15 * sin(g.time * 2.5);
      plus.shader = ui.Gradient.radial(f.box!, 3.2,
          [const Color(0xFFB04CFF).withValues(alpha: pulse), const Color(0x00B04CFF)], [0, 1]);
      canvas.drawPath(Path()..addPolygon(f.boxPoly, true), plus);
      plus.shader = null;
    }
    if (g.magicFlash > 0) {
      plus.shader = ui.Gradient.radial(p.pos, 8,
          [const Color(0xFFB04CFF).withValues(alpha: 0.5 * min(1.0, g.magicFlash)), const Color(0x00B04CFF)], [0, 1]);
      canvas.drawPath(Path()..addPolygon(g.flashPoly, true), plus);
      plus.shader = null;
    }

    for (final e in f.enemies) {
      if (!e.alive || e.light.isEmpty || alive) continue;
      plus.shader = ui.Gradient.radial(e.pos, 8, [const Color(0x40FFE8B0), const Color(0x00FFE8B0)]);
      canvas.drawPath(Path()..addPolygon(e.light, true), plus);
      plus.shader = null;
    }
    for (final r in f.rooms) {
      if (r.lit && !alive && view.overlaps(r.rect)) {
        canvas.drawRect(r.rect, Paint()
          ..blendMode = BlendMode.plus
          ..color = const Color(0x14FFF2D0));
      }
      final sw = r.switchPos;
      if (sw == null || !view.contains(sw)) continue;
      final blink = r.lit || (g.time * 1.5 + sw.dx).floor() % 2 == 0;
      if (blink) {
        canvas.drawCircle(sw + const Offset(0.09, -0.22), 0.04,
            Paint()..color = r.lit ? const Color(0xFF40FF60) : const Color(0xFFFF4040));
      }
    }

    // Pantallas de ordenador: brillan en la oscuridad. Todas parecen vivas.
    for (final pc in f.pcs) {
      if (!view.contains(pc.pos)) continue;
      Color? c;
      if (!pc.used) {
        final flick = sin(g.time * 7 + pc.phase) > 0.3 || _fx.nextDouble() < 0.1;
        c = flick ? const Color(0xFF7FA8FF) : const Color(0xFF203050);
      } else if (pc.working) {
        c = const Color(0xFF40FF90);
      }
      if (c == null) continue;
      const w = 0.7, px = w / 12;
      final top = pc.pos.dy + 0.35 - 12 * px;
      final left = pc.pos.dx - w / 2;
      canvas.drawRect(Rect.fromLTWH(left + 3 * px, top + 2 * px, 6 * px, 3 * px), Paint()..color = c);
      plus.shader = ui.Gradient.radial(
          Offset(pc.pos.dx, top + 3.5 * px), 0.9, [c.withValues(alpha: 0.25), c.withValues(alpha: 0)], [0, 1]);
      canvas.drawCircle(Offset(pc.pos.dx, top + 3.5 * px), 0.9, plus);
      plus.shader = null;
    }

    // Sicarios: la brasa del cigarro y el láser al apuntar.
    for (final e in f.enemies) {
      if (!e.alive || e.fade < 1 || alive) continue;
      final d = (e.pos - p.pos).distance;
      if (d > 13) continue;
      final head = e.pos + const Offset(0, -0.42);
      if (e.state != EState.flee && lineOfSight(f, p.pos, e.pos)) {
        final glow = 0.55 + 0.45 * sin(g.time * 1.7 + e.cigPhase);
        canvas.drawRect(
            Rect.fromCenter(center: head + Offset(cos(e.angle) * 0.12, 0.05), width: 0.06, height: 0.06),
            Paint()..color = Color.fromRGBO(255, 120, 30, glow));
        plus.shader = ui.Gradient.radial(head, 0.35, [Color.fromRGBO(255, 90, 20, 0.35 * glow), const Color(0x00FF5A14)], [0, 1]);
        canvas.drawCircle(head, 0.35, plus);
        plus.shader = null;
      }
      if (e.state == EState.aim && g.hiding == null) {
        // Punto rojo de la mira sobre el pecho: te están apuntando.
        final target = p.pos + const Offset(0, -0.25);
        canvas.drawCircle(target, 0.05 + 0.03 * sin(g.time * 30), Paint()..color = const Color(0xFFFF2020));
        plus.shader = ui.Gradient.radial(target, 0.25, [const Color(0x88FF2020), const Color(0x00FF2020)]);
        canvas.drawCircle(target, 0.25, plus);
        plus.shader = null;
      }
    }

    final boss = f.boss;
    if (boss != null && boss.alive && boss.windup > 0) {
      final tip = boss.pos + Offset(cos(boss.angle), sin(boss.angle)) * 0.55 + const Offset(0, -0.45);
      plus.shader = ui.Gradient.radial(tip, 0.45, [const Color(0xDDFFFFFF), const Color(0x00FFFFFF)]);
      canvas.drawCircle(tip, 0.45, plus);
      plus.shader = null;
    }

    // Balas: un proyectil incandescente con estela corta.
    for (final b in g.bullets) {
      final tail = b.pos - b.dir * 0.55;
      final col = b.fromPlayer ? const Color(0xFFFFF0A0) : const Color(0xFFFFB050);
      canvas.drawLine(
        tail,
        b.pos,
        Paint()
          ..strokeWidth = 0.07
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(tail, b.pos, [col.withValues(alpha: 0), col]),
      );
      canvas.drawCircle(b.pos, 0.045, Paint()..color = const Color(0xFFFFFFF0));
      plus.shader = ui.Gradient.radial(b.pos, 0.3, [col.withValues(alpha: 0.6), col.withValues(alpha: 0)]);
      canvas.drawCircle(b.pos, 0.3, plus);
      plus.shader = null;
    }
    for (final fl in g.flashes) {
      final k = fl.t / 0.1;
      plus.shader = ui.Gradient.radial(fl.pos, 0.7, [Color.fromRGBO(255, 230, 160, k), const Color(0x00FFE6A0)]);
      canvas.drawCircle(fl.pos, 0.7, plus);
      plus.shader = null;
    }
    if (g.muzzleFlash > 0) {
      final m = p.pos + Offset(cos(p.angle), sin(p.angle)) * 0.4 + const Offset(0, -0.15);
      final k = (g.muzzleFlash / 0.12).clamp(0.0, 1.0);
      plus.shader = ui.Gradient.radial(m, 2.2, [Color.fromRGBO(255, 200, 120, 0.35 * k), const Color(0x00FFC878)], [0, 1]);
      canvas.drawCircle(m, 2.2, plus);
      plus.shader = ui.Gradient.radial(m, 0.6, [const Color(0xFFFFF0A0), const Color(0x00FFF0A0)], [0, 1]);
      canvas.drawCircle(m, 0.6, plus);
      plus.shader = null;
    }
    _drawDust(canvas);
    final sp = Paint();
    for (final s in g.sparks) {
      sp.color = s.color.withValues(alpha: (s.life * 2).clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromCenter(center: s.pos, width: 0.06, height: 0.06), sp);
    }

    if (alive) {
      // El centro comercial vuelve a la vida: destellos dorados.
      final r = Random(g.fi * 31 + (g.time * 4).floor());
      for (var i = 0; i < 25; i++) {
        final pt = Offset(view.left + r.nextDouble() * view.width, view.top + r.nextDouble() * view.height);
        canvas.drawRect(Rect.fromCenter(center: pt, width: 0.06, height: 0.06),
            Paint()..color = const Color(0xCCFFF2B0));
      }
    }
  }

  void _drawSigns(Canvas canvas, Rect view, bool alive) {
    for (final l in g.floor.lamps) {
      if (l.sign == null || !view.contains(l.pos)) continue;
      final level = alive ? 1.0 : (l.alive ? l.level : 0.0);
      final on = level > 0.1;
      final col = on ? l.color : l.color.withValues(alpha: 0.18);
      final tp = TextPainter(
        text: TextSpan(
          text: l.sign,
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w900,
            fontSize: _s * (l.mode == 3 ? 0.18 : 0.3),
            letterSpacing: _s * 0.03,
            color: col,
            shadows: on ? [Shadow(color: l.color, blurRadius: 10 * level), Shadow(color: l.color, blurRadius: 3)] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final c = toScreen(l.pos + Offset(0, l.mode == 3 ? -0.3 : 0));
      if (on) {
        canvas.drawOval(
          Rect.fromCenter(center: c, width: tp.width * 1.5 + _s * 0.6, height: tp.height * 2.2 + _s * 0.4),
          Paint()
            ..blendMode = BlendMode.plus
            ..color = l.color.withValues(alpha: 0.22 * level)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, _s * 0.35),
        );
      }
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
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

  /// Helipuerto pintado en la azotea.
  void _drawHelipad(Canvas canvas, Rect view) {
    final c = g.floor.helipad;
    if (c == null || !view.inflate(4).contains(c)) return;
    final yellow = Paint()
      ..color = const Color(0xFFB89A30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.18;
    canvas.drawCircle(c, 2.6, yellow);
    final h = Paint()..color = const Color(0xFFD8D0B8);
    canvas.drawRect(Rect.fromLTWH(c.dx - 0.9, c.dy - 1.1, 0.35, 2.2), h);
    canvas.drawRect(Rect.fromLTWH(c.dx + 0.55, c.dy - 1.1, 0.35, 2.2), h);
    canvas.drawRect(Rect.fromLTWH(c.dx - 0.6, c.dy - 0.17, 1.2, 0.34), h);
  }

  /// El helicóptero baja al helipuerto y, al final, se va contigo dentro.
  void _drawHelicopter(Canvas canvas) {
    final pad = g.floor.helipad;
    if (pad == null || g.heliT < 0) return;
    var alt = (1 - g.heliT / Game.heliLandTime).clamp(0.0, 1.0);
    if (g.won) alt = min(1.5, g.endT * 0.35);
    final body = pad + Offset(alt * 2, -alt * 7);
    final sc = 1 + alt * 0.5;
    // Sombra y foco sobre el suelo.
    canvas.drawOval(Rect.fromCenter(center: pad, width: 2.6 / sc, height: 1.1 / sc),
        Paint()..color = Color.fromRGBO(0, 0, 0, 0.5 * (1 - alt * 0.6)));
    canvas.drawCircle(
        pad,
        3,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(pad, 3, [const Color(0x55FFF4D0), const Color(0x00FFF4D0)]));
    canvas.save();
    canvas.translate(body.dx, body.dy);
    canvas.scale(sc);
    final dark = Paint()..color = const Color(0xFF1E2A22);
    // Cola y cabina.
    canvas.drawRect(const Rect.fromLTWH(-0.1, 0.4, 0.2, 1.8), dark);
    canvas.drawRect(const Rect.fromLTWH(-0.45, 2.05, 0.9, 0.12), dark);
    canvas.drawOval(const Rect.fromLTWH(-0.7, -1.1, 1.4, 1.9), dark);
    canvas.drawOval(const Rect.fromLTWH(-0.45, -1.0, 0.9, 0.7), Paint()..color = const Color(0xFF3A5A6A));
    // Rotor girando.
    final a = g.time * 28;
    final blade = Paint()
      ..color = const Color(0x99101010)
      ..strokeWidth = 0.12;
    for (var i = 0; i < 4; i++) {
      final d = Offset(cos(a + i * pi / 2), sin(a + i * pi / 2)) * 2.2;
      canvas.drawLine(-d * 0.05, d, blade);
    }
    canvas.drawCircle(Offset.zero, 2.2, Paint()..color = const Color(0x18FFFFFF));
    // Luz roja de posición.
    if ((g.time * 2).floor() % 2 == 0) {
      canvas.drawCircle(const Offset(0, 2.1), 0.1, Paint()..color = const Color(0xFFFF2020));
    }
    canvas.restore();
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
    sp.icons[itemInfo[r.item]!.icon]!.draw(canvas, center, 64 * pop, opacity: fade);
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
