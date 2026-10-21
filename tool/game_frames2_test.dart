import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidrath/game/game.dart';
import 'package:nidrath/game/painter.dart';
import 'package:nidrath/game/world.dart';
import 'package:nidrath/screens/game_screen.dart';

final out = Platform.environment['OUT']!;

Future<void> shot(Game g, String name) async {
  final rec = ui.PictureRecorder();
  GamePainter(g).paint(Canvas(rec), const Size(1600, 740));
  final img = await rec.endRecording().toImage(1600, 740);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  testWidgets('frames', (tester) async {
    await tester.runAsync(() async {
      final g = Game();
      final input = GameInput();
      g.p.pos = tileCenter(startTile);
      g.p.angle = 0;
      g.firstSicarioSeen = true;
      final e = Enemy(g.p.pos + const Offset(8, 0), pi, 0)..state = EState.aim..aimT = 0.02;
      g.floor.enemies.add(e);
      for (var i = 0; i < 6; i++) {
        g.update(1 / 60, input);
      }
      await shot(g, 'g2_bullet');
      // Panel de registro
      final c = g.floor.crates.first..loot = ItemType.water;
      g.p.pos = c.pos;
      g.floor.enemies.clear();
      input.action = true;
      for (var i = 0; i < 50; i++) {
        g.update(1 / 60, input);
      }
      await shot(g, 'g2_searching');
      for (var i = 0; i < 70; i++) {
        g.update(1 / 60, input);
      }
      await shot(g, 'g2_found');
      // Escondite
      final h = g.floor.hideSpots.first;
      g.p.pos = h.pos;
      g.searchResult = null;
      input.action = true;
      g.update(1 / 60, input);
      await shot(g, 'g2_hidden');
    });
  });

  testWidgets('controles', (tester) async {
    tester.view.physicalSize = const Size(1600, 740);
    tester.view.devicePixelRatio = 2;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: key, child: const GameScreen())));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$out/g2_ui.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
