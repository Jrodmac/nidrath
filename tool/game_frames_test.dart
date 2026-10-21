import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidrath/game/game.dart';
import 'package:nidrath/game/painter.dart';
import 'package:nidrath/game/world.dart';

Future<void> shot(Game g, String name) async {
  final rec = ui.PictureRecorder();
  GamePainter(g).paint(Canvas(rec), const Size(1600, 740));
  final img = await rec.endRecording().toImage(1600, 740);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File('${Platform.environment['OUT']}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  testWidgets('frames', (tester) async {
    await tester.runAsync(() async {
      final g = Game();
      final input = GameInput()..move = const Offset(0, -1);
      for (var i = 0; i < 70; i++) {
        g.update(1 / 60, input);
      }
      await shot(g, 'game_start');
      // Dentro de una tienda con interruptor, encendida.
      final room = g.floor.rooms.firstWhere((r) => r.switchPos != null, orElse: () => g.floor.rooms.first);
      g.p.pos = room.rect.center;
      input.move = Offset.zero;
      g.update(1 / 60, input);
      await shot(g, 'game_room_dark');
      room.lit = true;
      g.update(1 / 60, input);
      await shot(g, 'game_room_lit');
      room.lit = false;
      // Un sicario delante.
      g.p.pos = tileCenter(startTile);
      g.p.angle = 0;
      g.firstSicarioSeen = true;
      final e = Enemy(g.p.pos + const Offset(9, 0), pi, 0);
      g.floor.enemies.add(e);
      for (var i = 0; i < 3; i++) {
        g.update(1 / 60, input);
      }
      await shot(g, 'game_enemy');
    });
  });
}
