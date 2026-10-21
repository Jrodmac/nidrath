import 'dart:math';
import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidrath/game/game.dart';
import 'package:nidrath/game/painter.dart';
import 'package:nidrath/game/world.dart';
import 'package:nidrath/screens/game_screen.dart';
import 'package:nidrath/screens/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plantas, garaje y azotea bien conectados; mínimo de tiendas', () {
    for (var seed = 0; seed < 30; seed++) {
      final w = generateWorld(Random(seed));
      expect(w.floors.length, floorCount);
      for (final f in w.floors) {
        final from = arrivalTile(f);
        final why = 'seed $seed planta ${f.index}';
        if (f.up != null && f.up != from) expect(findPath(f, from, f.up!), isNotEmpty, reason: why);
        if (f.elevator != null) expect(findPath(f, from, f.elevator!), isNotEmpty, reason: why);
        if (f.box != null) expect(findPath(f, from, tileOf(f.box!)), isNotEmpty, reason: why);
        if (f.helipad != null) expect(findPath(f, from, tileOf(f.helipad!)), isNotEmpty, reason: why);
        if (f.index != garageFloor && f.index != roofFloor) {
          expect(f.rooms.length, greaterThanOrEqualTo(minRooms), reason: why);
        }
      }
      expect(w.floors[garageFloor].cars, isNotEmpty);
      expect(w.floors[roofFloor].helipad, isNotNull);
      final crates = w.floors.expand((f) => f.crates);
      expect(crates.where((c) => c.loot == ItemType.manuscript).length, 1);
      expect(crates.where((c) => c.loot == ItemType.glasses).length, 1);
      expect(w.manuscriptFloor, isNot(w.glassesFloor));
      expect(w.floors.expand((f) => f.pcs).where((p) => p.working).length, 2);
    }
  });

  testWidgets('la simulación y el render aguantan varios minutos de juego', (tester) async {
    final rng = Random(1);
    final g = Game();
    final input = GameInput();
    final painter = GamePainter(g);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < 60 * 180; i++) {
      if (i % 90 == 0) input.move = Offset(rng.nextDouble() * 2 - 1, rng.nextDouble() * 2 - 1);
      if (i % 40 == 0) input.attack = true;
      if (i % 25 == 0) input.action = true;
      g.update(1 / 60, input);
      if (i % 300 == 0) painter.paint(canvas, const Size(800, 400));
      if (g.lost || g.won) break;
    }
    recorder.endRecording();
    // ignore: avoid_print
    print('frames simulados hasta: t=${g.time.toStringAsFixed(1)}s lost=${g.lost} hp=${g.p.hp}');
  });

  testWidgets('hoja, gafas, IA, carnicero, caja, azotea y helicóptero', (tester) async {
    final g = Game();
    final input = GameInput();
    final painter = GamePainter(g);
    final canvas = Canvas(PictureRecorder());
    for (final f in g.world.floors) {
      f.enemies.clear();
      f.spawnTimer = 1e9;
    }
    void step([int n = 1]) {
      for (var i = 0; i < n; i++) {
        g.p.hp = maxPoints;
        g.p.energy = maxPoints;
        g.update(1 / 60, input);
      }
      painter.paint(canvas, const Size(800, 400));
    }

    void take(ItemType t) {
      final f = g.world.floors.firstWhere((f) => f.crates.any((c) => c.loot == t));
      g.fi = f.index;
      g.p.pos = f.crates.firstWhere((c) => c.loot == t).pos;
      input.action = true;
      step(130);
    }

    Pc workingPc() {
      final f = g.world.floors.firstWhere((f) => f.pcs.any((p) => p.working));
      g.fi = f.index;
      return f.pcs.firstWhere((p) => p.working);
    }

    take(ItemType.manuscript);
    expect(g.p.hasManuscript, isTrue);
    expect(g.p.manuscriptRevealed, isFalse);
    // La IA no lee una hoja en blanco.
    g.p.pos = workingPc().pos;
    input.action = true;
    step();
    expect(g.p.spellLearned, isFalse);

    take(ItemType.glasses);
    expect(g.p.hasGlasses, isTrue);
    expect(g.p.manuscriptRevealed, isFalse, reason: 'hay que ponérselas');
    input.use = ItemType.glasses;
    step();
    expect(g.p.wearingGlasses, isTrue);
    expect(g.p.manuscriptRevealed, isTrue);
    g.p.pos = workingPc().pos;
    input.action = true;
    step();
    expect(g.p.spellLearned, isTrue);

    // El carnicero aparece junto a la caja y aguanta 10 balas.
    g.fi = g.world.boxFloor;
    g.p.pos = g.floor.box! + const Offset(0.3, 0);
    step();
    final boss = g.floor.boss!;
    expect(g.actionKind, 'boxSealed');
    g.p.hasPistol = true;
    g.p.ammo = 30;
    for (var i = 0; i < 1200 && boss.alive; i++) {
      g.p.angle = (boss.pos - g.p.pos).direction;
      if (i % 25 == 0) input.attack = true;
      step();
    }
    expect(boss.alive, isFalse);
    expect(30 - g.p.ammo, greaterThanOrEqualTo(10));
    g.p.pos = g.floor.box! + const Offset(0.3, 0);
    input.action = true;
    step();
    expect(g.boxDone, isTrue);
    expect(g.won, isFalse);

    // Azotea: emboscada, refuerzos y helicóptero.
    g.fi = roofFloor - 1;
    for (final f in g.world.floors) {
      f.enemies.clear();
      f.spawnTimer = 1e9;
    }
    g.p.pos = tileCenter(g.floor.up!);
    input.action = true;
    step(70);
    expect(g.fi, roofFloor);
    for (var wave = 0; wave < 2; wave++) {
      expect(g.floor.enemies.where((e) => e.alive && e.fearless), isNotEmpty);
      for (final e in g.floor.enemies) {
        e.state = EState.dead;
      }
      step(2);
    }
    expect(g.heliT, greaterThanOrEqualTo(0));
    step((Game.heliLandTime * 60).ceil() + 5);
    g.p.pos = g.floor.helipad!;
    input.action = true;
    step();
    expect(g.won, isTrue);
    step(200);
  });

  testWidgets('salir de la partida vuelve a la pantalla de inicio', (tester) async {
    tester.view.physicalSize = const Size(1600, 740);
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('CONTINUAR'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('PAUSA'), findsNothing);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('SALIR'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(GameScreen), findsNothing);
  });
}
