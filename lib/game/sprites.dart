import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Sprites pixel art definidos como rejillas de texto. Cada carácter es un
/// color de la paleta; '.' es transparente. Se pre-renderizan a [ui.Image]
/// y se pintan con FilterQuality.none para conservar el píxel.
class Sprite {
  final ui.Image image;
  final int w, h;
  Sprite(this.image, this.w, this.h);

  /// Dibuja el sprite centrado en [c] con una anchura en unidades de mundo
  /// [width]; la altura mantiene la proporción. [anchorY] desplaza el punto
  /// de anclaje (0.5 = centro, 1 = pies).
  void draw(Canvas canvas, Offset c, double width,
      {double anchorY = 0.5, bool flipX = false, double opacity = 1, double rotation = 0}) {
    final hgt = width * h / w;
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    if (opacity < 1) paint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (rotation != 0) canvas.rotate(rotation);
    if (flipX) canvas.scale(-1, 1);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Rect.fromLTWH(-width / 2, -hgt * anchorY, width, hgt),
      paint,
    );
    canvas.restore();
  }
}

Sprite buildSprite(List<String> rows, Map<String, Color> pal) => _build(rows, pal);

/// Ciclo de andar de un personaje: 4 imágenes por dirección.
class CharAnim {
  final List<Sprite> down, up, side;
  CharAnim(this.down, this.up, this.side);

  /// Imagen para mirar en [angle]; [flip] recibe si hay que voltear en horizontal.
  Sprite pick(double angle, int frame, List<bool> flip) {
    final c = cos(angle), s = sin(angle);
    final f = frame % 4;
    if (c.abs() > s.abs()) {
      flip[0] = c < 0;
      return side[f];
    }
    flip[0] = false;
    return s > 0 ? down[f] : up[f];
  }

  /// De frente o de espaldas: alterna levantar una pierna y la otra.
  /// De perfil: paso abierto y piernas juntas.
  static CharAnim build(List<String> down, List<String> up, List<String> side, Map<String, Color> pal,
      {required int legFrom, required int sideFrom}) {
    List<Sprite> frontal(List<String> rows) => [
          _build(rows, pal),
          _build(_liftLeg(rows, legFrom, true), pal),
          _build(rows, pal),
          _build(_liftLeg(rows, legFrom, false), pal),
        ];
    final stride = _build(_stride(side, sideFrom), pal);
    final pass = _build(side, pal);
    return CharAnim(frontal(down), frontal(up), [stride, pass, stride, pass]);
  }
}

int _width(List<String> rows) => rows.fold<int>(0, (m, r) => max(m, r.length));

/// Sube un píxel la pierna de un lado desde la fila [from]: el pie se despega del suelo.
List<String> _liftLeg(List<String> rows, int from, bool left) {
  final w = _width(rows);
  final src = [for (final r in rows) r.padRight(w, '.')];
  final mid = w ~/ 2;
  return [
    for (var y = 0; y < src.length; y++)
      y < from
          ? src[y]
          : String.fromCharCodes([
              for (var x = 0; x < w; x++)
                ((x < mid) == left)
                    ? (y + 1 < src.length ? src[y + 1].codeUnitAt(x) : 46)
                    : src[y].codeUnitAt(x),
            ]),
  ];
}

/// Separa las piernas hacia delante y hacia atrás desde la fila [from].
List<String> _stride(List<String> rows, int from) {
  final w = _width(rows);
  final src = [for (final r in rows) r.padRight(w, '.')];
  final mid = w ~/ 2;
  return [
    for (var y = 0; y < src.length; y++)
      y <= from
          ? src[y]
          : String.fromCharCodes([
              for (var x = 0; x < w; x++)
                () {
                  final a = y >= src.length - 2 ? 2 : 1;
                  final sx = x < mid ? x + a : x - a;
                  if ((x < mid) != (sx < mid) || sx < 0 || sx >= w) return 46;
                  return src[y].codeUnitAt(sx);
                }(),
            ]),
  ];
}

/// Variantes de sicario: gorra roja y chándal, calvo, chaqueta de cuero o traje negro.
const thugLooks = 4;

const playerPalette = _playerPal;

Sprite _build(List<String> rows, Map<String, Color> pal) {
  final h = rows.length;
  final w = rows.fold<int>(0, (m, r) => max(m, r.length));
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final p = Paint()..isAntiAlias = false;
  for (var y = 0; y < h; y++) {
    final row = rows[y];
    for (var x = 0; x < row.length; x++) {
      final ch = row[x];
      final col = pal[ch];
      if (col == null) continue;
      p.color = col;
      c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), p);
    }
  }
  return Sprite(rec.endRecording().toImageSync(w, h), w, h);
}

Sprite _buildFn(int w, int h, Color? Function(int x, int y) fn) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final p = Paint()..isAntiAlias = false;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final col = fn(x, y);
      if (col == null) continue;
      p.color = col;
      c.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1), p);
    }
  }
  return Sprite(rec.endRecording().toImageSync(w, h), w, h);
}

// --- Personajes -------------------------------------------------------------

const _humanDown = [
  '....kkkk....',
  '...khhhhk...',
  '..khhhhhhk..',
  '..khsssshk..',
  '..kekssksk..',
  '..kssssssk..',
  '...kssssk...',
  '..kjjjjjjk..',
  '.kjjjJJjjjk.',
  '.kjjjJJjjjk.',
  '.ksjjJJjjyk.',
  '..kjjjjjjk..',
  '..kppppppk..',
  '..kppkkppk..',
  '..kbbk.kbbk.',
  '...kk...kk..',
];

const _humanUp = [
  '....kkkk....',
  '...khhhhk...',
  '..khhhhhhk..',
  '..khhhhhhk..',
  '..khhhhhhk..',
  '..khhhhhhk..',
  '...khhhhk...',
  '..kjjjjjjk..',
  '.kjjjjjjjjk.',
  '.kjjjJJjjjk.',
  '.ksjjJJjjsk.',
  '..kjjjjjjk..',
  '..kppppppk..',
  '..kppkkppk..',
  '..kbbk.kbbk.',
  '...kk...kk..',
];

const _humanSide = [
  '....kkkk....',
  '...khhhhk...',
  '..khhhhhhk..',
  '..khhhssskk.',
  '..khhhsske..',
  '..khhssssk..',
  '...kssssk...',
  '...kjjjjk...',
  '..kjjjjjjk..',
  '..kjjJjjsyy.',
  '..kjjJjjk...',
  '...kjjjjk...',
  '...kppppk...',
  '...kpkkpk...',
  '...kbk.kbk..',
  '....k...k...',
];

const _thugDown = [
  '....kkkk....',
  '...khhhhk...',
  '..khhhhhhk..',
  '..khsssshk..',
  '..kggsggsk..',
  '..kssssssk..',
  '...kssssk...',
  '..kcwrrwck..',
  '.kcccwrwccck',
  '.kcCcwrwcCck',
  '.kscccrcccmk',
  '..kcccccck..',
  '..kppppppk..',
  '..kppkkppk..',
  '..kbbk.kbbk.',
  '...kk...kk..',
];

const _thugUp = [
  '....kkkk....',
  '...khhhhk...',
  '..khhhhhhk..',
  '..khhhhhhk..',
  '..khhhhhhk..',
  '..kshhhhsk..',
  '...kssssk...',
  '..kcccccck..',
  '.kccccccccck',
  '.kcCccccCcck',
  '.ksccccccsk.',
  '..kcccccck..',
  '..kppppppk..',
  '..kppkkppk..',
  '..kbbk.kbbk.',
  '...kk...kk..',
];

const _thugSide = [
  '....kkkk....',
  '...khhhhk...',
  '..khhhhhhk..',
  '..khhhssskk.',
  '..khhhsggg..',
  '..khhssssk..',
  '...kssssk...',
  '...kcwrck...',
  '..kcccwcck..',
  '..kcCccsmmmm',
  '..kcCcckkk..',
  '...kcccck...',
  '...kppppk...',
  '...kpkkpk...',
  '...kbk.kbk..',
  '....k...k...',
];

// El carnicero: calvo, camiseta de tirantes manchada y un cuchillo enorme.
const _bossDown = [
  '.....kkkkkk.....',
  '....kssssssk....',
  '....kseSSesk....',
  '....kssssssk....',
  '....ksrkkrsk....',
  '.....kssssk.....',
  '.kkkkkwwwwkkkkk.',
  'kssSkwwwwwwkSssk',
  'kssSkwrwwwwkSssk',
  'kssSkwwwrwwkSssk',
  'kssskwwwwwwkSssk',
  '.kkk.kwwwwk.ksk.',
  '.ksk.kppppk.knk.',
  '.kkk.kppppk.knk.',
  '.....kpkkpk..k..',
  '.....kpk.kpk....',
  '....kbbk.kbbk...',
  '....kkk...kkk...',
];

const _bossUp = [
  '.....kkkkkk.....',
  '....kssssssk....',
  '....kssssssk....',
  '....kSssssSk....',
  '....kSSSSSSk....',
  '.....kSSSSk.....',
  '.kkkkkwwwwkkkkk.',
  'kssSkwwwwwwkSssk',
  'kssSkwwwwwwkSssk',
  'kssSkwWwwWwkSssk',
  'kssskwwwwwwkSssk',
  '.kkk.kwwwwk.ksk.',
  '.knk.kppppk.kkk.',
  '.knk.kppppk.....',
  '..k..kpkkpk.....',
  '.....kpk.kpk....',
  '....kbbk.kbbk...',
  '....kkk...kkk...',
];

const _bossSide = [
  '.....kkkkkk.....',
  '....kssssssk....',
  '....ksssssek....',
  '....kssssssSk...',
  '....kSssssrk....',
  '.....kssssk.....',
  '....kkwwwwkk....',
  '...kSwwwwwwk....',
  '...kSwwrwwwk....',
  '...kSswwwwskkkkk',
  '...kSsswwssnnnnk',
  '....kkwwwwkkkkkk',
  '.....kppppk.....',
  '.....kppppk.....',
  '.....kpkkpk.....',
  '.....kpk.kpk....',
  '....kbbk.kbbk...',
  '....kkk...kkk...',
];

const _bossPal = {
  'k': Color(0xFF0A0606),
  's': Color(0xFFC88A62),
  'S': Color(0xFF9A6444),
  'e': Color(0xFF100000),
  'r': Color(0xFF8A0E0E),
  'w': Color(0xFFBDB6A2),
  'W': Color(0xFF8E8878),
  'p': Color(0xFF2A2620),
  'b': Color(0xFF140E0A),
  'n': Color(0xFFD8DCE0),
};

// Coche aparcado visto desde arriba, con el morro hacia arriba.
const _car = [
  '..kkkkkkkk..',
  '.klcccccclk.',
  '.kcccccccck.',
  'wkcccccccckw',
  'wkCggggggCkw',
  '.kgGgggggggk',
  '.kggggggggk.',
  '.kCccccccCk.',
  '.kcccccccck.',
  '.kcccccccck.',
  '.kcccccccck.',
  '.kcccccccck.',
  '.kcccccccck.',
  '.kcccccccck.',
  '.kCccccccCk.',
  '.kggggggggk.',
  '.kgggggGggk.',
  'wkCggggggCkw',
  'wkcccccccckw',
  '.kcccccccck.',
  '.kcccccccck.',
  '.kcccccccck.',
  '.kttccccttk.',
  '..kkkkkkkk..',
];

const carBodies = [
  Color(0xFF7A1E1E),
  Color(0xFF1E3A6A),
  Color(0xFFB8B8B0),
  Color(0xFF1A1A1E),
  Color(0xFF2A4A30),
  Color(0xFF8A7A20),
];

const _playerPal = {
  'k': Color(0xFF141414),
  'h': Color(0xFF3B2A1E),
  's': Color(0xFFD9A066),
  'e': Color(0xFF141414),
  'j': Color(0xFF3F5A3A),
  'J': Color(0xFF2B3F28),
  'p': Color(0xFF2C3344),
  'b': Color(0xFF1A1A1A),
  'y': Color(0xFFF2E8A0),
};

const _thugPal = {
  'k': Color(0xFF070707),
  'h': Color(0xFF0D0D0D),
  's': Color(0xFFB57A4E),
  'g': Color(0xFF020202),
  'c': Color(0xFF1C1C22),
  'C': Color(0xFF34343F),
  'w': Color(0xFFD8D8D8),
  'r': Color(0xFF8A1010),
  'p': Color(0xFF15151A),
  'b': Color(0xFF050505),
  'm': Color(0xFF5A5A5A),
};

const _mannequinPal = {
  'k': Color(0xFF3A3228),
  'h': Color(0xFFD8CBB0),
  's': Color(0xFFD8CBB0),
  'e': Color(0xFF050505),
  'j': Color(0xFFD8CBB0),
  'J': Color(0xFFB3A68A),
  'p': Color(0xFFB3A68A),
  'b': Color(0xFF9C9076),
  'y': Color(0xFFD8CBB0),
};


// --- Objetos ----------------------------------------------------------------

const _shelf = [
  'kkkkkkkkkkkkkkkk',
  'kwwwwwwwwwwwwwwk',
  'kbbbbbbbbbbbbbbk',
  'krrkggkbbkyykbbk',
  'kbbbbbbbbbbbbbbk',
  'kwwwwwwwwwwwwwwk',
  'kbbbbbbbbbbbbbbk',
  'kbbggkbbrrkbbbbk',
  'kbbbbbbbbbbbbbbk',
  'kwwwwwwwwwwwwwwk',
  'kkkkkkkkkkkkkkkk',
];

const _vending = [
  'kkkkkkkkkkkk',
  'krrrrrrrrrrk',
  'krkkkkkkkrrk',
  'krkcycgckrrk',
  'krkcccccckrk',
  'krkcgcyckrrk',
  'krkcccccckrk',
  'krkcycrckrrk',
  'krkkkkkkkrrk',
  'krrrrrrrrrrk',
  'krkddddkrrrk',
  'krrrrrrrrrrk',
  'kkkkkkkkkkkk',
];

const _counter = [
  'kkkkkkkkkkkkkkkk',
  'kggggggggggggggk',
  'kGGGGGGGGGGGGGGk',
  'kkkkkkkkkkkkkkkk',
  'kddddddddddddddk',
  'kdkkdddkkdddkkdk',
  'kddddddddddddddk',
  'kkkkkkkkkkkkkkkk',
];

const _trash = [
  '..kkkkkk..',
  '.kggggggk.',
  'kkkkkkkkkk',
  '.kgGgGgGk.',
  '.kgGgGgGk.',
  '.kgGgGgGk.',
  '.kgGgGgGk.',
  '.kgGgGgGk.',
  '.kkkkkkkk.',
];

const _locker = [
  'kkkkkkkkkk',
  'kbbbkkbbbk',
  'kbkbkkbkbk',
  'kbbbkkbbbk',
  'kbkbkkbkbk',
  'kbbbkkbbbk',
  'kbbbkkbbbk',
  'kbbykkybbk',
  'kbbbkkbbbk',
  'kbbbkkbbbk',
  'kbbbkkbbbk',
  'kbbbkkbbbk',
  'kkkkkkkkkk',
];

const _pc = [
  '.kkkkkkkkkk.',
  '.kggggggggk.',
  '.kgssssssgk.',
  '.kgssssssgk.',
  '.kgssssssgk.',
  '.kggggggggk.',
  '.kkkkggkkkk.',
  '....kggk....',
  'kkkkkkkkkkkk',
  'kddddddddddk',
  'kdwwwwwwwwdk',
  'kkkkkkkkkkkk',
];

const _box = [
  'kkkkkkkkkkkk',
  'kvvvvvvvvvvk',
  'kvyvvvvvvyvk',
  'kvvkkkkkkvvk',
  'kvvkooookvvk',
  'kvvkoOOokvvk',
  'kvvkoOOokvvk',
  'kvvkooookvvk',
  'kvvkkkkkkvvk',
  'kvyvvvvvvyvk',
  'kvvvvvvvvvvk',
  'kkkkkkkkkkkk',
];

// --- Iconos de inventario (10x10) -------------------------------------------

const iconWater = [
  '...kkkk...',
  '...kwwk...',
  '..kbbbbk..',
  '..kbBbbk..',
  '..kbBbbk..',
  '..kbbbbk..',
  '..kwwwwk..',
  '..kbBbbk..',
  '..kbbbbk..',
  '...kkkk...',
];
const iconFood = [
  '..........',
  '..kkkkkk..',
  '.kggggggk.',
  '.krrrrrrk.',
  '.krwwwwrk.',
  '.krwwwwrk.',
  '.krrrrrrk.',
  '.kggggggk.',
  '..kkkkkk..',
  '..........',
];
const iconMedkit = [
  '..........',
  '...kkkk...',
  '.kkkkkkkk.',
  '.kwwwwwwk.',
  '.kwwrrwwk.',
  '.kwrrrrwk.',
  '.kwwrrwwk.',
  '.kwwwwwwk.',
  '.kkkkkkkk.',
  '..........',
];
const iconBandage = [
  '..........',
  '..........',
  '...kkkk...',
  '..kbbbbk..',
  '.kbbwwbbk.',
  '.kbwkkwbk.',
  '.kbbwwbbk.',
  '..kbbbbk..',
  '...kkkk...',
  '..........',
];
const iconPainkiller = [
  '...kkkk...',
  '..kwwwwk..',
  '..kkkkkk..',
  '..kooook..',
  '..kowwok..',
  '..kowwok..',
  '..kooook..',
  '..kooook..',
  '..kkkkkk..',
  '..........',
];
const iconPills = [
  '..........',
  '.....kkk..',
  '....krrwk.',
  '...krrwwk.',
  '...kkwwk..',
  '..kkk.k...',
  '.kppwk....',
  '.kpwwk....',
  '..kkk.....',
  '..........',
];
const iconPistol = [
  '..........',
  '..........',
  '.kkkkkkkk.',
  '.kmmmmmmmk',
  '.kmMMMMmk.',
  '.kkkkmmk..',
  '....kmmk..',
  '....kmmk..',
  '....kkkk..',
  '..........',
];
const iconAmmo = [
  '..........',
  '..........',
  '..k.k.k...',
  '.kykykyk..',
  '.kykykyk..',
  '.kokokok..',
  '.kokokok..',
  '.kkkkkkk..',
  '..........',
  '..........',
];
const iconPipe = [
  '........kk',
  '.......kmk',
  '......kmk.',
  '.....kmk..',
  '....kmk...',
  '...kmk....',
  '..kmk.....',
  '.kmk......',
  'kmk.......',
  'kk........',
];
const iconManuscript = [
  '.kkkkkkkk.',
  'kyyyyyyyyk',
  '.kppppppk.',
  '.kpvvpvpk.',
  '.kppppppk.',
  '.kpvpvvpk.',
  '.kppppppk.',
  '.kpvvvppk.',
  'kyyyyyyyyk',
  '.kkkkkkkk.',
];
const iconSheet = [
  '.kkkkkkk..',
  '.kpppppkk.',
  '.kppppppkk',
  '.kpppppppk',
  '.kpppppppk',
  '.kpppppppk',
  '.kpppppppk',
  '.kpppppppk',
  '.kpppppppk',
  '.kkkkkkkkk',
];
const iconGlasses = [
  '..........',
  '..........',
  'kkkkkkkkkk',
  'kaaakkaaak',
  'kaAakkaAak',
  'kaaakkaaak',
  '.kkk..kkk.',
  '..........',
  '..........',
  '..........',
];
const iconMagic = [
  '....kk....',
  '...kvvk...',
  'kkkkvvkkkk',
  'kvvvwwvvvk',
  '.kvvwwvvk.',
  '..kvvvvk..',
  '.kvvkkvvk.',
  '.kvk..kvk.',
  'kkk....kkk',
  '..........',
];
const iconRat = [
  '................',
  '..........kk....',
  '.........kggk...',
  '..kkkkkkkgggkk..',
  '.kggggggggggrgk.',
  'kgggggggggggggpk',
  'kgggGgggggggkk..',
  '.kggGGgggggk....',
  '..kkgkkkgkk.....',
  '...kk...kk......',
];

const _probador = [
  'kkkkkkkkkkkk',
  'kmmmmmmmmmmk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kpPppPppPppk',
  'kdpdPdpdPdpk',
  'kddddddddddk',
];

const _hideLocker = [
  'kkkkkkkkkkkk',
  'kbbbbbbbbbbk',
  'kbkkkkkkkkbk',
  'kbbbbbbbbbbk',
  'kbkkkkkkkkbk',
  'kbbbbbbbbbbk',
  'kbkkkkkkkkbk',
  'kbbbbbbbbbbk',
  'kbbbbbbbbybk',
  'kbbbbbbbbbbk',
  'kbbbbbbbbbbk',
  'kbbbbbbbbbbk',
  'kbbbbbbbbbbk',
  'kbbbbbbbbbbk',
  'kkkkkkkkkkkk',
];

const iconFist = [
  '..........',
  '..kkkkk...',
  '.ksksksk..',
  '.ksksksk..',
  '.kssssskk.',
  '.ksssssssk',
  '.kssssssk.',
  '..kssssk..',
  '...kkkk...',
  '..........',
];

const _iconPal = {
  'k': Color(0xFF0E0E0E),
  'w': Color(0xFFF0F0F0),
  'b': Color(0xFF3A7BD5),
  'B': Color(0xFF8FC1FF),
  'g': Color(0xFF8A8A8A),
  'r': Color(0xFFC0392B),
  'o': Color(0xFFE67E22),
  'p': Color(0xFF7FB3D5),
  'm': Color(0xFF6B6B6B),
  'M': Color(0xFF9A9A9A),
  'y': Color(0xFFE8C468),
  'v': Color(0xFF8E44AD),
  's': Color(0xFFD9A066),
};

const _bandagePal = {
  'k': Color(0xFF0E0E0E),
  'b': Color(0xFFE6D3B3),
  'w': Color(0xFFFFFFFF),
};

const _manuscriptPal = {
  'k': Color(0xFF0E0E0E),
  'p': Color(0xFFD8C48A),
  'y': Color(0xFFB89B5E),
  'v': Color(0xFF5A2A7A),
};

class Sprites {
  Sprites._();
  static Sprites? _i;
  static Sprites get i => _i ??= Sprites._().._load();

  late Sprite playerDown, playerUp, playerSide;
  late Sprite thugDown, thugUp, thugSide;
  late Sprite manDown, manUp, manSide;
  late Sprite bossDown, bossUp, bossSide;
  late CharAnim playerAnim, bossAnim;
  late List<CharAnim> thugAnims;
  late List<Sprite> cars;
  late List<Sprite> crates;
  late Sprite pc, box;
  late List<Sprite> hideSpots;
  late Map<String, Sprite> icons;

  void _load() {
    playerDown = _build(_humanDown, _playerPal);
    playerUp = _build(_humanUp, _playerPal);
    playerSide = _build(_humanSide, _playerPal);
    thugDown = _build(_thugDown, _thugPal);
    thugUp = _build(_thugUp, _thugPal);
    thugSide = _build(_thugSide, _thugPal);
    manDown = _build(_humanDown, _mannequinPal);
    manUp = _build(_humanUp, _mannequinPal);
    manSide = _build(_humanSide, _mannequinPal);
    bossDown = _build(_bossDown, _bossPal);
    bossUp = _build(_bossUp, _bossPal);
    bossSide = _build(_bossSide, _bossPal);
    playerAnim = CharAnim.build(_humanDown, _humanUp, _humanSide, _playerPal, legFrom: 13, sideFrom: 12);
    bossAnim = CharAnim.build(_bossDown, _bossUp, _bossSide, _bossPal, legFrom: 15, sideFrom: 13);
    thugAnims = [
      for (final pal in [
        _thugPal,
        {..._thugPal, 'h': const Color(0xFFA06A44)},
        {..._thugPal, 'h': const Color(0xFF2A1A10), 'c': const Color(0xFF4A2E1C), 'C': const Color(0xFF6A4630), 'w': const Color(0xFF8A8070)},
        {..._thugPal, 'h': const Color(0xFF7A1414), 'c': const Color(0xFF1E2A44), 'C': const Color(0xFF3A4A6A), 'w': const Color(0xFFDDDDDD)},
      ])
        CharAnim.build(_thugDown, _thugUp, _thugSide, pal, legFrom: 13, sideFrom: 12),
    ];
    cars = [
      for (final body in carBodies)
        _build(_car, {
          'k': const Color(0xFF080808),
          'c': body,
          'C': Color.lerp(body, const Color(0xFF000000), 0.35)!,
          'g': const Color(0xFF10161E),
          'G': const Color(0xFF5A6A80),
          'l': const Color(0xFFE8E0B0),
          't': const Color(0xFF8A1010),
          'w': const Color(0xFF050505),
        }),
    ];
    crates = [
      _build(_shelf, const {
        'k': Color(0xFF1B120B),
        'w': Color(0xFF7A5A3A),
        'b': Color(0xFF4A3424),
        'r': Color(0xFF8E2B2B),
        'g': Color(0xFF2E6B3A),
        'y': Color(0xFFB8A040),
      }),
      _build(_vending, const {
        'k': Color(0xFF0E0E0E),
        'r': Color(0xFF7A1C1C),
        'c': Color(0xFF233446),
        'y': Color(0xFFC9A93A),
        'g': Color(0xFF3A8A4A),
        'd': Color(0xFF151515),
      }),
      _build(_counter, const {
        'k': Color(0xFF101010),
        'g': Color(0xFF6E6E6E),
        'G': Color(0xFF4E4E4E),
        'd': Color(0xFF3A3A3A),
      }),
      _build(_trash, const {
        'k': Color(0xFF0B140B),
        'g': Color(0xFF2E4A2E),
        'G': Color(0xFF1E331E),
      }),
      _build(_locker, const {
        'k': Color(0xFF101418),
        'b': Color(0xFF3E5566),
        'y': Color(0xFFB0B0B0),
      }),
      cars[2],
    ];
    pc = _build(_pc, const {
      'k': Color(0xFF0A0A0A),
      'g': Color(0xFF8C8C80),
      's': Color(0xFF101418),
      'd': Color(0xFF4A3A2A),
      'w': Color(0xFF2A2A2A),
    });
    box = _build(_box, const {
      'k': Color(0xFF0A0510),
      'v': Color(0xFF3A1F4A),
      'y': Color(0xFFD4AF37),
      'o': Color(0xFFB04CFF),
      'O': Color(0xFFFFD0FF),
    });
    hideSpots = [
      _build(_hideLocker, const {
        'k': Color(0xFF0C1014),
        'b': Color(0xFF2E4252),
        'y': Color(0xFFB0B0B0),
      }),
      _build(_probador, const {
        'k': Color(0xFF0E0E0E),
        'm': Color(0xFF8A8A8A),
        'p': Color(0xFF5A2A4A),
        'P': Color(0xFF3A1A30),
        'd': Color(0xFF050505),
      }),
    ];
    icons = {
      'water': _build(iconWater, _iconPal),
      'food': _build(iconFood, _iconPal),
      'medkit': _build(iconMedkit, _iconPal),
      'bandage': _build(iconBandage, _bandagePal),
      'painkiller': _build(iconPainkiller, _iconPal),
      'pills': _build(iconPills, _iconPal),
      'pistol': _build(iconPistol, _iconPal),
      'ammo': _build(iconAmmo, _iconPal),
      'pipe': _build(iconPipe, _iconPal),
      'manuscript': _build(iconManuscript, _manuscriptPal),
      'sheet': _build(iconSheet, _manuscriptPal),
      'glasses': _build(iconGlasses, const {
        'k': Color(0xFF2A1A10),
        'a': Color(0xFFE0A030),
        'A': Color(0xFFFFE0A0),
      }),
      'magic': _build(iconMagic, _iconPal),
      'fist': _build(iconFist, _iconPal),
      'rat': _build(iconRat, const {
        'k': Color(0xFF0E0E0E),
        'g': Color(0xFF6A5E58),
        'G': Color(0xFF4A403C),
        'r': Color(0xFFFF2020),
        'p': Color(0xFFD08A8A),
      }),
    };
  }
}

// --- Texturas de suelo y paredes (16x16, generadas) -------------------------

class FloorPalette {
  final Color floor, floorAlt, shop, shopAlt, wallTop, wallFace, wallFaceAlt, grime;
  const FloorPalette({
    required this.floor,
    required this.floorAlt,
    required this.shop,
    required this.shopAlt,
    required this.wallTop,
    required this.wallFace,
    required this.wallFaceAlt,
    required this.grime,
  });
}

/// Paletas oscuras por planta y la paleta brillante del final.
const darkPalettes = [
  // Garaje: hormigón y manchas de aceite.
  FloorPalette(
    floor: Color(0xFF3A3A38),
    floorAlt: Color(0xFF343432),
    shop: Color(0xFF2E2C28),
    shopAlt: Color(0xFF292724),
    wallTop: Color(0xFF121211),
    wallFace: Color(0xFF4A4A44),
    wallFaceAlt: Color(0xFF5A5432),
    grime: Color(0xFF1C1C1A),
  ),
  FloorPalette(
    floor: Color(0xFF3C4148),
    floorAlt: Color(0xFF353A40),
    shop: Color(0xFF2F3A4A),
    shopAlt: Color(0xFF2A3442),
    wallTop: Color(0xFF15171B),
    wallFace: Color(0xFF2A2E35),
    wallFaceAlt: Color(0xFF3A3F47),
    grime: Color(0xFF22252A),
  ),
  FloorPalette(
    floor: Color(0xFF39423B),
    floorAlt: Color(0xFF323A34),
    shop: Color(0xFF4A2F33),
    shopAlt: Color(0xFF42292D),
    wallTop: Color(0xFF131814),
    wallFace: Color(0xFF263029),
    wallFaceAlt: Color(0xFF354238),
    grime: Color(0xFF1E2620),
  ),
  FloorPalette(
    floor: Color(0xFF453B33),
    floorAlt: Color(0xFF3D342D),
    shop: Color(0xFF2F4436),
    shopAlt: Color(0xFF2A3C30),
    wallTop: Color(0xFF1A1512),
    wallFace: Color(0xFF332A23),
    wallFaceAlt: Color(0xFF433830),
    grime: Color(0xFF2A221C),
  ),
  FloorPalette(
    floor: Color(0xFF3D3747),
    floorAlt: Color(0xFF36313F),
    shop: Color(0xFF443A2A),
    shopAlt: Color(0xFF3C3325),
    wallTop: Color(0xFF16131B),
    wallFace: Color(0xFF2D2736),
    wallFaceAlt: Color(0xFF3D3548),
    grime: Color(0xFF241F2B),
  ),
  FloorPalette(
    floor: Color(0xFF343F47),
    floorAlt: Color(0xFF2E3840),
    shop: Color(0xFF3A3047),
    shopAlt: Color(0xFF332A3F),
    wallTop: Color(0xFF12161A),
    wallFace: Color(0xFF26313A),
    wallFaceAlt: Color(0xFF34424D),
    grime: Color(0xFF1C2328),
  ),
  FloorPalette(
    floor: Color(0xFF473733),
    floorAlt: Color(0xFF3F302D),
    shop: Color(0xFF2E3A44),
    shopAlt: Color(0xFF29333C),
    wallTop: Color(0xFF1A1211),
    wallFace: Color(0xFF3A2724),
    wallFaceAlt: Color(0xFF4A3430),
    grime: Color(0xFF2A1C1A),
  ),
  // Azotea: tela asfáltica mojada y grava.
  FloorPalette(
    floor: Color(0xFF2C2E33),
    floorAlt: Color(0xFF27292D),
    shop: Color(0xFF2C2E33),
    shopAlt: Color(0xFF27292D),
    wallTop: Color(0xFF4A4E56),
    wallFace: Color(0xFF6A6E76),
    wallFaceAlt: Color(0xFF7A7E86),
    grime: Color(0xFF1E2024),
  ),
];

const alivePalette = FloorPalette(
  floor: Color(0xFFF2EDE4),
  floorAlt: Color(0xFFE6DFD2),
  shop: Color(0xFFD9A066),
  shopAlt: Color(0xFFC98F55),
  wallTop: Color(0xFF7FB8C9),
  wallFace: Color(0xFFFFF4D6),
  wallFaceAlt: Color(0xFFFFD27F),
  grime: Color(0xFFD8D0C2),
);

class TileSet {
  final List<Sprite> floor;
  final List<Sprite> shop;
  final Sprite wallTop;
  final List<Sprite> wallFace;
  final Sprite stairUp, stairDown, elevator;
  TileSet(this.floor, this.shop, this.wallTop, this.wallFace, this.stairUp, this.stairDown, this.elevator);

  static TileSet build(FloorPalette p, int seed, {bool alive = false}) {
    final rng = Random(seed);
    Color vary(Color c, double amt) {
      final d = (rng.nextDouble() * 2 - 1) * amt;
      return Color.lerp(c, d > 0 ? const Color(0xFFFFFFFF) : const Color(0xFF000000), d.abs())!;
    }

    Sprite floorTex(int variant) {
      final cracks = <int>{};
      if (!alive && variant > 0) {
        var x = rng.nextInt(16), y = rng.nextInt(16);
        for (var i = 0; i < 9; i++) {
          cracks.add(y * 16 + x);
          x = (x + rng.nextInt(3) - 1).clamp(0, 15);
          y = (y + 1).clamp(0, 15);
        }
      }
      return _buildFn(16, 16, (x, y) {
        if (cracks.contains(y * 16 + x)) return p.grime;
        if (x == 0 || y == 0 || x == 8 || y == 8) return Color.lerp(p.floorAlt, const Color(0xFF000000), 0.25);
        final checker = ((x ~/ 8) + (y ~/ 8)) % 2 == 0;
        final base = checker ? p.floor : p.floorAlt;
        if (alive && (x + y) % 11 == 0 && x < 7 && y < 7) return const Color(0xFFFFFFFF);
        return rng.nextDouble() < 0.12 ? vary(base, alive ? 0.03 : 0.12) : base;
      });
    }

    // Moqueta de tienda: trama fina y manchas, sin juntas que parezcan pared.
    Sprite shopTex() => _buildFn(16, 16, (x, y) {
          final weave = (x + y) % 4 == 0 || (x - y) % 4 == 0;
          final base = weave ? p.shopAlt : p.shop;
          return rng.nextDouble() < 0.08 ? vary(base, 0.08) : base;
        });

    final wallTop = _buildFn(16, 16, (x, y) {
      if (rng.nextDouble() < 0.08) return vary(p.wallTop, 0.15);
      return p.wallTop;
    });

    // Cara frontal: ladrillo o persiana metálica de tienda.
    Sprite brick() => _buildFn(16, 16, (x, y) {
          if (y >= 14) return Color.lerp(p.wallFace, const Color(0xFF000000), 0.5);
          if (y % 4 == 3) return Color.lerp(p.wallFace, const Color(0xFF000000), 0.35);
          final off = (y ~/ 4) % 2 == 0 ? 0 : 4;
          if ((x + off) % 8 == 7) return Color.lerp(p.wallFace, const Color(0xFF000000), 0.35);
          return rng.nextDouble() < 0.15 ? vary(p.wallFace, 0.1) : p.wallFace;
        });
    Sprite shutter() => _buildFn(16, 16, (x, y) {
          if (y >= 14) return Color.lerp(p.wallFaceAlt, const Color(0xFF000000), 0.5);
          if (y % 2 == 1) return Color.lerp(p.wallFaceAlt, const Color(0xFF000000), 0.3);
          if (!alive && rng.nextDouble() < 0.04) return const Color(0xFF6A2020); // graffiti
          return p.wallFaceAlt;
        });

    Sprite stairs(bool up) => _buildFn(16, 16, (x, y) {
          final step = up ? y ~/ 3 : (15 - y) ~/ 3;
          final shade = 0.1 + step * 0.08;
          if (y % 3 == 0) return Color.lerp(p.floor, const Color(0xFF000000), 0.6);
          if (x == 0 || x == 15) return const Color(0xFF8A7A30);
          // Flecha
          final ay = up ? y : 15 - y;
          if (ay >= 3 && ay <= 12 && (x - 7.5).abs() <= (ay < 7 ? ay - 3 : 1.5) && (x - 7.5).abs() < 5) {
            return up ? const Color(0xFF6FBF73) : const Color(0xFFBF6F6F);
          }
          return Color.lerp(p.floor, const Color(0xFF000000), shade);
        });

    // Puertas de acero del ascensor.
    final elevator = _buildFn(16, 16, (x, y) {
      if (y < 2 || x == 0 || x == 15) return const Color(0xFF202226);
      if (x == 7 || x == 8) return const Color(0xFF08090A);
      if (y == 1 && (x == 3 || x == 12)) return const Color(0xFF40D0FF);
      final base = x % 3 == 0 ? const Color(0xFF7A7F88) : const Color(0xFF8E939C);
      return alive ? Color.lerp(base, const Color(0xFFFFFFFF), 0.3) : base;
    });

    return TileSet(
      [floorTex(0), floorTex(1), floorTex(2)],
      [shopTex(), shopTex()],
      wallTop,
      [brick(), shutter()],
      stairs(true),
      stairs(false),
      elevator,
    );
  }
}
