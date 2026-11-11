// Recorta una hoja de personaje (JPG o PNG con el damero «transparente»
// dibujado) en una imagen por pose, con fondo transparente de verdad.
//
//   SRC=hoja.jpg PREFIX=sicario NAMES=front,side,skip,back \
//   DEST=assets/img OUT=carpeta_para_la_vista_previa flutter test tool/cut_sheet_test.dart
//
// Las figuras se nombran por filas (ROWS, por defecto 1) y de izquierda a
// derecha; «skip» descarta una. GLOW=1 recorta también un halo de color.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

final _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crc(List<int> b) {
  var c = 0xFFFFFFFF;
  for (final x in b) {
    c = _crcTable[(c ^ x) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void writePng(String path, Uint8List rgba, int w, int h) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(rgba, y * w * 4, (y + 1) * w * 4));
  }
  final out = BytesBuilder()..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final len = ByteData(4)..setUint32(0, data.length);
    final crc = ByteData(4)..setUint32(0, _crc(body));
    out
      ..add(len.buffer.asUint8List())
      ..add(body)
      ..add(crc.buffer.asUint8List());
  }

  final hdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', hdr.buffer.asUint8List());
  chunk('IDAT', ZLibCodec(level: 9).encode(raw.toBytes()));
  chunk('IEND', const []);
  File(path).writeAsBytesSync(out.toBytes());
}

void main() {
  testWidgets('recortar hoja', (tester) async {
    final env = Platform.environment;
    if (env['SRC'] == null) return; // solo se usa a mano
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(File(env['SRC']!).readAsBytesSync());
      final img = (await codec.getNextFrame()).image;
      final w = img.width, h = img.height;
      final px = (await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!.buffer.asUint8List();

      // Los dos grises del damero se miden en el borde de la hoja (claro u oscuro).
      final border = <int>[
        for (var x = 0; x < w; x += 3) ...[(px[x * 4] + px[x * 4 + 1] + px[x * 4 + 2]) ~/ 3],
        for (var x = 0; x < w; x += 3)
          (px[((h - 1) * w + x) * 4] + px[((h - 1) * w + x) * 4 + 1] + px[((h - 1) * w + x) * 4 + 2]) ~/ 3,
      ]..sort();
      final lo = border[border.length ~/ 50], hi = border[border.length - 1 - border.length ~/ 50];
      final minLum = lo - 20 < 30 ? 30 : lo - 20;
      final fringe = lo - 18 > 70 ? 70 : (lo - 18 < 26 ? 26 : lo - 18);
      // GLOW=1: también cuenta como fondo el halo de color pintado encima del
      // damero (solo se detiene en el contorno negro o en algo muy brillante).
      final glow = env['GLOW'] == '1';
      // ignore: avoid_print
      print('damero: $lo..$hi');
      bool bgLike(int i) {
        final r = px[i * 4], g = px[i * 4 + 1], b = px[i * 4 + 2];
        final lum = (r + g + b) ~/ 3;
        if (glow) return lum > minLum && lum < 125;
        return (r - g).abs() < 14 && (g - b).abs() < 14 && lum > minLum && lum < hi + 14;
      }

      // Se rellena desde los bordes: lo claro encerrado por la figura se queda.
      final bg = Uint8List(w * h);
      final stack = <int>[];
      // Con halo, el relleno avanza con una brocha gruesa para no colarse por
      // las rendijas del contorno; luego se recupera el margen perdido.
      final brush = int.parse(env['BRUSH'] ?? '3');
      Uint8List? pass;
      if (glow) {
        pass = Uint8List(w * h);
        for (var i = 0; i < w * h; i++) {
          if (bgLike(i)) pass[i] = 1;
        }
      }
      bool wide(int i) {
        final x = i % w, y = i ~/ w;
        for (var dy = -brush; dy <= brush; dy++) {
          for (var dx = -brush; dx <= brush; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            if (pass![yy * w + xx] == 0) return false;
          }
        }
        return true;
      }

      void seed(int i) {
        if (bg[i] == 0 && (glow ? wide(i) : bgLike(i))) {
          bg[i] = 1;
          stack.add(i);
        }
      }

      for (var x = 0; x < w; x++) {
        seed(x);
        seed((h - 1) * w + x);
      }
      for (var y = 0; y < h; y++) {
        seed(y * w);
        seed(y * w + w - 1);
      }
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        final x = i % w, y = i ~/ w;
        if (x > 0) seed(i - 1);
        if (x < w - 1) seed(i + 1);
        if (y > 0) seed(i - w);
        if (y < h - 1) seed(i + w);
      }
      if (glow) {
        for (var k = 0; k < brush; k++) {
          final add = <int>[];
          for (var y = 1; y < h - 1; y++) {
            for (var x = 1; x < w - 1; x++) {
              final i = y * w + x;
              if (bg[i] == 0 && pass![i] == 1 && bg[i - 1] + bg[i + 1] + bg[i - w] + bg[i + w] > 0) add.add(i);
            }
          }
          for (final i in add) {
            bg[i] = 1;
          }
        }
      }
      // Quita el borde grisáceo que deja el suavizado contra el fondo.
      for (var pass = 0; pass < 2; pass++) {
        final add = <int>[];
        for (var y = 1; y < h - 1; y++) {
          for (var x = 1; x < w - 1; x++) {
            final i = y * w + x;
            if (bg[i] == 1) continue;
            if (bg[i - 1] + bg[i + 1] + bg[i - w] + bg[i + w] == 0) continue;
            final r = px[i * 4], g = px[i * 4 + 1], b = px[i * 4 + 2];
            if ((r - g).abs() < 20 && (g - b).abs() < 20 && (r + g + b) ~/ 3 > fringe) add.add(i);
          }
        }
        for (final i in add) {
          bg[i] = 1;
        }
      }
      final alpha = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (bg[i] == 1) continue;
          final edge = x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
              bg[i - 1] + bg[i + 1] + bg[i - w] + bg[i + w] > 0;
          alpha[i] = edge ? 150 : 255;
        }
      }

      // Vista previa sobre magenta, a un tercio, para revisar el recorte.
      final pw = w ~/ 3, ph = h ~/ 3;
      final prev = Uint8List(pw * ph * 4);
      for (var y = 0; y < ph; y++) {
        for (var x = 0; x < pw; x++) {
          final i = (y * 3) * w + x * 3, o = (y * pw + x) * 4;
          final a = alpha[i] / 255;
          prev[o] = (px[i * 4] * a + 255 * (1 - a)).round();
          prev[o + 1] = (px[i * 4 + 1] * a).round();
          prev[o + 2] = (px[i * 4 + 2] * a + 255 * (1 - a)).round();
          prev[o + 3] = 255;
        }
      }
      writePng('${env['OUT']}/cut_preview_${env['PREFIX']}.png', prev, pw, ph);

      // Una figura por mancha conexa; las piezas sueltas muy juntas (unas
      // pastillas) cuentan como una sola. Se ordenan por filas y de izquierda a derecha.
      final label = Int32List(w * h);
      var boxes = <List<int>>[]; // x0, y0, x1, y1, área
      for (var start = 0; start < w * h; start++) {
        if (alpha[start] == 0 || label[start] != 0) continue;
        final id = boxes.length + 1;
        final bx = [w, h, 0, 0, 0];
        label[start] = id;
        stack.add(start);
        while (stack.isNotEmpty) {
          final i = stack.removeLast();
          final x = i % w, y = i ~/ w;
          if (x < bx[0]) bx[0] = x;
          if (y < bx[1]) bx[1] = y;
          if (x + 1 > bx[2]) bx[2] = x + 1;
          if (y + 1 > bx[3]) bx[3] = y + 1;
          bx[4]++;
          for (final n in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
            if (alpha[n] != 0 && label[n] == 0) {
              label[n] = id;
              stack.add(n);
            }
          }
        }
        boxes.add(bx);
      }
      boxes = boxes.where((b) => b[4] > 300).toList();
      const gap = 30;
      for (var merged = true; merged;) {
        merged = false;
        outer:
        for (var i = 0; i < boxes.length; i++) {
          for (var j = i + 1; j < boxes.length; j++) {
            final a = boxes[i], b = boxes[j];
            if (a[0] - gap < b[2] && b[0] - gap < a[2] && a[1] - gap < b[3] && b[1] - gap < a[3]) {
              boxes[i] = [
                a[0] < b[0] ? a[0] : b[0],
                a[1] < b[1] ? a[1] : b[1],
                a[2] > b[2] ? a[2] : b[2],
                a[3] > b[3] ? a[3] : b[3],
                a[4] + b[4],
              ];
              boxes.removeAt(j);
              merged = true;
              break outer;
            }
          }
        }
      }
      boxes = boxes.where((b) => b[4] > 2500).toList();
      final rows = int.parse(env['ROWS'] ?? '1'); // filas de figuras en la hoja
      int row(List<int> b) => ((b[1] + b[3]) / 2 / h * rows).floor();
      boxes.sort((a, b) => row(a) != row(b) ? row(a) - row(b) : a[0] - b[0]);
      final runs = boxes;
      final names = env['NAMES']!.split(',');
      // ignore: avoid_print
      print('${w}x$h, figuras: ${runs.length} (nombres: ${names.length})');
      for (var k = 0; k < runs.length && k < names.length; k++) {
        if (names[k] == 'skip') continue;
        final x0 = runs[k][0], x1 = runs[k][2];
        final y0 = runs[k][1], y1 = runs[k][3];
        // A mitad de tamaño: de sobra para la pantalla y suaviza el borde.
        final cw = (x1 - x0) ~/ 2, chh = (y1 - y0) ~/ 2;
        final out = Uint8List(cw * chh * 4);
        var headSum = 0.0, headN = 0.0;
        for (var y = 0; y < chh; y++) {
          for (var x = 0; x < cw; x++) {
            var r = 0, g = 0, b = 0, a = 0;
            for (final d in const [(0, 0), (1, 0), (0, 1), (1, 1)]) {
              final i = (y0 + y * 2 + d.$2) * w + x0 + x * 2 + d.$1;
              final al = alpha[i];
              r += px[i * 4] * al;
              g += px[i * 4 + 1] * al;
              b += px[i * 4 + 2] * al;
              a += al;
            }
            final o = (y * cw + x) * 4;
            if (a > 0) {
              out[o] = r ~/ a;
              out[o + 1] = g ~/ a;
              out[o + 2] = b ~/ a;
            }
            out[o + 3] = a ~/ 4;
            if (y < chh * 0.1 && a > 0) {
              headSum += x * a;
              headN += a;
            }
          }
        }
        writePng('${env['DEST']}/${env['PREFIX']}_${names[k]}.png', out, cw, chh);
        // «eje»: dónde cae la cabeza a lo ancho; va en Pose.axis de thug_art.dart.
        // ignore: avoid_print
        print('${names[k]}: ${cw}x$chh  eje ${(headSum / headN / cw).toStringAsFixed(3)}');
      }
    });
  });
}
