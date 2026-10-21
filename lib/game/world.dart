import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

const int mapW = 61;
const int mapH = 41;
const int floorCount = 8;
const int garageFloor = 0;
const int groundFloor = 1;
const int roofFloor = floorCount - 1;

/// Tiendas mínimas por planta comercial.
const int minRooms = 10;

/// Balas que aguanta el jefe.
const double bossHp = 10;

const floorNames = [
  'Garaje',
  'Planta baja',
  'Primera planta',
  'Segunda planta',
  'Tercera planta',
  'Cuarta planta',
  'Quinta planta',
  'Azotea',
];

enum Tile { wall, floor, shop, stairUp, stairDown, elevator, car }

enum ItemType { water, food, medkit, bandage, painkiller, pills, pistol, ammo, pipe, manuscript, glasses }

class ItemInfo {
  final String name;
  final String icon;
  const ItemInfo(this.name, this.icon);
}

const itemInfo = {
  ItemType.water: ItemInfo('Agua', 'water'),
  ItemType.food: ItemInfo('Comida', 'food'),
  ItemType.medkit: ItemInfo('Botiquín', 'medkit'),
  ItemType.bandage: ItemInfo('Vendas', 'bandage'),
  ItemType.painkiller: ItemInfo('Analgésicos', 'painkiller'),
  ItemType.pills: ItemInfo('Pastillas sin etiqueta', 'pills'),
  ItemType.pistol: ItemInfo('Pistola', 'pistol'),
  ItemType.ammo: ItemInfo('Munición', 'ammo'),
  ItemType.pipe: ItemInfo('Barra de hierro', 'pipe'),
  // Escrito con tinta invisible: parece una hoja en blanco.
  ItemType.manuscript: ItemInfo('Hoja en blanco', 'sheet'),
  ItemType.glasses: ItemInfo('Gafas', 'glasses'),
};

const crateNames = ['estantería', 'máquina expendedora', 'mostrador', 'papelera', 'armario', 'coche'];
const int carCrate = 5;

const shopSigns = [
  'CINE', 'MODA', 'JUGUETES', 'BURGER', 'ZAPATOS', 'LIBROS', 'JOYAS', 'DEPORTES',
  'MÚSICA', 'PERFUMES', 'ÓPTICA', 'PIZZA', 'GAMES', 'BAZAR', 'FARMACIA', 'CAFÉ',
];

class Crate {
  final Offset pos;
  final int kind;
  ItemType? loot;
  bool rat = false;
  bool searched = false;
  Crate(this.pos, this.kind);
}

class Pc {
  final Offset pos;
  bool working = false;
  bool used = false;
  final double phase;
  Pc(this.pos, this.phase);
}

class Mannequin {
  Offset pos;
  double angle;
  bool screamer = false;
  bool fallen = false;
  double moveT;
  Mannequin(this.pos, this.angle, this.moveT);
}

/// Lámpara o neón. Las que tienen [sign] son letreros de tienda.
class Lamp {
  final Offset pos;
  final double radius;
  final int mode; // 0 estable, 1 parpadeo, 2 revienta al acercarse
  final String? sign;
  final Color color;
  bool alive = true;
  double level = 1;
  double timer = 0;
  List<Offset> poly = const [];
  Lamp(this.pos, this.radius, this.mode, this.color, {this.sign});
}

enum EState { patrol, chase, aim, flee, dead }

class Enemy {
  Offset pos;
  double angle;
  int hp = 2;
  EState state = EState.patrol;
  List<Point<int>> path = [];
  Point<int>? goal;
  double repath = 0;
  double aimT = 0;
  double shootCd = 1;
  double fleeT = 0;
  double fear = 0;
  Offset lastKnown = Offset.zero;
  double unseenT = 99;
  double stepT = 0;
  double deadT = 0;
  double fade = 1;
  bool moving = false;
  List<Offset> light = const [];
  final double cigPhase;
  bool fearless = false; // los de la azotea no huyen
  Enemy(this.pos, this.angle, this.cigPhase);
  bool get alive => state != EState.dead;
}

/// El guardián de la caja: un tipo enorme con un cuchillo.
class Boss {
  Offset pos;
  double angle = pi / 2;
  double hp = bossHp;
  double windup = 0; // >0: levantando el cuchillo
  double cooldown = 1;
  double stagger = 0;
  double repath = 0;
  double deadT = 0;
  List<Point<int>> path = [];
  bool moving = false;
  Boss(this.pos);
  bool get alive => hp > 0;
}

/// Coche aparcado en el garaje: ocupa dos casillas en vertical.
class Car {
  final Point<int> tile;
  final int color;
  Crate? crate; // se puede registrar
  Car(this.tile, this.color);
  Offset get center => Offset(tile.x + 0.5, tile.y + 1.0);
}

/// Tienda. Algunas tienen interruptor: luz completa, pero atrae a los sicarios.
class Room {
  final Rect rect;
  Offset? switchPos;
  bool lit = false;
  List<Offset> poly = const [];
  Room(this.rect);
}

/// Escondite: taquilla (0) o probador (1).
class HideSpot {
  final Offset pos;
  final int kind;
  HideSpot(this.pos, this.kind);
  String get name => kind == 0 ? 'la taquilla' : 'el probador';
}

class GroundItem {
  final Offset pos;
  final ItemType type;
  GroundItem(this.pos, this.type);
}

class Decal {
  final Offset pos;
  final int kind; // 0 sangre, 1 cristales, 2 papeles, 3 grafiti
  final double rot, size;
  final int seed;
  Decal(this.pos, this.kind, this.rot, this.size, this.seed);
}

class FloorData {
  final int index;
  final List<Tile> tiles = List.filled(mapW * mapH, Tile.wall);
  final List<Room> rooms = [];
  final List<(List<Point<int>>, Point<int>)> doors = [];
  final List<Point<int>> rubble = [];
  final List<Crate> crates = [];
  final List<Pc> pcs = [];
  final List<HideSpot> hideSpots = [];
  final List<Mannequin> mannequins = [];
  final List<Lamp> lamps = [];
  final List<Enemy> enemies = [];
  final List<GroundItem> items = [];
  final List<Decal> decals = [];
  final Set<int> explored = {};
  Point<int>? up, down, elevator;
  bool elevatorWorks = true;
  final List<Car> cars = [];
  Offset? box;
  Boss? boss;
  Offset? helipad;
  List<Offset> boxPoly = const [];
  double spawnTimer = 60;
  int enemyCap = 3;
  bool firstVisit = true;
  late final List<Point<int>> freeTiles;

  FloorData(this.index);

  Tile at(int x, int y) => (x < 0 || y < 0 || x >= mapW || y >= mapH) ? Tile.wall : tiles[y * mapW + x];
  void set(int x, int y, Tile t) => tiles[y * mapW + x] = t;
  bool solidAt(int x, int y) {
    final t = at(x, y);
    return t == Tile.wall || t == Tile.car;
  }

  /// Los coches no tapan la luz ni la vista: solo las paredes.
  bool opaqueAt(int x, int y) => at(x, y) == Tile.wall;
  bool solidPos(Offset p) => solidAt(p.dx.floor(), p.dy.floor());
}

// --- Geometría -------------------------------------------------------------

Offset tileCenter(Point<int> t) => Offset(t.x + 0.5, t.y + 0.5);
Point<int> tileOf(Offset p) => Point(p.dx.floor(), p.dy.floor());

double angleDiff(double a, double b) {
  var d = (a - b) % (2 * pi);
  if (d > pi) d -= 2 * pi;
  if (d < -pi) d += 2 * pi;
  return d.abs();
}

double lerpAngle(double a, double b, double t) {
  var d = (b - a) % (2 * pi);
  if (d > pi) d -= 2 * pi;
  if (d < -pi) d += 2 * pi;
  return a + d * t.clamp(0.0, 1.0);
}

/// Lanza un rayo por la rejilla (DDA) y devuelve la distancia hasta la pared.
double castRay(FloorData f, double ox, double oy, double dx, double dy, double maxD,
    [void Function(int x, int y)? visit]) {
  var mx = ox.floor(), my = oy.floor();
  final ddx = dx == 0 ? 1e30 : (1 / dx).abs();
  final ddy = dy == 0 ? 1e30 : (1 / dy).abs();
  int sx, sy;
  double sdx, sdy;
  if (dx < 0) {
    sx = -1;
    sdx = (ox - mx) * ddx;
  } else {
    sx = 1;
    sdx = (mx + 1 - ox) * ddx;
  }
  if (dy < 0) {
    sy = -1;
    sdy = (oy - my) * ddy;
  } else {
    sy = 1;
    sdy = (my + 1 - oy) * ddy;
  }
  visit?.call(mx, my);
  while (true) {
    double d;
    if (sdx < sdy) {
      d = sdx;
      sdx += ddx;
      mx += sx;
    } else {
      d = sdy;
      sdy += ddy;
      my += sy;
    }
    if (d > maxD) return maxD;
    if (f.opaqueAt(mx, my)) {
      visit?.call(mx, my);
      return d;
    }
    visit?.call(mx, my);
  }
}

bool lineOfSight(FloorData f, Offset a, Offset b) {
  final d = (b - a).distance;
  if (d < 0.01) return true;
  final dir = (b - a) / d;
  return castRay(f, a.dx, a.dy, dir.dx, dir.dy, d) >= d - 0.02;
}

List<Offset> lightPolygon(FloorData f, Offset o, double radius, int rays,
    {double startAngle = 0, double sweep = 2 * pi, void Function(int, int)? visit}) {
  final pts = <Offset>[];
  final full = sweep >= 2 * pi - 0.001;
  if (!full) pts.add(o);
  for (var i = 0; i <= rays; i++) {
    final a = startAngle + sweep * i / rays;
    final dx = cos(a), dy = sin(a);
    final d = castRay(f, o.dx, o.dy, dx, dy, radius, visit);
    pts.add(Offset(o.dx + dx * d, o.dy + dy * d));
  }
  return pts;
}

bool collides(FloorData f, double x, double y, double r) {
  for (var ty = (y - r).floor(); ty <= (y + r).floor(); ty++) {
    for (var tx = (x - r).floor(); tx <= (x + r).floor(); tx++) {
      if (f.solidAt(tx, ty)) return true;
    }
  }
  return false;
}

Offset moveWithCollision(FloorData f, Offset p, Offset delta, double r) {
  var x = p.dx, y = p.dy;
  if (!collides(f, x + delta.dx, y, r)) x += delta.dx;
  if (!collides(f, x, y + delta.dy, r)) y += delta.dy;
  return Offset(x, y);
}

List<Point<int>> findPath(FloorData f, Point<int> s, Point<int> t) {
  if (f.solidAt(t.x, t.y) || f.solidAt(s.x, s.y)) return [];
  if (s == t) return [];
  final prev = Int32List(mapW * mapH)..fillRange(0, mapW * mapH, -1);
  final start = s.y * mapW + s.x, goal = t.y * mapW + t.x;
  final queue = <int>[start];
  prev[start] = start;
  var head = 0;
  const dirs = [1, 0, -1, 0, 0, 1, 0, -1];
  while (head < queue.length) {
    final c = queue[head++];
    if (c == goal) break;
    final cx = c % mapW, cy = c ~/ mapW;
    for (var k = 0; k < 8; k += 2) {
      final nx = cx + dirs[k], ny = cy + dirs[k + 1];
      if (f.solidAt(nx, ny)) continue;
      final n = ny * mapW + nx;
      if (prev[n] != -1) continue;
      prev[n] = c;
      queue.add(n);
    }
  }
  if (prev[goal] == -1) return [];
  final out = <Point<int>>[];
  var c = goal;
  while (c != start) {
    out.add(Point(c % mapW, c ~/ mapW));
    c = prev[c];
  }
  return out.reversed.toList();
}

// --- Generación -------------------------------------------------------------

class World {
  final List<FloorData> floors;
  final Offset start;
  final int boxFloor;
  final int manuscriptFloor;
  final int glassesFloor;
  World(this.floors, this.start, this.boxFloor, this.manuscriptFloor, this.glassesFloor);
}

const startTile = Point(30, 37);

/// Galerías comunes a todas las plantas: (inicio, ancho).
class _Layout {
  final List<(int, int)> vertical;
  final List<(int, int)> horizontal;
  final Rect atrium;
  _Layout(this.vertical, this.horizontal, this.atrium);

  bool isCorridor(int x, int y) {
    if (x < 2 || x > mapW - 3 || y < 2 || y > mapH - 3) return false;
    for (final (x0, w) in vertical) {
      if (x >= x0 && x < x0 + w) return true;
    }
    for (final (y0, w) in horizontal) {
      if (y >= y0 && y < y0 + w) return true;
    }
    return false;
  }

  bool inAtrium(int x, int y) => atrium.contains(Offset(x + 0.5, y + 0.5));
}

_Layout _makeLayout(Random rng) {
  int j() => rng.nextInt(3) - 1;
  return _Layout(
    [(2, 3), (19 + j(), 3), (39 + j(), 3), (56, 3)],
    [(2, 3), (19 + j(), 3), (36, 3)],
    const Rect.fromLTRB(24, 12, 37, 29),
  );
}

void _carveFloor(FloorData f, _Layout l, Random rng) {
  for (var y = 0; y < mapH; y++) {
    for (var x = 0; x < mapW; x++) {
      if (l.isCorridor(x, y)) f.set(x, y, Tile.floor);
    }
  }
  // Manzanas entre galerías, divididas en tiendas.
  final leaves = <Rect>[];
  void split(int x0, int y0, int x1, int y1) {
    final w = x1 - x0 + 1, h = y1 - y0 + 1;
    final canV = w >= 12, canH = h >= 12;
    if ((canV || canH) && !(w < 15 && h < 15 && rng.nextDouble() < 0.25)) {
      if (canV && (!canH || w >= h)) {
        final sx = x0 + 5 + rng.nextInt(w - 10);
        split(x0, y0, sx, y1);
        split(sx, y0, x1, y1);
      } else {
        final sy = y0 + 5 + rng.nextInt(h - 10);
        split(x0, y0, x1, sy);
        split(x0, sy, x1, y1);
      }
      return;
    }
    leaves.add(Rect.fromLTRB(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble()));
  }

  final vs = l.vertical, hs = l.horizontal;
  for (var i = 0; i + 1 < vs.length; i++) {
    for (var k = 0; k + 1 < hs.length; k++) {
      final x0 = vs[i].$1 + vs[i].$2, x1 = vs[i + 1].$1 - 1;
      final y0 = hs[k].$1 + hs[k].$2, y1 = hs[k + 1].$1 - 1;
      split(x0, y0, x1, y1);
    }
  }
  for (final r in leaves) {
    for (var y = r.top.toInt() + 1; y < r.bottom.toInt(); y++) {
      for (var x = r.left.toInt() + 1; x < r.right.toInt(); x++) {
        f.set(x, y, Tile.shop);
      }
    }
    // Rectángulo interior en coordenadas de mundo.
    f.rooms.add(Room(Rect.fromLTRB(r.left + 1, r.top + 1, r.right, r.bottom)));
  }
  // Puertas: preferimos que den a una galería.
  for (var ri = 0; ri < leaves.length; ri++) {
    final r = leaves[ri];
    final x0 = r.left.toInt(), y0 = r.top.toInt(), x1 = r.right.toInt(), y1 = r.bottom.toInt();
    final options = <(List<Point<int>>, Point<int>, bool)>[];
    void side(List<Point<int>> wall, Point<int> out) {
      for (var i = 1; i + 2 < wall.length; i++) {
        final a = wall[i], b = wall[i + 1];
        final oa = f.at(a.x + out.x, a.y + out.y), ob = f.at(b.x + out.x, b.y + out.y);
        final ia = f.at(a.x - out.x, a.y - out.y), ib = f.at(b.x - out.x, b.y - out.y);
        if (oa == Tile.wall || ob == Tile.wall || ia == Tile.wall || ib == Tile.wall) continue;
        options.add(([a, b], out, oa == Tile.floor && ob == Tile.floor));
      }
    }

    side([for (var x = x0; x <= x1; x++) Point(x, y0)], const Point(0, -1));
    side([for (var x = x0; x <= x1; x++) Point(x, y1)], const Point(0, 1));
    side([for (var y = y0; y <= y1; y++) Point(x0, y)], const Point(-1, 0));
    side([for (var y = y0; y <= y1; y++) Point(x1, y)], const Point(1, 0));
    if (options.isEmpty) continue;
    final toCorridor = options.where((o) => o.$3).toList();
    final pool = toCorridor.isNotEmpty ? toCorridor : options;
    final doors = toCorridor.length > 6 && rng.nextDouble() < 0.4 ? 2 : 1;
    for (var d = 0; d < doors; d++) {
      final o = pool[rng.nextInt(pool.length)];
      for (final t in o.$1) {
        f.set(t.x, t.y, Tile.shop);
      }
      if (o.$3) f.doors.add((o.$1, o.$2));
      // Interruptor junto a la primera puerta, por dentro.
      final room = f.rooms[ri];
      if (d == 0 && room.switchPos == null && rng.nextDouble() < 0.4) {
        final a = o.$1.first;
        final side = Point(o.$2.y.abs(), o.$2.x.abs()); // perpendicular a la salida
        final inside = Point(a.x - o.$2.x - side.x, a.y - o.$2.y - side.y);
        if (f.at(inside.x, inside.y) == Tile.shop) room.switchPos = tileCenter(inside);
      }
    }
  }
  // Atrio con columnas y claraboya.
  for (var y = l.atrium.top.toInt(); y < l.atrium.bottom.toInt(); y++) {
    for (var x = l.atrium.left.toInt(); x < l.atrium.right.toInt(); x++) {
      final pillar = (x - l.atrium.left.toInt()) % 4 == 2 && (y - l.atrium.top.toInt()) % 4 == 2;
      f.set(x, y, pillar ? Tile.wall : Tile.floor);
    }
  }
  // Las tiendas que el atrio ha abierto dejan de tener interruptor propio.
  f.rooms.removeWhere((r) => r.rect.overlaps(l.atrium));
}

Set<Point<int>> _reachable(FloorData f, Point<int> from) {
  final seen = <Point<int>>{from};
  final q = [from];
  for (var h = 0; h < q.length; h++) {
    final c = q[h];
    for (final d in const [Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1)]) {
      final n = Point(c.x + d.x, c.y + d.y);
      if (f.solidAt(n.x, n.y) || !seen.add(n)) continue;
      q.add(n);
    }
  }
  return seen;
}

int _countReachable(FloorData f, Point<int> from) => _reachable(f, from).length;

/// Planta comercial con al menos [minRooms] tiendas a las que se puede entrar.
void _carveMall(FloorData f, _Layout l, Random rng) {
  final probe = Point(l.vertical.first.$1 + 1, l.horizontal.first.$1 + 1);
  for (var attempt = 0; attempt < 80; attempt++) {
    f.tiles.fillRange(0, f.tiles.length, Tile.wall);
    f.rooms.clear();
    f.doors.clear();
    _carveFloor(f, l, rng);
    final reach = _reachable(f, probe);
    if (f.rooms.where((r) => reach.contains(tileOf(r.rect.center))).length >= minRooms) return;
  }
}

/// Garaje: una fila de trasteros arriba y el aparcamiento lleno de coches.
void _carveGarage(FloorData f, Random rng, Set<Point<int>> clear) {
  for (var y = 8; y < mapH - 1; y++) {
    for (var x = 1; x < mapW - 1; x++) {
      f.set(x, y, Tile.floor);
    }
  }
  for (var i = 0; i < 10; i++) {
    final x0 = 1 + i * 6;
    for (var y = 1; y <= 6; y++) {
      for (var x = x0; x < x0 + 5; x++) {
        f.set(x, y, Tile.shop);
      }
    }
    f.set(x0 + 2, 7, Tile.shop);
    final room = Room(Rect.fromLTRB(x0.toDouble(), 1, x0 + 5.0, 7));
    if (rng.nextDouble() < 0.4) room.switchPos = tileCenter(Point(x0 + 1, 6));
    f.rooms.add(room);
  }
  // Escalera y ascensor siempre comunicados con el aparcamiento.
  for (final c in clear) {
    for (var y = c.y; y <= 8; y++) {
      if (f.at(c.x, y) == Tile.wall) f.set(c.x, y, Tile.floor);
    }
  }
  bool nearClear(int x, int y) => clear.any((c) => (c.x - x).abs() <= 2 && (c.y - y).abs() <= 2);
  for (final row in const [11, 17, 23, 29, 35]) {
    for (var x = 3; x <= mapW - 4; x += 2) {
      if (nearClear(x, row) || nearClear(x, row + 1)) continue;
      if (x % 10 == 9) {
        // Columna de hormigón.
        f.set(x, row, Tile.wall);
        f.set(x, row + 1, Tile.wall);
        continue;
      }
      if (rng.nextDouble() < 0.3) continue;
      f.set(x, row, Tile.car);
      f.set(x, row + 1, Tile.car);
      f.cars.add(Car(Point(x, row), rng.nextInt(6)));
    }
  }
}

/// Azotea: aire libre, máquinas de aire acondicionado y el helipuerto.
void _carveRoof(FloorData f, Random rng, Point<int> stair) {
  for (var y = 1; y < mapH - 1; y++) {
    for (var x = 1; x < mapW - 1; x++) {
      f.set(x, y, Tile.floor);
    }
  }
  Point<int> pad = const Point(mapW - 10, 8);
  for (var i = 0; i < 300; i++) {
    final t = Point(8 + rng.nextInt(mapW - 16), 7 + rng.nextInt(mapH - 14));
    if ((t - stair).magnitude >= 24) {
      pad = t;
      break;
    }
  }
  f.helipad = tileCenter(pad);
  final total = _countReachable(f, stair);
  var reach = total;
  for (var i = 0; i < 40; i++) {
    final w = 2 + rng.nextInt(3), h = 2 + rng.nextInt(2);
    final x = 2 + rng.nextInt(mapW - 4 - w), y = 2 + rng.nextInt(mapH - 4 - h);
    if (x + w + 3 > stair.x && x - 3 < stair.x && y + h + 3 > stair.y && y - 3 < stair.y) continue;
    if (x + w + 4 > pad.x && x - 4 < pad.x && y + h + 4 > pad.y && y - 4 < pad.y) continue;
    final cells = [
      for (var yy = y; yy < y + h; yy++)
        for (var xx = x; xx < x + w; xx++) Point(xx, yy),
    ];
    if (cells.any((c) => f.at(c.x, c.y) != Tile.floor)) continue;
    for (final c in cells) {
      f.set(c.x, c.y, Tile.wall);
    }
    // Ninguna máquina puede dejar zonas encerradas.
    final now = _countReachable(f, stair);
    if (now == reach - cells.length) {
      reach = now;
    } else {
      for (final c in cells) {
        f.set(c.x, c.y, Tile.floor);
      }
    }
  }
}

/// Escombros que cortan galerías: el centro comercial se vuelve un laberinto
/// sin perder la conexión entre todas las zonas.
void _barricades(FloorData f, _Layout l, Random rng, Set<Point<int>> keep, Point<int> anchor) {
  // Las tiendas sin puerta se quedan aisladas: su interior no cuenta.
  var total = _countReachable(f, anchor);
  var placed = 0;
  for (var attempt = 0; attempt < 40 && placed < 6; attempt++) {
    final cells = <Point<int>>[];
    if (rng.nextBool()) {
      final (x0, w) = l.vertical[rng.nextInt(l.vertical.length)];
      final y = 6 + rng.nextInt(mapH - 12);
      for (var x = x0; x < x0 + w; x++) {
        cells.add(Point(x, y));
      }
    } else {
      final (y0, w) = l.horizontal[rng.nextInt(l.horizontal.length)];
      final x = 6 + rng.nextInt(mapW - 12);
      for (var y = y0; y < y0 + w; y++) {
        cells.add(Point(x, y));
      }
    }
    if (cells.any((c) =>
        f.solidAt(c.x, c.y) ||
        l.inAtrium(c.x, c.y) ||
        keep.any((k) => (k.x - c.x).abs() + (k.y - c.y).abs() < 4))) {
      continue;
    }
    final before = [for (final c in cells) f.at(c.x, c.y)];
    for (final c in cells) {
      f.set(c.x, c.y, Tile.wall);
    }
    if (_countReachable(f, anchor) == total - cells.length) {
      total -= cells.length;
      placed++;
      f.rubble.addAll(cells);
    } else {
      for (var i = 0; i < cells.length; i++) {
        f.set(cells[i].x, cells[i].y, before[i]);
      }
    }
  }
}

/// Por dónde se entra a cada planta.
Point<int> arrivalTile(FloorData f) => switch (f.index) {
      groundFloor => startTile,
      garageFloor => f.up!,
      _ => f.down!,
    };

World generateWorld(Random rng) {
  final layout = _makeLayout(rng);
  final floors = List.generate(floorCount, FloorData.new);
  for (final f in floors) {
    if (f.index != garageFloor && f.index != roofFloor) _carveMall(f, layout, rng);
  }
  final start = tileCenter(startTile);

  double dist(Point<int> a, Point<int> b) => sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
  final corridorTiles = [
    for (var y = 0; y < mapH; y++)
      for (var x = 0; x < mapW; x++)
        if (layout.isCorridor(x, y) && !layout.inAtrium(x, y)) Point(x, y),
  ];
  Point<int> pickCorridor(bool Function(Point<int>) ok) {
    for (var i = 0; i < 800; i++) {
      final t = corridorTiles[rng.nextInt(corridorTiles.length)];
      if (ok(t)) return t;
    }
    return corridorTiles[rng.nextInt(corridorTiles.length)];
  }

  // Ascensor: misma posición en todas las plantas, menos en la azotea.
  final elevator = pickCorridor((t) => dist(t, startTile) >= 9 && dist(t, startTile) <= 22);
  // Escaleras mecánicas: misma posición entre plantas contiguas.
  for (var fi = groundFloor; fi < floorCount - 1; fi++) {
    final from = fi == groundFloor ? startTile : floors[fi].down!;
    final t = pickCorridor((t) => dist(t, from) >= 24 && dist(t, elevator) >= 6);
    floors[fi].up = t;
    floors[fi + 1].down = t;
  }
  // Rampa al garaje.
  final ramp = pickCorridor((t) =>
      dist(t, startTile) >= 16 && dist(t, floors[groundFloor].up!) >= 10 && dist(t, elevator) >= 6);
  floors[garageFloor].up = ramp;
  floors[groundFloor].down = ramp;
  _carveGarage(floors[garageFloor], rng, {ramp, elevator});
  _carveRoof(floors[roofFloor], rng, floors[roofFloor].down!);

  for (final f in floors) {
    if (f.up != null) f.set(f.up!.x, f.up!.y, Tile.stairUp);
    if (f.down != null) f.set(f.down!.x, f.down!.y, Tile.stairDown);
    if (f.index != roofFloor) {
      f.elevator = elevator;
      f.set(elevator.x, elevator.y, Tile.elevator);
    }
  }
  // El ascensor no para en dos plantas.
  final broken = [for (var i = 0; i < roofFloor; i++) if (i != groundFloor) i]..shuffle(rng);
  for (final i in broken.take(2)) {
    floors[i].elevatorWorks = false;
  }

  for (final f in floors) {
    final anchor = arrivalTile(f);
    if (f.index != garageFloor && f.index != roofFloor) {
      _barricades(f, layout, rng, {startTile, ?f.up, ?f.down, elevator}, anchor);
    }
    // Solo casillas alcanzables: nada de objetos en tiendas tapiadas.
    final seen = _reachable(f, anchor);
    f.freeTiles = [
      for (final t in seen)
        if (f.at(t.x, t.y) == Tile.floor || f.at(t.x, t.y) == Tile.shop) t,
    ];
    f.rooms.removeWhere((r) => !seen.contains(tileOf(r.rect.center)));
    for (final r in f.rooms) {
      if (r.switchPos != null && !seen.contains(tileOf(r.switchPos!))) r.switchPos = null;
    }
  }

  final boxFloor = groundFloor + 1 + rng.nextInt(roofFloor - groundFloor - 1);

  final allCrates = <Crate>[];
  final allPcs = <Pc>[];
  for (final f in floors) {
    final roof = f.index == roofFloor, garage = f.index == garageFloor;
    final taken = <Point<int>>{?f.elevator};
    for (final r in f.rooms) {
      if (r.switchPos != null) taken.add(tileOf(r.switchPos!));
    }
    final arrival = arrivalTile(f);
    bool ok(Point<int> t, double minArrival) =>
        !taken.contains(t) &&
        dist(t, arrival) >= minArrival &&
        (f.up == null || dist(t, f.up!) >= 1.5) &&
        (f.elevator == null || dist(t, f.elevator!) >= 1.5);
    Point<int> pick({double minArrival = 2, bool shopOnly = false, bool corridorOnly = false, bool nearWall = false}) {
      for (var i = 0; i < 600; i++) {
        final t = f.freeTiles[rng.nextInt(f.freeTiles.length)];
        final tile = f.at(t.x, t.y);
        if (shopOnly && tile != Tile.shop) continue;
        if (corridorOnly && tile != Tile.floor) continue;
        if (nearWall && i < 450) {
          var walls = 0;
          if (f.solidAt(t.x + 1, t.y)) walls++;
          if (f.solidAt(t.x - 1, t.y)) walls++;
          if (f.solidAt(t.x, t.y + 1)) walls++;
          if (f.solidAt(t.x, t.y - 1)) walls++;
          if (walls < 1) continue;
        }
        if (ok(t, minArrival)) {
          taken.add(t);
          return t;
        }
      }
      final t = f.freeTiles[rng.nextInt(f.freeTiles.length)];
      taken.add(t);
      return t;
    }

    if (f.index == boxFloor) {
      final best = pick(minArrival: 22, shopOnly: true);
      f.box = tileCenter(best);
      f.boxPoly = lightPolygon(f, f.box!, 4, 90);
    }

    if (!roof) {
      final crates = garage ? 14 : 24;
      for (var i = 0; i < crates; i++) {
        final c = Crate(tileCenter(pick(nearWall: true, shopOnly: garage || i < 18)), rng.nextInt(5));
        f.crates.add(c);
        allCrates.add(c);
      }
      // Coches con la puerta abierta: se pueden registrar.
      for (final car in ([...f.cars]..shuffle(rng)).take(10)) {
        final c = Crate(car.center, carCrate);
        car.crate = c;
        f.crates.add(c);
        allCrates.add(c);
      }
      for (var i = 0; i < (garage ? 2 : 3); i++) {
        final p = Pc(tileCenter(pick(shopOnly: true, nearWall: true)), rng.nextDouble() * 10);
        f.pcs.add(p);
        allPcs.add(p);
      }
      for (var i = 0; i < 9; i++) {
        final locker = i < 5;
        final t = pick(nearWall: true, corridorOnly: locker, shopOnly: !locker, minArrival: 3);
        f.hideSpots.add(HideSpot(tileCenter(t), locker ? 0 : 1));
      }
      final mannequins = garage ? 2 : 6 + rng.nextInt(5);
      for (var i = 0; i < mannequins; i++) {
        final t = pick(shopOnly: true, minArrival: 5);
        f.mannequins.add(Mannequin(tileCenter(t), rng.nextDouble() * 2 * pi, 2 + rng.nextDouble() * 4));
      }
      if (f.mannequins.isNotEmpty) {
        f.mannequins[rng.nextInt(f.mannequins.length)].screamer = true;
      }
    }

    if (roof) {
      // Focos del helipuerto y la luna.
      final pad = Lamp(f.helipad!, 5.5, 1, const Color(0xFFFFE6B0));
      pad.poly = lightPolygon(f, pad.pos, pad.radius, 90);
      f.lamps.add(pad);
      for (var i = 0; i < 6; i++) {
        final l = Lamp(tileCenter(pick(minArrival: 0)), 3.5, rng.nextDouble() < 0.5 ? 1 : 0, const Color(0xFF9FB4FF));
        l.poly = lightPolygon(f, l.pos, l.radius, 60);
        f.lamps.add(l);
      }
    } else if (!garage) {
      // Claraboya del atrio: luz de luna azulada.
      final sky = Lamp(layout.atrium.center, 7.5, 0, const Color(0xFF8FA8FF));
      sky.poly = lightPolygon(f, sky.pos, sky.radius, 120);
      f.lamps.add(sky);
    }
    if (!roof) {
      // Lámparas que aún funcionan... más o menos.
      for (var i = 0; i < 12 + rng.nextInt(5); i++) {
        final t = pick(minArrival: 0, corridorOnly: i < 9);
        final mode = rng.nextDouble() < 0.4 ? 1 : (rng.nextDouble() < 0.4 ? 2 : 0);
        final l = Lamp(tileCenter(t), 3.2 + rng.nextDouble() * 1.8, mode,
            garage ? const Color(0xFFD8F0FF) : const Color(0xFFFFE6B0));
        l.poly = lightPolygon(f, l.pos, l.radius, 72);
        f.lamps.add(l);
      }
      // Luces de emergencia: verdes en las galerías, rojas en las tiendas.
      for (var i = 0; i < 18; i++) {
        final t = pick(minArrival: 0, nearWall: true, corridorOnly: i < 10, shopOnly: i >= 10);
        final green = i < 10;
        final l = Lamp(tileCenter(t), 2.6, 3, green ? const Color(0xFF30FF80) : const Color(0xFFFF3030),
            sign: green ? 'SALIDA' : null);
        l.poly = lightPolygon(f, l.pos, l.radius, 48);
        f.lamps.add(l);
      }
      // Cartel del ascensor: dice si para aquí o no.
      final e = tileCenter(f.elevator!);
      final el = Lamp(e, 2.2, 3, f.elevatorWorks ? const Color(0xFF40D0FF) : const Color(0xFFFF4040),
          sign: f.elevatorWorks ? 'ASCENSOR' : 'AVERIADO');
      el.poly = lightPolygon(f, e, el.radius, 48);
      f.lamps.add(el);
    }
    // Neones sobre las puertas de las tiendas.
    final signs = [...shopSigns]..shuffle(rng);
    var si = 0;
    const neon = [Color(0xFFFF2D6F), Color(0xFF2DE2FF), Color(0xFF9DFF2D), Color(0xFFFFB02D), Color(0xFFB02DFF)];
    for (final (door, out) in f.doors) {
      if (rng.nextDouble() < 0.35) continue;
      final a = door.first, b = door.last;
      final edge = Offset((a.x + b.x) / 2 + 0.5 + out.x * 0.5, (a.y + b.y) / 2 + 0.5 + out.y * 0.5);
      final l = Lamp(edge, 3.4, rng.nextDouble() < 0.7 ? 1 : 0, neon[rng.nextInt(neon.length)],
          sign: signs[si++ % signs.length]);
      l.poly = lightPolygon(f, edge + Offset(out.x * 0.6, out.y * 0.6), l.radius, 72);
      f.lamps.add(l);
    }
    for (final r in f.rooms) {
      r.poly = [r.rect.topLeft, r.rect.topRight, r.rect.bottomRight, r.rect.bottomLeft];
    }

    for (var i = 0; i < 150; i++) {
      final t = f.freeTiles[rng.nextInt(f.freeTiles.length)];
      f.decals.add(Decal(
        Offset(t.x + 0.15 + rng.nextDouble() * 0.7, t.y + 0.15 + rng.nextDouble() * 0.7),
        rng.nextInt(10) < 3 ? 0 : 1 + rng.nextInt(3),
        rng.nextDouble() * pi,
        0.3 + rng.nextDouble() * 0.5,
        rng.nextInt(1 << 30),
      ));
    }

    f.enemyCap = const [3, 3, 4, 4, 5, 5, 6, 0][f.index];
    final initial = const [2, 1, 3, 3, 4, 4, 5, 0][f.index];
    for (var i = 0; i < initial; i++) {
      final t = pick(minArrival: 18);
      f.enemies.add(Enemy(tileCenter(t), rng.nextDouble() * 2 * pi, rng.nextDouble() * 10));
    }
    f.spawnTimer = 50 + rng.nextDouble() * 40;
  }

  // Botín repartido por todo el edificio.
  allCrates.shuffle(rng);
  final loot = <ItemType>[
    for (var i = 0; i < 24; i++) ItemType.water,
    for (var i = 0; i < 20; i++) ItemType.food,
    for (var i = 0; i < 6; i++) ItemType.medkit,
    for (var i = 0; i < 9; i++) ItemType.bandage,
    for (var i = 0; i < 7; i++) ItemType.painkiller,
    for (var i = 0; i < 8; i++) ItemType.pills,
    for (var i = 0; i < 3; i++) ItemType.pistol,
    for (var i = 0; i < 14; i++) ItemType.ammo,
    for (var i = 0; i < 2; i++) ItemType.pipe,
  ];
  // Una barra de hierro siempre en la planta baja: hay que poder defenderse.
  final ground = floors[groundFloor].crates.where((c) => c.kind != carCrate).toList();
  ground[rng.nextInt(ground.length)].loot = ItemType.pipe;
  var li = 0;
  for (final c in allCrates) {
    if (c.loot != null) continue;
    if (li < loot.length) {
      c.loot = loot[li++];
    } else if (rng.nextDouble() < 0.3) {
      c.rat = true;
    }
  }
  // La hoja y las gafas, en plantas distintas y sin ninguna pista.
  final keyFloors = [for (var i = 0; i < roofFloor; i++) i]..shuffle(rng);
  void hide(int fi, ItemType t) {
    // Nunca a costa de un arma o de munición.
    const keep = {ItemType.pipe, ItemType.manuscript, ItemType.pistol, ItemType.ammo};
    final options = floors[fi].crates.where((c) => !keep.contains(c.loot)).toList();
    final c = options[rng.nextInt(options.length)];
    c.loot = t;
    c.rat = false;
  }

  hide(keyFloors[0], ItemType.manuscript);
  hide(keyFloors[1], ItemType.glasses);
  // Dos ordenadores funcionan, en plantas distintas.
  allPcs.shuffle(rng);
  allPcs.first.working = true;
  allPcs.firstWhere((p) => !floors.any((f) => f.pcs.contains(p) && f.pcs.contains(allPcs.first))).working = true;

  // Junto a la puerta de la azotea, la reserva de los sicarios.
  final roof = floors[roofFloor];
  final stash = [
    for (final t in roof.freeTiles)
      if (t != roof.down && (t.x - roof.down!.x).abs() <= 2 && (t.y - roof.down!.y).abs() <= 2) t
  ]..shuffle(rng);
  for (final (i, type) in [ItemType.ammo, ItemType.ammo, ItemType.medkit].indexed) {
    if (i < stash.length) roof.items.add(GroundItem(tileCenter(stash[i]), type));
  }

  return World(floors, start, boxFloor, keyFloors[0], keyFloors[1]);
}
