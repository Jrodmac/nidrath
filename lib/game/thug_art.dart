import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Una pose recortada y dónde cae el eje del cuerpo dentro de la imagen (0..1).
class Pose {
  final String file;
  final double axis;
  const Pose(this.file, [this.axis = 0.5]);
}

/// Imágenes de los personajes. Los perfiles miran a la derecha. Mientras no
/// estén cargadas, la vista dibuja las figuras vectoriales.
class ThugArt {
  static const front = Pose('sicario_front');
  static const back = Pose('sicario_back');
  static const side = Pose('sicario_side', 0.53);
  static const walkFront = Pose('sicario_walk_front');
  static const walkSide = Pose('sicario_walk_side', 0.56);
  static const aimFront = Pose('sicario_aim_front');
  static const aimSide = Pose('sicario_aim_side', 0.25);
  static const bossFront = Pose('carnicero_front');
  static const bossBack = Pose('carnicero_back');
  static const bossSide = Pose('carnicero_side');

  static const _thug = [front, back, side, walkFront, walkSide, aimFront, aimSide];
  static const _boss = [bossFront, bossBack, bossSide];

  static final Map<String, ui.Image> _images = {};
  static Future<void>? _loading;

  static bool get ready => _thug.every((p) => _images.containsKey(p.file));
  static bool get bossReady => _boss.every((p) => _images.containsKey(p.file));

  static ui.Image image(Pose p) => _images[p.file]!;

  static Future<void> load() => _loading ??= _load();

  /// Muebles y objetos, por nombre de archivo (sin «.png»). Sin imagen, null:
  /// la vista usa el sprite de siempre.
  static ui.Image? prop(String file) => _images[file];

  static const crateFiles = ['mueble_shelf', 'mueble_vending', 'mueble_counter', 'mueble_trash', 'mueble_cabinet'];
  static const hideFiles = ['obj_locker', 'obj_probador'];
  static const itemNames = [
    'water', 'food', 'medkit', 'bandage', 'painkiller', 'pills', //
    'pistol', 'ammo', 'pipe', 'manuscript', 'glasses', //
    'shotgun', 'shells', 'knife', 'grenade', 'vest',
  ];

  /// Armas en la mano, vistas en primera persona.
  static const handFiles = ['fp_shotgun', 'fp_shotgun_fire', 'fp_knife', 'fp_grenade', 'fp_pistol', 'fp_pipe'];

  /// Dibuja el objeto [name] encajado en un cuadrado de lado [size].
  /// Devuelve false si no hay imagen.
  static bool drawIcon(Canvas c, String name, Offset center, double size, {double opacity = 1}) {
    final im = _images['item_$name'];
    if (im == null) return false;
    final k = size / (im.width > im.height ? im.width : im.height);
    final w = im.width * k, h = im.height * k;
    c.drawImageRect(
      im,
      Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()),
      Rect.fromCenter(center: center, width: w, height: h),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    return true;
  }

  static Future<void> _load() async {
    final files = [
      for (final p in [..._thug, ..._boss]) p.file,
      ...crateFiles,
      ...hideFiles,
      'obj_pc',
      'obj_mannequin',
      'obj_box',
      for (final n in itemNames) 'item_$n',
      ...handFiles,
    ];
    for (final f in files) {
      try {
        final data = await rootBundle.load('assets/img/$f.png');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        _images[f] = (await codec.getNextFrame()).image;
      } catch (_) {
        // Sin esa imagen se sigue jugando con la figura dibujada.
      }
    }
  }
}
