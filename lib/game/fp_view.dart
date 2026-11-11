import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'figure.dart';
import 'game.dart';
import 'sprites.dart';
import 'thug_art.dart';
import 'world.dart';

class _Item {
  final double depth, x0, x1;
  final void Function(Canvas c) draw;
  _Item(this.depth, this.x0, this.x1, this.draw);
}

/// Vista en primera persona: lanza un rayo por columna de pantalla para las
/// paredes y dibuja personajes y objetos como figuras de pie, de lejos a cerca.
class FpView {
  static const double wallH = 1.8; // altura de las paredes, en casillas
  static const double eye = 1.0; // altura de los ojos
  static const double _tanHalf = 0.78; // mitad del campo de visión
  static const double _colW = 3; // ancho de cada columna, en píxeles
  static const double _near = 0.06;
  static const _stops = [0.0, 0.02, 0.04, 0.07, 0.11, 0.16, 0.23, 0.32, 0.45, 0.6, 0.8, 1.0];

  late Game g;
  late FloorData f;
  double W = 0, H = 0;
  double px = 0, py = 0, fx = 1, fy = 0, rx = 0, ry = 1;
  double focal = 1, horizon = 0;
  bool roof = false;

  // Luz acumulada en el último punto consultado.
  double lr = 0, lg = 0, lb = 0;
  final List<Lamp> _lamps = [];
  final List<Enemy> _beams = [];
  final List<Room> _litRooms = [];

  // Una entrada por borde de columna.
  int _n = 0;
  Float64List _z = Float64List(0);
  Float64List _top = Float64List(0), _bot = Float64List(0);
  Float64List _cr = Float64List(0), _cg = Float64List(0), _cb = Float64List(0);
  Int32List _key = Int32List(0), _cell = Int32List(0);
  Float32List _pos = Float32List(0);
  Int32List _col = Int32List(0);
  Uint16List _idx = Uint16List(0);

  final List<_Item> _items = [];
  final List<double> _pa = [], _pb = [], _w = [];

  late Color _wallA, _wallB, _floorC, _shopC, _ceilC;
  static const _rubbleC = Color(0xFF6A5A48);

  // Última proyección de [_proj].
  double _d = 0, _sx = 0, _sc = 0;

  void paint(Canvas canvas, Size size, Game game, Offset shake) {
    g = game;
    f = g.floor;
    W = size.width;
    H = size.height;
    final p = g.p;
    px = p.pos.dx;
    py = p.pos.dy;
    fx = cos(p.angle);
    fy = sin(p.angle);
    rx = -fy;
    ry = fx;
    focal = W / 2 / _tanHalf * (1 + 0.35 * g.zoomPunch * g.zoomPunch);
    horizon = H / 2 + sin(p.walkPhase * 1.5) * H * 0.008 + shake.dy;
    roof = g.fi == roofFloor;
    final pal = darkPalettes[g.fi];
    _wallA = _mix(pal.wallFace, 0xFFC8C8C0, 0.6);
    _wallB = _mix(pal.wallFaceAlt, 0xFFC8C8C0, 0.6);
    _floorC = _mix(pal.floor, 0xFFA0A4AA, 0.4);
    _shopC = _mix(pal.shop, 0xFFA0A0A0, 0.3);
    _ceilC = _mix(pal.wallTop, 0xFFB0B4BA, 0.5);

    _lamps.clear();
    _beams.clear();
    _litRooms.clear();
    for (final l in f.lamps) {
      if (l.alive && l.level >= 0.05 && (l.pos - p.pos).distance < 24) _lamps.add(l);
    }
    for (final e in f.enemies) {
      if (e.alive && e.light.isNotEmpty) _beams.add(e);
    }
    for (final r in f.rooms) {
      if (r.lit) _litRooms.add(r);
    }

    canvas.save();
    canvas.translate(shake.dx, 0);
    _backdrop(canvas);
    _floorMarks(canvas);
    _walls(canvas);
    _sprites(canvas);
    canvas.restore();

    if (g.hiding == null && !g.won && !g.lost) {
      _dust(canvas);
      _weapon(canvas);
    }
    _aimWarning(canvas);
  }

  static Color _mix(Color a, int b, double t) => Color.lerp(a, Color(b), t)!;

  // --- Luz ---------------------------------------------------------------------

  void _add(double k, double r, double gg, double b) {
    lr += k * r;
    lg += k * gg;
    lb += k * b;
  }

  /// Luz que lleva encima el jugador: linterna, resplandor cercano y fogonazos.
  void _selfLight(double d, double ang) {
    final amb = roof ? 0.3 : 0.07;
    lr = amb * (roof ? 0.8 : 1);
    lg = amb * (roof ? 0.9 : 1);
    lb = amb * (roof ? 1.25 : 1.1);
    if (g.coneLen > 0.3 && d < g.coneLen) {
      final edge = ((Game.coneHalf + 0.1 - ang) / 0.22).clamp(0.0, 1.0);
      _add(0.95 * g.flashPower * pow(1 - d / g.coneLen, 1.2) * edge, 1, 0.96, 0.85);
    }
    final ar = g.ambientR * 1.3;
    if (d < ar) _add(0.5 * (1 - d / ar), 1, 0.95, 0.85);
    if (g.muzzleFlash > 0 && d < 7) _add((g.muzzleFlash / 0.12).clamp(0.0, 1.0) * (1 - d / 7), 1, 0.85, 0.55);
    if (g.magicFlash > 0 && d < 8) _add(min(1.0, g.magicFlash) * (1 - d / 8), 0.7, 0.35, 1);
  }

  /// Toda la luz que llega a un punto del mundo; el resultado queda en lr, lg, lb.
  void _lightAt(double x, double y, {bool los = true}) {
    final ax = x - px, ay = y - py;
    final d = sqrt(ax * ax + ay * ay);
    _selfLight(d, d < 0.01 ? 0 : angleDiff(atan2(ay, ax), g.p.angle));
    final pt = Offset(x, y);
    for (final r in _litRooms) {
      if (r.rect.inflate(0.1).contains(pt)) {
        _add(0.8, 1, 0.95, 0.82);
        break;
      }
    }
    for (final l in _lamps) {
      final ex = l.pos.dx - x, ey = l.pos.dy - y;
      final d2 = ex * ex + ey * ey;
      if (d2 >= l.radius * l.radius) continue;
      if (los && !lineOfSight(f, l.pos, pt)) continue;
      final k = (1 - sqrt(d2) / l.radius) * l.level * (l.mode == 3 ? 0.45 : (l.sign != null ? 0.6 : 0.85));
      _add(k, l.color.r, l.color.g, l.color.b);
    }
    for (final e in _beams) {
      final ex = x - e.pos.dx, ey = y - e.pos.dy;
      final d2 = ex * ex + ey * ey;
      if (d2 >= 64 || d2 < 0.01) continue;
      if (angleDiff(atan2(ey, ex), e.angle) > 0.42) continue;
      if (los && !lineOfSight(f, e.pos, pt)) continue;
      _add(0.7 * (1 - sqrt(d2) / 8), 1, 0.91, 0.69);
    }
    for (final fl in g.flashes) {
      final dd = (fl.pos - pt).distance;
      if (dd < 3.5) _add((fl.t / 0.1).clamp(0.0, 1.0) * (1 - dd / 3.5), 1, 0.9, 0.63);
    }
    final box = f.box;
    if (box != null) {
      final dd = (box - pt).distance;
      if (dd < 3.2) _add((0.5 + 0.15 * sin(g.time * 2.5)) * (1 - dd / 3.2), 0.69, 0.3, 1);
    }
    final pad = f.helipad;
    if (pad != null && g.heliT >= 0) {
      final dd = (pad - pt).distance;
      if (dd < 3.5) _add(0.8 * (1 - dd / 3.5), 1, 0.96, 0.82);
    }
  }

  /// Color [base] bajo la última luz calculada.
  Color _lit(Color base, [double m = 1, double alpha = 1]) => Color.fromARGB(
        (alpha * 255).round(),
        (base.r * min(1.0, lr) * m * 255).round().clamp(0, 255),
        (base.g * min(1.0, lg) * m * 255).round().clamp(0, 255),
        (base.b * min(1.0, lb) * m * 255).round().clamp(0, 255),
      );

  /// La última luz como tinte para multiplicar una imagen.
  Color _tint([double least = 0]) => Color.fromARGB(
        255,
        (lr.clamp(least, 1.0) * 255).round(),
        (lg.clamp(least, 1.0) * 255).round(),
        (lb.clamp(least, 1.0) * 255).round(),
      );

  // --- Proyección ----------------------------------------------------------------

  /// Proyecta un punto del suelo; false si queda detrás de la cámara.
  bool _proj(Offset w) {
    final ax = w.dx - px, ay = w.dy - py;
    _d = ax * fx + ay * fy;
    if (_d < 0.12) return false;
    _sc = focal / _d;
    _sx = W / 2 + (ax * rx + ay * ry) * _sc;
    return true;
  }

  /// Polígono 3D (ternas x, y, altura) recortado contra la cámara y proyectado.
  Path? _poly(List<double> w) {
    _pa.clear();
    for (var i = 0; i < w.length; i += 3) {
      final ax = w[i] - px, ay = w[i + 1] - py;
      _pa
        ..add(ax * fx + ay * fy)
        ..add(ax * rx + ay * ry)
        ..add(w[i + 2]);
    }
    _pb.clear();
    final m = _pa.length ~/ 3;
    for (var i = 0; i < m; i++) {
      final a = i * 3, b = ((i + 1) % m) * 3;
      final d0 = _pa[a], d1 = _pa[b];
      if (d0 >= _near) {
        _pb
          ..add(d0)
          ..add(_pa[a + 1])
          ..add(_pa[a + 2]);
      }
      if ((d0 >= _near) != (d1 >= _near)) {
        final t = (_near - d0) / (d1 - d0);
        _pb
          ..add(_near)
          ..add(_pa[a + 1] + (_pa[b + 1] - _pa[a + 1]) * t)
          ..add(_pa[a + 2] + (_pa[b + 2] - _pa[a + 2]) * t);
      }
    }
    if (_pb.length < 9) return null;
    final path = Path();
    for (var i = 0; i < _pb.length; i += 3) {
      final sc = focal / _pb[i];
      final x = W / 2 + _pb[i + 1] * sc, y = horizon - (_pb[i + 2] - eye) * sc;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  /// Polígono horizontal a la altura [z], opcionalmente encogido hacia [c].
  Path? _flat(List<Offset> pts, double z, [Offset? c, double s = 1]) {
    _w.clear();
    for (final p in pts) {
      final q = c == null ? p : c + (p - c) * s;
      _w
        ..add(q.dx)
        ..add(q.dy)
        ..add(z);
    }
    return _poly(_w);
  }

  Path? _rect(Rect r, double z) => _flat([r.topLeft, r.topRight, r.bottomRight, r.bottomLeft], z);

  /// Segmento sobre el suelo, añadido a [path].
  void _seg(Path path, double ax, double ay, double bx, double by) {
    var d0 = (ax - px) * fx + (ay - py) * fy, l0 = (ax - px) * rx + (ay - py) * ry;
    var d1 = (bx - px) * fx + (by - py) * fy, l1 = (bx - px) * rx + (by - py) * ry;
    if (d0 < _near && d1 < _near) return;
    if (d0 < _near) {
      final t = (_near - d0) / (d1 - d0);
      l0 += (l1 - l0) * t;
      d0 = _near;
    } else if (d1 < _near) {
      final t = (_near - d1) / (d0 - d1);
      l1 += (l0 - l1) * t;
      d1 = _near;
    }
    path.moveTo(W / 2 + l0 * focal / d0, horizon + eye * focal / d0);
    path.lineTo(W / 2 + l1 * focal / d1, horizon + eye * focal / d1);
  }

  // --- Suelo y techo -------------------------------------------------------------

  /// Degradado vertical: cada fila de pantalla es una distancia sobre el suelo o el techo.
  ui.Gradient _grad(Color base, double h, double span, int dir) {
    final colors = <Color>[];
    for (final t in _stops) {
      _selfLight(t <= 0 ? 1e6 : h * focal / (t * span), 0);
      colors.add(_lit(base));
    }
    return ui.Gradient.linear(Offset(0, horizon), Offset(0, horizon + dir * span), colors, _stops);
  }

  late ui.Gradient _shopShader;

  void _backdrop(Canvas c) {
    c.drawRect(Rect.fromLTRB(-40, -40, W + 40, H + 40), Paint()..color = const Color(0xFF000000));
    final below = max(1.0, H - horizon), above = max(1.0, horizon);
    _shopShader = _grad(_shopC, eye, below, 1);
    c.drawRect(Rect.fromLTRB(-40, horizon, W + 40, H + 40), Paint()..shader = _grad(_floorC, eye, below, 1));
    final sky = roof
        ? ui.Gradient.linear(Offset.zero, Offset(0, horizon), const [Color(0xFF04060A), Color(0xFF1A2030)])
        : _grad(_ceilC, wallH - eye, above, -1);
    c.drawRect(Rect.fromLTRB(-40, -40, W + 40, horizon), Paint()..shader = sky);
  }

  /// Todo lo que va pintado sobre el suelo o el techo. Las paredes se dibujan
  /// después y tapan lo que queda detrás de ellas.
  void _floorMarks(Canvas c) {
    final p = g.p;
    final paint = Paint();

    // Moqueta de las tiendas y techo de las que tienen la luz encendida.
    for (final r in f.rooms) {
      if (!r.rect.inflate(18).contains(p.pos)) continue;
      final path = _rect(r.rect, 0);
      if (path != null) {
        if (r.lit) {
          c.drawPath(path, Paint()..color = _mix(_shopC, 0xFFFFF2D0, 0.15));
        } else {
          c.drawPath(path, Paint()..shader = _shopShader);
        }
      }
      if (r.lit && !roof) {
        final top = _rect(r.rect, wallH);
        if (top != null) c.drawPath(top, Paint()..color = _mix(_ceilC, 0xFFFFF2D0, 0.3));
      }
    }

    // Juntas de las baldosas.
    final grid = Path();
    final x0 = (px - 10).floorToDouble(), x1 = (px + 10).ceilToDouble();
    final y0 = (py - 10).floorToDouble(), y1 = (py + 10).ceilToDouble();
    for (var x = x0; x <= x1; x++) {
      _seg(grid, x, y0, x, y1);
    }
    for (var y = y0; y <= y1; y++) {
      _seg(grid, x0, y, x1, y);
    }
    c.drawPath(
        grid,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x38000000));

    void tile(Point<int>? t, Color color) {
      if (t == null) return;
      final path = _rect(Rect.fromLTWH(t.x + 0.04, t.y + 0.04, 0.92, 0.92), 0);
      if (path == null) return;
      _lightAt(t.x + 0.5, t.y + 0.5, los: false);
      c.drawPath(path, paint..color = _lit(color));
    }

    tile(f.down, const Color(0xFF181010));
    tile(f.up, const Color(0xFF7A8A7A));
    tile(f.elevator, const Color(0xFF8E939C));

    final pad = f.helipad;
    if (pad != null) {
      _lightAt(pad.dx, pad.dy, los: false);
      final ring = [for (var i = 0; i < 40; i++) pad + Offset(cos(i * pi / 20), sin(i * pi / 20)) * 2.6];
      final path = _flat(ring, 0);
      if (path != null) {
        c.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(2.0, H * 0.008)
              ..color = _lit(const Color(0xFFD8B840)));
      }
      for (final r in [
        Rect.fromLTWH(pad.dx - 0.9, pad.dy - 1.1, 0.35, 2.2),
        Rect.fromLTWH(pad.dx + 0.55, pad.dy - 1.1, 0.35, 2.2),
        Rect.fromLTWH(pad.dx - 0.6, pad.dy - 0.17, 1.2, 0.34),
      ]) {
        final h = _rect(r, 0);
        if (h != null) c.drawPath(h, paint..color = _lit(const Color(0xFFD8D0B8)));
      }
    }

    // Manchas de sangre y papeles.
    for (final d in f.decals) {
      if (d.kind != 0 && d.kind != 2) continue;
      if ((d.pos - p.pos).distance > 9) continue;
      final blood = d.kind == 0;
      final hw = blood ? d.size * 0.32 : d.size * 0.25, hh = blood ? d.size * 0.24 : d.size * 0.17;
      final ca = cos(d.rot), sa = sin(d.rot);
      final path = _flat([
        for (final o in [Offset(-hw, -hh), Offset(hw, -hh), Offset(hw, hh), Offset(-hw, hh)])
          d.pos + Offset(o.dx * ca - o.dy * sa, o.dx * sa + o.dy * ca)
      ], 0);
      if (path == null) continue;
      _lightAt(d.pos.dx, d.pos.dy, los: false);
      c.drawPath(path, paint..color = _lit(blood ? const Color(0xFF7A0A0A) : const Color(0xFFD8D0B8), 1, 0.7));
    }

    // Charcos de luz: lámparas, neones y las linternas de los sicarios.
    final plus = Paint()..blendMode = BlendMode.plus;
    for (final l in _lamps) {
      final a = (l.mode == 3 ? 0.07 : (l.sign != null ? 0.13 : 0.11)) * l.level;
      plus.color = l.color.withValues(alpha: a);
      for (final s in const [1.0, 0.5]) {
        final path = _flat(l.poly, 0, l.pos, s);
        if (path != null) c.drawPath(path, plus);
      }
      if (!roof && l.sign == null && l.mode != 3) {
        final path = _flat(l.poly, wallH, l.pos, 0.45);
        if (path != null) c.drawPath(path, plus..color = l.color.withValues(alpha: a * 1.6));
      }
    }
    plus.color = const Color(0x38FFE8B0);
    for (final e in _beams) {
      final path = _flat(e.light, 0);
      if (path != null) c.drawPath(path, plus);
    }
    if (f.box != null && f.boxPoly.isNotEmpty) {
      final path = _flat(f.boxPoly, 0);
      if (path != null) {
        c.drawPath(path, plus..color = const Color(0xFFB04CFF).withValues(alpha: 0.14 + 0.06 * sin(g.time * 2.5)));
      }
    }
  }

  // --- Paredes -----------------------------------------------------------------

  void _alloc(int n) {
    _n = n;
    _z = Float64List(n + 1);
    _top = Float64List(n + 1);
    _bot = Float64List(n + 1);
    _cr = Float64List(n + 1);
    _cg = Float64List(n + 1);
    _cb = Float64List(n + 1);
    _key = Int32List(n + 1);
    _cell = Int32List(n + 1);
    // Dos cuadriláteros por columna: la pared y su zócalo.
    _pos = Float32List(n * 16);
    _col = Int32List(n * 8);
    _idx = Uint16List(n * 12);
    for (var q = 0; q < n * 2; q++) {
      final v = q * 4, i = q * 6;
      _idx[i] = v;
      _idx[i + 1] = v + 1;
      _idx[i + 2] = v + 2;
      _idx[i + 3] = v;
      _idx[i + 4] = v + 2;
      _idx[i + 5] = v + 3;
    }
  }

  static int _rgb(double r, double g, double b, double m) =>
      0xFF000000 |
      ((r * m).round().clamp(0, 255) << 16) |
      ((g * m).round().clamp(0, 255) << 8) |
      (b * m).round().clamp(0, 255);

  void _walls(Canvas canvas) {
    final n = (W / _colW).ceil();
    if (n != _n) _alloc(n);
    final rubble = <int>{for (final c in f.rubble) c.y * mapW + c.x};

    for (var i = 0; i <= n; i++) {
      final camX = (i * _colW - W / 2) / focal;
      final dx = fx + rx * camX, dy = fy + ry * camX;
      var mx = px.floor(), my = py.floor();
      final ddx = dx == 0 ? 1e30 : (1 / dx).abs(), ddy = dy == 0 ? 1e30 : (1 / dy).abs();
      final sx = dx < 0 ? -1 : 1, sy = dy < 0 ? -1 : 1;
      var sdx = dx < 0 ? (px - mx) * ddx : (mx + 1 - px) * ddx;
      var sdy = dy < 0 ? (py - my) * ddy : (my + 1 - py) * ddy;
      var side = 0;
      for (var k = 0; k < 120; k++) {
        if (sdx < sdy) {
          sdx += ddx;
          mx += sx;
          side = 0;
        } else {
          sdy += ddy;
          my += sy;
          side = 1;
        }
        if (f.opaqueAt(mx, my)) break;
      }
      final perp = max(0.05, side == 0 ? sdx - ddx : sdy - ddy);
      final hx = px + dx * perp, hy = py + dy * perp;
      final sc = focal / perp;
      _z[i] = perp;
      _top[i] = max(-4 * H, horizon - (wallH - eye) * sc);
      _bot[i] = min(5 * H, horizon + eye * sc);
      // Mismo plano de pared en columnas vecinas: se unen sin escalones.
      _key[i] = side == 0 ? (sx > 0 ? mx : mx + 1) * 4 + (sx > 0 ? 0 : 1) : (sy > 0 ? my : my + 1) * 4 + (sy > 0 ? 2 : 3);
      _cell[i] = side == 0 ? hy.floor() : hx.floor();
      final front = side == 0 ? f.at(mx - sx, my) : f.at(mx, my - sy);
      final base = rubble.contains(my * mapW + mx) ? _rubbleC : (front == Tile.shop ? _wallB : _wallA);
      _lightAt(hx - dx * 0.04, hy - dy * 0.04);
      final sh = (side == 1 ? 0.82 : 1.0) * 255;
      _cr[i] = base.r * min(1.0, lr) * sh;
      _cg[i] = base.g * min(1.0, lg) * sh;
      _cb[i] = base.b * min(1.0, lb) * sh;
    }

    for (var i = 0; i < n; i++) {
      final same = _key[i] == _key[i + 1];
      final j = same ? i + 1 : i;
      // Junta vertical entre casillas.
      final seam = same && _cell[i] != _cell[i + 1] ? 0.7 : 1.0;
      final xa = i * _colW, xb = (i + 1) * _colW;
      final ta = _top[i], ba = _bot[i], tb = _top[j], bb = _bot[j];
      final ka = ba - (ba - ta) * 0.07, kb = bb - (bb - tb) * 0.07;
      final ca = _rgb(_cr[i], _cg[i], _cb[i], seam), cb = _rgb(_cr[j], _cg[j], _cb[j], seam);
      final za = _rgb(_cr[i], _cg[i], _cb[i], 0.55), zb = _rgb(_cr[j], _cg[j], _cb[j], 0.55);
      var v = i * 16;
      _pos[v] = xa;
      _pos[v + 1] = ta;
      _pos[v + 2] = xb;
      _pos[v + 3] = tb;
      _pos[v + 4] = xb;
      _pos[v + 5] = kb;
      _pos[v + 6] = xa;
      _pos[v + 7] = ka;
      _pos[v + 8] = xa;
      _pos[v + 9] = ka;
      _pos[v + 10] = xb;
      _pos[v + 11] = kb;
      _pos[v + 12] = xb;
      _pos[v + 13] = bb;
      _pos[v + 14] = xa;
      _pos[v + 15] = ba;
      v = i * 8;
      _col[v] = ca;
      _col[v + 1] = cb;
      _col[v + 2] = cb;
      _col[v + 3] = ca;
      _col[v + 4] = za;
      _col[v + 5] = zb;
      _col[v + 6] = zb;
      _col[v + 7] = za;
    }
    final verts = ui.Vertices.raw(ui.VertexMode.triangles, _pos, colors: _col, indices: _idx);
    canvas.drawVertices(verts, BlendMode.dst, Paint());
    verts.dispose();
  }

  // --- Personajes y objetos --------------------------------------------------------

  /// Dibuja solo en las columnas donde no hay una pared más cerca que [depth].
  void _clipped(Canvas c, _Item it) {
    if (it.x1 < 0 || it.x0 > W) return;
    final i1 = (it.x1 / _colW).ceil().clamp(0, _n);
    var i = (it.x0 / _colW).floor().clamp(0, _n);
    while (i < i1) {
      if (_z[i] <= it.depth) {
        i++;
        continue;
      }
      final s = i;
      while (i < i1 && _z[i] > it.depth) {
        i++;
      }
      c.save();
      c.clipRect(Rect.fromLTRB(s * _colW, -40, i * _colW, H + 40));
      it.draw(c);
      c.restore();
    }
  }

  /// Añade algo plantado en [w]. [draw] recibe la x en pantalla, los píxeles
  /// por casilla a esa distancia y la y del suelo.
  void _put(Offset w, double halfW, void Function(Canvas c, double sx, double sc, double fy) draw) {
    if (!_proj(w)) return;
    final d = _d, sx = _sx, sc = _sc;
    final hw = halfW * sc;
    if (sx + hw < 0 || sx - hw > W) return;
    _items.add(_Item(d, sx - hw, sx + hw, (c) => draw(c, sx, sc, horizon + eye * sc)));
  }

  void _img(Canvas c, Sprite s, double cx, double bottom, double wpx,
      {bool flip = false, double opacity = 1, Color? tint, double rot = 0}) {
    final hpx = wpx * s.h / s.w;
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (tint != null) paint.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    if (opacity < 1) paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    c.save();
    c.translate(cx, bottom);
    if (rot != 0) c.rotate(rot);
    if (flip) c.scale(-1, 1);
    c.drawImageRect(s.image, Rect.fromLTWH(0, 0, s.w.toDouble(), s.h.toDouble()),
        Rect.fromLTWH(-wpx / 2, -hpx, wpx, hpx), paint);
    c.restore();
  }

  /// Mueble u objeto recortado, apoyado en [bottom] y con [hpx] píxeles de alto.
  void _prop(Canvas c, ui.Image im, double cx, double bottom, double hpx,
      {double opacity = 1, Color? tint, double rot = 0}) {
    final wpx = hpx * im.width / im.height;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (tint != null) paint.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    if (opacity < 1) paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    c.save();
    c.translate(cx, bottom);
    if (rot != 0) c.rotate(rot);
    c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
        Rect.fromLTWH(-wpx / 2, -hpx, wpx, hpx), paint);
    c.restore();
  }

  /// Un mueble ya registrado se ve algo más apagado.
  static Color _dim(Color c) => Color.fromARGB(255, (c.r * 255 * 0.7).round(), (c.g * 255 * 0.7).round(), (c.b * 255 * 0.7).round());

  /// Media anchura en el mundo de una imagen de [h] de alto.
  static double _halfOf(ui.Image? im, double h, double fallback) => im == null ? fallback : h * im.width / im.height / 2;

  /// Imagen recortada de un personaje, de pie sobre [feet] y con [h] píxeles de alto.
  void _photo(Canvas c, Pose pose, Offset feet, double h,
      {required Color tint, bool flip = false, double opacity = 1, double rot = 0}) {
    final im = ThugArt.image(pose);
    final w = h * im.width / im.height;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    if (opacity < 1) paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    c.save();
    c.translate(feet.dx, feet.dy);
    if (rot != 0) c.rotate(rot);
    if (flip) c.scale(-1, 1);
    c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
        Rect.fromLTWH(-w * pose.axis, -h, w, h), paint);
    c.restore();
  }

  /// Un sicario según se le vea de frente, de espaldas o de perfil. [step] es
  /// el punto del paso (0..3) o -1 si está quieto. Sin imágenes cargadas, la
  /// figura dibujada.
  void _thug(Canvas c, Offset feet, double h, FigureLook look,
      {required double facing,
      required Color tint,
      double swing = 0,
      int step = -1,
      double opacity = 1,
      double rot = 0,
      bool aiming = false}) {
    if (!ThugArt.ready) {
      drawFigure(c, feet, h, look,
          facing: facing, swing: swing, tint: tint, opacity: opacity, rot: rot, aiming: aiming);
      return;
    }
    final ca = cos(facing), sa = sin(facing);
    final walking = step == 0 || step == 2;
    final Pose pose;
    var flip = false;
    if (ca.abs() > sa.abs()) {
      pose = aiming ? ThugArt.aimSide : (walking ? ThugArt.walkSide : ThugArt.side);
      flip = ca < 0;
    } else if (sa > 0) {
      pose = aiming ? ThugArt.aimFront : (walking ? ThugArt.walkFront : ThugArt.front);
      flip = !aiming && step == 2; // el otro pie: la misma zancada en espejo
    } else {
      pose = ThugArt.back;
      rot += swing * 0.03; // de espaldas solo hay una imagen: se balancea
    }
    _photo(c, pose, feet, h, tint: tint, flip: flip, opacity: opacity, rot: rot);
  }

  /// El carnicero, con su imagen si está cargada.
  void _bossArt(Canvas c, Offset feet, double h,
      {required double facing, required Color tint, double swing = 0, double opacity = 1, double rot = 0, bool windup = false}) {
    if (!ThugArt.bossReady) {
      drawFigure(c, feet, h, bossFigure,
          facing: facing, swing: swing, tint: tint, opacity: opacity, rot: rot, aiming: windup);
      return;
    }
    final ca = cos(facing), sa = sin(facing);
    final side = ca.abs() > sa.abs();
    _photo(c, side ? ThugArt.bossSide : (sa > 0 ? ThugArt.bossFront : ThugArt.bossBack), feet, h,
        tint: tint, flip: side && ca < 0, opacity: opacity, rot: rot + swing * 0.035);
  }

  void _glow(Canvas c, Offset at, double r, Color color) {
    if (r < 0.5) return;
    c.drawCircle(
        at,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(at, r, [color, color.withValues(alpha: 0)]));
  }

  void _shadow(Canvas c, double sx, double fy, double w, double sc) {
    final flat = (eye * sc / focal).clamp(0.05, 0.6);
    c.drawOval(Rect.fromCenter(center: Offset(sx, fy), width: w * sc, height: w * sc * flat),
        Paint()..color = const Color(0x66000000));
  }

  /// Hacia dónde mira alguien visto desde la cámara, en el convenio de
  /// [CharAnim.pick]: «abajo» es de frente y «arriba» de espaldas.
  double _facing(double angle) {
    final ca = cos(angle), sa = sin(angle);
    return atan2(-(ca * fx + sa * fy), ca * rx + sa * ry);
  }

  /// Caja con las caras que se ven desde la cámara.
  void _box(Canvas c, double x0, double y0, double x1, double y1, double z0, double z1, Color color, Color tint) {
    final paint = Paint();
    void face(List<double> pts, double m) {
      final path = _poly(pts);
      if (path == null) return;
      paint.color = Color.fromARGB(
        255,
        (color.r * tint.r * m * 255).round().clamp(0, 255),
        (color.g * tint.g * m * 255).round().clamp(0, 255),
        (color.b * tint.b * m * 255).round().clamp(0, 255),
      );
      c.drawPath(path, paint);
    }

    if (px < x0) face([x0, y0, z0, x0, y1, z0, x0, y1, z1, x0, y0, z1], 1);
    if (px > x1) face([x1, y0, z0, x1, y1, z0, x1, y1, z1, x1, y0, z1], 1);
    if (py < y0) face([x0, y0, z0, x1, y0, z0, x1, y0, z1, x0, y0, z1], 0.8);
    if (py > y1) face([x0, y1, z0, x1, y1, z0, x1, y1, z1, x0, y1, z1], 0.8);
    if (eye > z1) face([x0, y0, z1, x1, y0, z1, x1, y1, z1, x0, y1, z1], 1.15);
  }

  /// Añade un volumen de planta [r] (coches, escalones): se ordena por su centro.
  void _putSolid(Rect r, void Function(Canvas c, Color tint) draw) {
    final cx = r.center.dx - px, cy = r.center.dy - py;
    final depth = cx * fx + cy * fy;
    if (depth < -1.5 || depth > 26) return;
    var x0 = double.infinity, x1 = -double.infinity;
    for (final q in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final d = (q.dx - px) * fx + (q.dy - py) * fy;
      if (d < 0.1) {
        x0 = 0;
        x1 = W;
        break;
      }
      final x = W / 2 + ((q.dx - px) * rx + (q.dy - py) * ry) * focal / d;
      x0 = min(x0, x);
      x1 = max(x1, x);
    }
    if (x1 < 0 || x0 > W) return;
    _lightAt(r.center.dx, r.center.dy, los: false);
    final tint = _tint();
    _items.add(_Item(max(0.1, depth), x0, x1, (c) => draw(c, tint)));
  }

  void _sprites(Canvas canvas) {
    final sp = Sprites.i;
    final p = g.p;
    final t = g.time;
    _items.clear();

    // Coches: carrocería, cabina y, si se puede registrar, la puerta abierta.
    for (final car in f.cars) {
      final x = car.tile.x.toDouble(), y = car.tile.y.toDouble();
      final body = carBodies[car.color];
      final open = car.crate != null && !car.crate!.searched;
      _putSolid(Rect.fromLTRB(x + 0.06, y + 0.05, x + 0.94, y + 1.95), (c, tint) {
        _box(c, x + 0.06, y + 0.05, x + 0.94, y + 1.95, 0.1, 0.62, body, tint);
        _box(c, x + 0.14, y + 0.55, x + 0.86, y + 1.5, 0.62, 0.98, const Color(0xFF2A3440), tint);
        if (open) _box(c, x + 0.94, y + 0.62, x + 1.3, y + 0.7, 0.16, 0.92, Color.lerp(body, Colors.white, 0.25)!, tint);
      });
    }

    // Escalera de subida: tres peldaños.
    final up = f.up;
    if (up != null) {
      final x = up.x.toDouble(), y = up.y.toDouble();
      _putSolid(Rect.fromLTWH(x, y, 1, 1), (c, tint) {
        for (var i = 0; i < 3; i++) {
          _box(c, x + 0.08, y + 0.08 + i * 0.28, x + 0.92, y + 0.36 + i * 0.28, 0, 0.66 - i * 0.22,
              const Color(0xFF9AA89A), tint);
        }
      });
    }
    void arrow(Point<int>? at, bool upward) {
      if (at == null) return;
      _put(tileCenter(at), 0.3, (c, sx, sc, fy) {
        final y = fy - 1.35 * sc, s = 0.2 * sc * (upward ? 1 : -1);
        c.drawPath(
            Path()
              ..moveTo(sx, y - s)
              ..lineTo(sx + s.abs(), y + s)
              ..lineTo(sx - s.abs(), y + s)
              ..close(),
            Paint()..color = upward ? const Color(0xCC6FBF73) : const Color(0xCCBF6F6F));
      });
    }

    arrow(f.up, true);
    arrow(f.down, false);

    const crateW = [1.3, 0.95, 1.2, 0.5, 0.75];
    const crateH = [1.7, 1.75, 1.15, 0.7, 1.75]; // estantería, máquina, mostrador, papelera, armario
    for (final cr in f.crates) {
      if (cr.kind == carCrate) continue;
      _lightAt(cr.pos.dx, cr.pos.dy);
      final tint = _tint();
      final art = ThugArt.prop(ThugArt.crateFiles[cr.kind]);
      final w = crateW[cr.kind], h = crateH[cr.kind];
      _put(cr.pos, _halfOf(art, h, w / 2), (c, sx, sc, fy) {
        _shadow(c, sx, fy, w, sc);
        if (art != null) {
          _prop(c, art, sx, fy, h * sc, opacity: cr.searched ? 0.7 : 1, tint: cr.searched ? _dim(tint) : tint);
        } else {
          _img(c, sp.crates[cr.kind], sx, fy, w * sc, opacity: cr.searched ? 0.55 : 1, tint: tint);
        }
      });
    }

    for (final pc in f.pcs) {
      _lightAt(pc.pos.dx, pc.pos.dy);
      final tint = _tint();
      Color? screen;
      if (!pc.used) {
        screen = sin(t * 7 + pc.phase) > 0.3 ? const Color(0xFF7FA8FF) : const Color(0xFF203050);
      } else if (pc.working) {
        screen = const Color(0xFF40FF90);
      }
      final art = ThugArt.prop('obj_pc');
      const h = 1.15;
      _put(pc.pos, _halfOf(art, h, 0.4), (c, sx, sc, fy) {
        if (art != null) {
          _shadow(c, sx, fy, 0.9, sc);
          _prop(c, art, sx, fy, h * sc, tint: tint);
          if (screen == null) return;
          // La pantalla brilla en la oscuridad (la del dibujo está apagada).
          final wpx = h * sc * art.width / art.height;
          final scr = Rect.fromLTWH(sx - wpx / 2 + 0.35 * wpx, fy - h * sc * 0.95, 0.19 * wpx, h * sc * 0.16);
          c.drawRRect(RRect.fromRectAndRadius(scr, Radius.circular(0.03 * sc)),
              Paint()..color = screen.withValues(alpha: 0.75));
          _glow(c, scr.center, 0.9 * sc, screen.withValues(alpha: 0.25));
          return;
        }
        const w = 0.8;
        _img(c, sp.pc, sx, fy, w * sc, tint: tint);
        if (screen == null) return;
        // La pantalla brilla en la oscuridad.
        final u = w * sc / 12;
        c.drawRect(Rect.fromLTWH(sx - 3 * u, fy - 10 * u, 6 * u, 3 * u), Paint()..color = screen);
        _glow(c, Offset(sx, fy - 8.5 * u), 0.9 * sc, screen.withValues(alpha: 0.25));
      });
    }

    for (final r in f.rooms) {
      final sw = r.switchPos;
      if (sw == null) continue;
      _lightAt(sw.dx, sw.dy);
      final tint = _tint(0.15);
      final blink = r.lit || (t * 1.5 + sw.dx).floor() % 2 == 0;
      _put(sw, 0.15, (c, sx, sc, fy) {
        final paint = Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
        c.drawRect(Rect.fromLTRB(sx - 0.025 * sc, fy - 0.8 * sc, sx + 0.025 * sc, fy), paint..color = const Color(0xFF5A5A58));
        final box = Rect.fromLTRB(sx - 0.13 * sc, fy - 1.14 * sc, sx + 0.13 * sc, fy - 0.8 * sc);
        c.drawRect(box, paint..color = const Color(0xFF8A8A80));
        c.drawRect(box.deflate(0.04 * sc), paint..color = const Color(0xFFCFCFC0));
        c.drawRect(
            Rect.fromCenter(center: Offset(sx, fy - (r.lit ? 1.03 : 0.91) * sc), width: 0.08 * sc, height: 0.1 * sc),
            paint..color = const Color(0xFF404040));
        if (blink) {
          c.drawCircle(Offset(sx + 0.09 * sc, fy - 1.09 * sc), max(1.5, 0.03 * sc),
              Paint()..color = r.lit ? const Color(0xFF40FF60) : const Color(0xFFFF4040));
        }
      });
    }

    final box = f.box;
    if (box != null) {
      _lightAt(box.dx, box.dy);
      final tint = _tint(0.5);
      _put(box, 0.4, (c, sx, sc, fy) {
        final bob = (0.12 + sin(t * 2) * 0.04) * sc;
        _shadow(c, sx, fy, 0.7, sc);
        final art = ThugArt.prop('obj_box');
        if (art != null) {
          _prop(c, art, sx, fy - bob, 0.62 * sc, tint: tint);
        } else {
          _img(c, sp.box, sx, fy - bob, 0.75 * sc, tint: tint);
        }
        _glow(c, Offset(sx, fy - bob - 0.37 * sc), 1.1 * sc, const Color(0xFFB04CFF).withValues(alpha: 0.3 + 0.12 * sin(t * 2.5)));
      });
    }

    for (final it in f.items) {
      _lightAt(it.pos.dx, it.pos.dy);
      final tint = _tint(0.3);
      final art = ThugArt.prop('item_${it.type.name}');
      _put(it.pos, 0.2, (c, sx, sc, fy) {
        final lift = fy - (0.12 + sin(t * 4) * 0.04) * sc;
        if (art != null) {
          // Cabe en un cuadro de 0.34: lo alto por su altura, lo ancho por su anchura.
          final h = 0.34 * min(1.0, art.height / art.width);
          _prop(c, art, sx, lift, h * sc, tint: tint);
        } else {
          _img(c, sp.icons[itemInfo[it.type]!.icon]!, sx, lift, 0.38 * sc, tint: tint);
        }
      });
    }

    for (final m in f.mannequins) {
      _lightAt(m.pos.dx, m.pos.dy);
      final tint = _tint();
      _put(m.pos, 0.6, (c, sx, sc, fy) {
        _shadow(c, sx, fy, 0.5, sc);
        final art = ThugArt.prop('obj_mannequin');
        if (art != null) {
          _prop(c, art, m.fallen ? sx - 0.55 * sc : sx, fy, 1.45 * sc, tint: tint, rot: m.fallen ? pi / 2 : 0);
          return;
        }
        if (m.fallen) {
          drawFigure(c, Offset(sx - 0.5 * sc, fy), 1.2 * sc, mannequinFigure, facing: 0, tint: tint, rot: pi / 2);
          return;
        }
        drawFigure(c, Offset(sx, fy), 1.2 * sc, mannequinFigure, facing: _facing(m.angle), tint: tint);
      });
    }

    for (final e in f.enemies) {
      if (e.fade <= 0) continue;
      _lightAt(e.pos.dx, e.pos.dy);
      final tint = _tint();
      final look = thugFigures[e.look];
      final facing = _facing(e.angle);
      final right = cos(facing) >= 0;
      _put(e.pos, 0.9, (c, sx, sc, fy) {
        if (!e.alive) {
          final w = (0.5 + min(1.0, e.deadT) * 0.4) * sc;
          c.drawOval(Rect.fromCenter(center: Offset(sx, fy), width: w, height: w * (eye * sc / focal).clamp(0.05, 0.6)),
              Paint()..color = const Color(0xAA4A0606));
          final k = Curves.easeIn.transform((e.deadT / 0.35).clamp(0.0, 1.0));
          _thug(c, Offset(sx, fy), 1.2 * sc, look,
              facing: right ? 0 : pi, tint: tint, opacity: e.fade, rot: (right ? -1 : 1) * k * pi / 2);
          return;
        }
        _shadow(c, sx, fy, 0.5, sc);
        final fast = e.state == EState.chase || e.state == EState.flee;
        final swing = e.moving ? sin(t * (fast ? 11 : 6) + e.cigPhase) : 0.0;
        final step = e.moving ? (t * (fast ? 7 : 4) + e.cigPhase * 4).floor() % 4 : -1;
        final bob = e.moving ? swing.abs() * 0.03 * sc : 0.0;
        _thug(c, Offset(sx, fy - bob), 1.2 * sc, look,
            facing: facing, swing: swing, step: step, tint: tint, opacity: e.fade, aiming: e.state == EState.aim);
        if (e.fade < 1) return;
        final side = right ? 1 : -1;
        // La brasa del cigarro se ve aunque él esté a oscuras.
        // De espaldas no se ve: queda en la boca, por delante.
        final profile = cos(facing).abs() > sin(facing).abs();
        if (e.state != EState.flee && (profile || sin(facing) > 0)) {
          final glow = 0.55 + 0.45 * sin(t * 1.7 + e.cigPhase);
          final head = Offset(sx + side * (profile ? 0.075 : 0.02) * sc, fy - 1.045 * sc - bob);
          c.drawCircle(head, max(1.2, 0.012 * sc), Paint()..color = Color.fromRGBO(255, 130, 40, glow));
          _glow(c, head, 0.12 * sc, Color.fromRGBO(255, 90, 20, 0.4 * glow));
        }
        // Su linterna deslumbra cuando te enfoca.
        final gaze = angleDiff(e.angle, (p.pos - e.pos).direction);
        if (gaze < 0.45) {
          final k = 1 - gaze / 0.45;
          final at = Offset(sx + side * 0.12 * sc, fy - 0.78 * sc - bob);
          _glow(c, at, min(H * 0.6, (0.3 + 0.6 * k) * sc), Color.fromRGBO(255, 236, 190, 0.75 * k));
          _glow(c, at, min(H * 0.2, 0.12 * sc), Color.fromRGBO(255, 255, 255, k));
        }
        if (e.state == EState.aim && (t * 8).floor() % 2 == 0) {
          final at = Offset(sx + (profile ? side * 0.43 : 0.0) * sc, fy - 0.97 * sc - bob); // la boca del cañón
          c.drawCircle(at, max(1.5, 0.04 * sc), Paint()..color = const Color(0xFFFF3030));
          _glow(c, at, 0.25 * sc, const Color(0x99FF2020));
        }
      });
    }

    final boss = f.boss;
    if (boss != null) {
      _lightAt(boss.pos.dx, boss.pos.dy);
      final tint = _tint(0.1);
      final facing = _facing(boss.angle);
      final right = cos(facing) >= 0;
      _put(boss.pos, 1.2, (c, sx, sc, fy) {
        if (!boss.alive) {
          final w = (0.7 + min(1.0, boss.deadT) * 0.6) * sc;
          c.drawOval(Rect.fromCenter(center: Offset(sx, fy), width: w, height: w * (eye * sc / focal).clamp(0.05, 0.6)),
              Paint()..color = const Color(0xAA4A0606));
          final k = Curves.easeIn.transform((boss.deadT / 0.35).clamp(0.0, 1.0));
          _bossArt(c, Offset(sx, fy), 1.5 * sc, facing: right ? 0 : pi, tint: tint, rot: (right ? -1 : 1) * k * pi / 2);
          return;
        }
        _shadow(c, sx, fy, 0.75, sc);
        final hurt = boss.hp < bossHp * 0.4;
        final swing = boss.moving ? sin(t * (hurt ? 6 : 8)) : 0.0;
        final bob = boss.moving ? sin(t * (hurt ? 9 : 12)).abs() * 0.06 * sc : sin(t * 2.6) * 0.01 * sc;
        // Cojea cuando está herido; se encoge al preparar el zarpazo y se te echa encima al soltarla.
        final limp = boss.moving && hurt ? sin(t * 4.5) * 0.05 * sc : 0.0;
        final wind = boss.windup > 0 ? 1 - boss.windup / 0.45 : 0.0;
        final strike = boss.cooldown > 0.82 ? (boss.cooldown - 0.82) / 0.18 : 0.0;
        final op = boss.stagger > 0 && (t * 30).floor() % 2 == 0 ? 0.5 : 1.0;
        _bossArt(c, Offset(sx + limp, fy - bob), 1.5 * sc * (1 - 0.08 * wind + 0.2 * strike),
            facing: facing, swing: swing, tint: tint, opacity: op, windup: boss.windup > 0);
        if (boss.windup > 0) _glow(c, Offset(sx + 0.4 * sc, fy - 0.6 * sc), 0.45 * sc, const Color(0xDDFFFFFF));
      });
    }

    for (final h in f.hideSpots) {
      if (h == g.hiding) continue;
      _lightAt(h.pos.dx, h.pos.dy);
      final tint = _tint();
      final w = h.kind == 0 ? 0.9 : 1.0;
      final art = ThugArt.prop(ThugArt.hideFiles[h.kind]);
      final ht = h.kind == 0 ? 1.8 : 1.85;
      _put(h.pos, _halfOf(art, ht, w / 2), (c, sx, sc, fy) {
        _shadow(c, sx, fy, 0.8, sc);
        if (art != null) {
          _prop(c, art, sx, fy, ht * sc, tint: tint);
        } else {
          _img(c, sp.hideSpots[h.kind], sx, fy, w * sc, tint: tint);
        }
      });
    }

    // Lámparas y letreros de neón.
    for (final l in f.lamps) {
      if ((l.pos - p.pos).distance > 24) continue;
      final level = l.alive ? l.level : 0.0;
      final sign = l.sign;
      if (sign == null) {
        if (level < 0.05) continue;
        final z = l.mode == 3 ? 1.5 : wallH - 0.06;
        _put(l.pos, 0.4, (c, sx, sc, fy) {
          final at = Offset(sx, fy - z * sc);
          _glow(c, at, min(H * 0.5, 0.4 * sc), l.color.withValues(alpha: 0.55 * level));
          c.drawCircle(at, max(1.0, 0.05 * sc), Paint()..color = Color.lerp(l.color, Colors.white, 0.6)!.withValues(alpha: level));
        });
        continue;
      }
      if (l.along != null) {
        _shopSign(l, sign, level);
      } else {
        _hangingSign(l, sign, level);
      }
    }

    for (final b in g.bullets) {
      final col = b.fromPlayer ? const Color(0xFFFFF0A0) : const Color(0xFFFFB050);
      _put(b.pos, 0.3, (c, sx, sc, fy) {
        final at = Offset(sx, fy - 0.72 * sc);
        _glow(c, at, 0.3 * sc, col.withValues(alpha: 0.6));
        c.drawCircle(at, max(1.5, 0.04 * sc), Paint()..color = const Color(0xFFFFFFF0));
      });
    }
    for (final fl in g.flashes) {
      _put(fl.pos, 0.7, (c, sx, sc, fy) {
        _glow(c, Offset(sx, fy - 0.72 * sc), 0.7 * sc, Color.fromRGBO(255, 230, 160, (fl.t / 0.1).clamp(0.0, 1.0)));
      });
    }
    for (final s in g.sparks) {
      _put(s.pos, 0.05, (c, sx, sc, fy) {
        final sz = max(1.5, 0.05 * sc);
        c.drawRect(Rect.fromCenter(center: Offset(sx, fy - (0.4 + s.life * 0.8) * sc), width: sz, height: sz),
            Paint()..color = s.color.withValues(alpha: (s.life * 2).clamp(0.0, 1.0)));
      });
    }

    final pad = f.helipad;
    if (pad != null && g.heliT >= 0) _putHelicopter(pad);

    _items.sort((a, b) => b.depth.compareTo(a.depth));
    for (final it in _items) {
      _clipped(canvas, it);
    }
  }

  /// El helicóptero baja al helipuerto y, al final, se va contigo dentro.
  // --- Letreros ---------------------------------------------------------------------

  /// Transformación en perspectiva que lleva el rectángulo (0,0)-(lw,lh) al
  /// cuadrilátero [q] (arriba-izq, arriba-der, abajo-der, abajo-izq).
  static Float64List _quadMatrix(List<Offset> q, double lw, double lh) {
    final x0 = q[0].dx, y0 = q[0].dy, x1 = q[1].dx, y1 = q[1].dy;
    final x2 = q[2].dx, y2 = q[2].dy, x3 = q[3].dx, y3 = q[3].dy;
    final dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
    final dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
    final det = dx1 * dy2 - dx2 * dy1;
    final gg = det == 0 ? 0.0 : (dx3 * dy2 - dx2 * dy3) / det;
    final hh = det == 0 ? 0.0 : (dx1 * dy3 - dx3 * dy1) / det;
    final a = x1 - x0 + gg * x1, b = x3 - x0 + hh * x3;
    final d = y1 - y0 + gg * y1, e = y3 - y0 + hh * y3;
    return Float64List.fromList([
      a / lw, d / lw, 0, gg / lw, //
      b / lh, e / lh, 0, hh / lh,
      0, 0, 1, 0,
      x0, y0, 0, 1,
    ]);
  }

  /// Letrero de tienda: un panel oscuro colgado del techo sobre la entrada,
  /// a lo largo de la fachada, con las letras retroiluminadas.
  void _shopSign(Lamp l, String text, double level) {
    final al = l.along!;
    final c0 = l.pos;
    const zTop = 1.7, zBot = 1.36;
    // El letrero da al pasillo, hacia donde se proyecta su luz; desde dentro
    // de la tienda solo se ve la trasera.
    var lx = 0.0, ly = 0.0;
    for (final q in l.poly) {
      lx += q.dx;
      ly += q.dy;
    }
    final toHall = l.poly.isEmpty ? Offset.zero : Offset(lx / l.poly.length, ly / l.poly.length) - c0;
    final nrm = Offset(al.dy, al.dx);
    final hallSide = toHall.dx * nrm.dx + toHall.dy * nrm.dy;
    final camSide = (px - c0.dx) * nrm.dx + (py - c0.dy) * nrm.dy;
    final front = hallSide * camSide >= 0;
    // Extremos de izquierda a derecha según se mira.
    var e0 = c0 - al * l.span, e1 = c0 + al * l.span;
    if ((e0.dx - px) * rx + (e0.dy - py) * ry > (e1.dx - px) * rx + (e1.dy - py) * ry) {
      final t = e0;
      e0 = e1;
      e1 = t;
    }
    final pts = <Offset>[];
    var minD = double.infinity, x0 = double.infinity, x1 = -double.infinity;
    for (final (e, z) in [(e0, zTop), (e1, zTop), (e1, zBot), (e0, zBot)]) {
      if (!_proj(e)) return;
      minD = min(minD, _d);
      final pt = Offset(_sx, horizon - (z - eye) * _sc);
      pts.add(pt);
      x0 = min(x0, pt.dx);
      x1 = max(x1, pt.dx);
    }
    if (x1 < 0 || x0 > W || minD > 24) return;
    _lightAt(c0.dx, c0.dy);
    final body = _lit(const Color(0xFF2A2A30));
    final rim = _lit(const Color(0xFF5A5A62));
    final ink = _lit(l.color, 0.3);
    final on = level > 0.1;
    // Altura del techo en cada extremo, para las varillas.
    final ceil0 = horizon - (wallH - eye) * (pts[3].dy - pts[0].dy) / (zTop - zBot);
    final ceil1 = horizon - (wallH - eye) * (pts[2].dy - pts[1].dy) / (zTop - zBot);
    _items.add(_Item(minD, x0, x1, (c) {
      final hpx = max(pts[3].dy - pts[0].dy, pts[2].dy - pts[1].dy);
      final shape = Path()..addPolygon(pts, true);
      final rod = Paint()
        ..color = rim
        ..strokeWidth = max(1.0, hpx * 0.035);
      for (final k in [0.12, 0.88]) {
        final top = Offset.lerp(pts[0], pts[1], k)!;
        c.drawLine(top, Offset(top.dx, ui.lerpDouble(ceil0, ceil1, k)!), rod);
      }
      c.drawPath(shape, Paint()..color = body);
      c.drawPath(
          shape,
          Paint()
            ..color = rim
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.0, hpx * 0.05));
      if (!front || hpx < 5) return;
      if (on) {
        final mid = Offset.lerp(pts[0], pts[2], 0.5)!;
        _glow(c, mid, min(H * 0.5, hpx * 2.4), l.color.withValues(alpha: 0.14 * level));
      }
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w800,
            fontSize: 100,
            letterSpacing: 12,
            color: on ? Color.lerp(l.color, Colors.white, 0.35)!.withValues(alpha: 0.45 + 0.55 * level) : ink,
            shadows: on ? [Shadow(color: l.color, blurRadius: 24 * level)] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final lh = tp.height * 1.3;
      final lw = lh * (2 * l.span) / (zTop - zBot);
      final k = min(1.0, 0.86 * lw / tp.width);
      c.save();
      c.transform(_quadMatrix(pts, lw, lh));
      c.translate(lw / 2, lh / 2);
      c.scale(k);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
      tp.dispose();
    }));
  }

  /// SALIDA, ASCENSOR: una caja luminosa colgada del techo, como las de verdad.
  void _hangingSign(Lamp l, String text, double level) {
    final on = level > 0.1;
    final w = text.length * 0.075 + 0.14;
    _lightAt(l.pos.dx, l.pos.dy);
    final frame = _lit(const Color(0xFF3A3A40));
    final dark = _lit(l.color, 0.25);
    final grey = _lit(const Color(0xFF9A9A9A), 0.6);
    _put(l.pos, w / 2, (c, sx, sc, fy) {
      final top = fy - 1.66 * sc, bot = fy - 1.45 * sc;
      final ceil = fy - wallH * sc;
      final box = Rect.fromLTRB(sx - w / 2 * sc, top, sx + w / 2 * sc, bot);
      final rod = Paint()
        ..color = frame
        ..strokeWidth = max(1.0, 0.012 * sc);
      for (final k in [-0.3, 0.3]) {
        c.drawLine(Offset(sx + k * w * sc, top), Offset(sx + k * w * sc, ceil), rod);
      }
      if (on) _glow(c, box.center, min(H * 0.4, w * 0.5 * sc), l.color.withValues(alpha: 0.25 * level));
      c.drawRect(box.inflate(max(1.0, 0.015 * sc)), Paint()..color = frame);
      c.drawRect(box, Paint()..color = on ? Color.lerp(const Color(0xFF101010), l.color, 0.75 * level)! : dark);
      final fs = (bot - top) * 0.62;
      if (fs < 4) return;
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w800,
            fontSize: fs,
            letterSpacing: fs * 0.08,
            color: on ? Colors.white.withValues(alpha: 0.6 + 0.4 * level) : grey,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final k = min(1.0, box.width * 0.9 / tp.width);
      c.save();
      c.translate(box.center.dx, box.center.dy);
      c.scale(k);
      tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
      c.restore();
      tp.dispose();
    });
  }

  void _putHelicopter(Offset pad) {
    var alt = (1 - g.heliT / Game.heliLandTime).clamp(0.0, 1.0);
    if (g.won) alt = min(1.5, g.endT * 0.35);
    _put(pad, 2.4, (c, sx, sc, fy) {
      final base = fy - (0.15 + alt * 7) * sc;
      final dark = Paint()..color = const Color(0xFF1E2A22);
      // Patines, cola y cabina.
      c.drawRect(Rect.fromLTRB(sx - 0.8 * sc, base - 0.06 * sc, sx + 0.8 * sc, base), dark);
      c.drawRect(Rect.fromLTRB(sx + 0.6 * sc, base - 0.95 * sc, sx + 2.2 * sc, base - 0.75 * sc), dark);
      c.drawRect(Rect.fromLTRB(sx + 2.05 * sc, base - 1.35 * sc, sx + 2.2 * sc, base - 0.6 * sc), dark);
      c.drawOval(Rect.fromLTRB(sx - 1.0 * sc, base - 1.4 * sc, sx + 0.9 * sc, base - 0.1 * sc), dark);
      c.drawOval(Rect.fromLTRB(sx - 0.9 * sc, base - 1.25 * sc, sx - 0.1 * sc, base - 0.6 * sc),
          Paint()..color = const Color(0xFF3A5A6A));
      // Rotor girando.
      final top = Offset(sx, base - 1.55 * sc);
      c.drawRect(Rect.fromLTRB(sx - 0.05 * sc, top.dy, sx + 0.05 * sc, base - 1.35 * sc), dark);
      c.drawOval(Rect.fromCenter(center: top, width: 4.4 * sc, height: 0.25 * sc), Paint()..color = const Color(0x22FFFFFF));
      final reach = cos(g.time * 28) * 2.2 * sc;
      c.drawLine(
          top - Offset(reach, 0),
          top + Offset(reach, 0),
          Paint()
            ..color = const Color(0xAA101010)
            ..strokeWidth = max(1.5, 0.06 * sc));
      if ((g.time * 2).floor() % 2 == 0) {
        final light = Offset(sx + 2.12 * sc, base - 1.35 * sc);
        c.drawCircle(light, max(2.0, 0.08 * sc), Paint()..color = const Color(0xFFFF2020));
        _glow(c, light, 0.5 * sc, const Color(0x88FF2020));
      }
    });
  }

  // --- Sobre la pantalla ---------------------------------------------------------

  /// Motas de polvo flotando en el haz de la linterna.
  void _dust(Canvas c) {
    if (g.flashPower < 0.1 || roof) return;
    final t = g.time;
    final paint = Paint()..blendMode = BlendMode.plus;
    final center = Offset(W / 2, horizon);
    final reach = H * 0.62;
    for (var i = 0; i < 70; i++) {
      final a = ((i * 2654435761) & 0xFFFF) / 0xFFFF;
      final b = ((i * 40503 + 12345) & 0xFFFF) / 0xFFFF;
      final deep = 0.4 + b * 0.6; // las lejanas se mueven menos al girar
      final x = (a * W * 1.7 - g.p.angle * focal * deep + sin(t * (0.2 + b * 0.3) + a * 6) * 14) % W;
      final y = (b * H * 1.3 + t * (4 + a * 9) - g.p.walkPhase * 2 * deep) % H;
      final d = (Offset(x, y) - center).distance;
      if (d > reach) continue;
      final twinkle = 0.5 + 0.5 * sin(t * (1 + b * 2) + a * 9);
      final alpha = (1 - d / reach) * 0.5 * twinkle * g.flashPower;
      if (alpha < 0.03) continue;
      final sz = 1.2 + (1 - deep) * 2.2;
      c.drawRect(Rect.fromCenter(center: Offset(x, y), width: sz, height: sz),
          paint..color = Color.fromRGBO(255, 245, 220, alpha));
    }
  }

  /// El arma en la mano, abajo, con el vaivén de andar.
  void _weapon(Canvas c) {
    final p = g.p;
    final gun = p.hasPistol && p.ammo > 0;
    if (!gun && !p.hasPipe) return;
    final u = H * 0.011;
    final sway = Offset(sin(p.walkPhase * 1.5) * u * 1.6, cos(p.walkPhase * 3).abs() * u * 1.2);
    const skin = Color(0xFFB8875A), sleeve = Color(0xFF34492F);
    final paint = Paint();
    if (gun) {
      final rec = (p.shotT / 0.18).clamp(0.0, 1.0);
      final o = Offset(W * 0.57, H - rec * u * 5) + sway;
      c.drawRect(Rect.fromLTRB(o.dx - 7 * u, o.dy - 9 * u, o.dx + 7 * u, o.dy + 6 * u), paint..color = sleeve);
      c.drawRect(Rect.fromLTRB(o.dx - 6 * u, o.dy - 17 * u, o.dx + 6 * u, o.dy - 8 * u), paint..color = skin);
      c.drawRect(Rect.fromLTRB(o.dx - 3.2 * u, o.dy - 31 * u, o.dx + 3.2 * u, o.dy - 13 * u), paint..color = const Color(0xFF1A1A1E));
      c.drawRect(Rect.fromLTRB(o.dx - 3.2 * u, o.dy - 31 * u, o.dx + 3.2 * u, o.dy - 29.5 * u), paint..color = const Color(0xFF3A3A42));
      c.drawRect(Rect.fromLTRB(o.dx - 0.7 * u, o.dy - 32.5 * u, o.dx + 0.7 * u, o.dy - 31 * u), paint..color = const Color(0xFF0A0A0C));
      c.drawRect(Rect.fromLTRB(o.dx - 6 * u, o.dy - 14 * u, o.dx - 3.2 * u, o.dy - 10 * u), paint..color = const Color(0xFF9A6E46));
      if (g.muzzleFlash > 0) {
        final k = (g.muzzleFlash / 0.12).clamp(0.0, 1.0);
        final m = Offset(o.dx, o.dy - 35 * u);
        _glow(c, m, 26 * u, Color.fromRGBO(255, 200, 120, 0.55 * k));
        _glow(c, m, 9 * u, Color.fromRGBO(255, 245, 190, k));
      }
      return;
    }
    // Barra de hierro: al golpear cruza la pantalla de derecha a izquierda.
    final sw = (p.swingT / 0.25).clamp(0.0, 1.0);
    final hand = Offset(W * 0.63 - sw * W * 0.06, H + 2 * u) + sway;
    final a = -pi / 2 - 0.45 - sin(sw * pi) * 1.1;
    final tip = hand + Offset(cos(a), sin(a)) * (40 * u);
    c.drawLine(
        hand,
        tip,
        paint
          ..color = const Color(0xFF3E4146)
          ..strokeWidth = 3.4 * u
          ..strokeCap = StrokeCap.square);
    c.drawLine(hand, tip, paint
      ..color = const Color(0xFF7A7E86)
      ..strokeWidth = 1.6 * u);
    c.drawRect(Rect.fromCenter(center: hand + Offset(cos(a), sin(a)) * (6 * u), width: 9 * u, height: 9 * u),
        Paint()..color = skin);
  }

  /// Punto de mira y aviso de que un sicario te está apuntando.
  void _aimWarning(Canvas c) {
    if (g.won || g.lost || g.hiding != null) return;
    if (g.armed) c.drawCircle(Offset(W / 2, H / 2), 1.6, Paint()..color = const Color(0x66FFFFFF));
    if (!f.enemies.any((e) => e.state == EState.aim)) return;
    // El punto rojo de la mira sobre tu pecho.
    final at = Offset(W / 2, H * 0.84);
    c.drawCircle(at, 4 + 2 * sin(g.time * 30), Paint()..color = const Color(0xFFFF2020));
    _glow(c, at, H * 0.09, const Color(0x88FF2020));
  }
}
