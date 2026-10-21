// Capturas de todas las situaciones del juego, incluida la caja y el final.
// Uso: OUT=<carpeta> flutter test tool/walkthrough_frames_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nidrath/game/game.dart';
import 'package:nidrath/game/world.dart';
import 'package:nidrath/screens/game_screen.dart';
import 'package:nidrath/screens/splash_screen.dart';

final out = Platform.environment['OUT']!;
final key = GlobalKey();
var n = 0;

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final b = File(f).readAsBytesSync();
      l.addFont(Future.value(ByteData.view(b.buffer)));
    }
    await l.load();
  }

  const win = 'C:/Windows/Fonts';
  const mat = 'C:/flutter/bin/cache/artifacts/material_fonts';
  await load('monospace', ['$win/consola.ttf', '$win/consolab.ttf']);
  await load('Roboto', ['$mat/roboto-regular.ttf', '$mat/roboto-bold.ttf']);
  await load('MaterialIcons', ['$mat/materialicons-regular.otf']);
}

Future<void> shot(WidgetTester tester, String name) async {
  n++;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$out/${n.toString().padLeft(2, '0')}_$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> step(WidgetTester tester, [int frames = 1]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void setup(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 740);
  tester.view.devicePixelRatio = 2;
}

void main() {
  testWidgets('splash', (tester) async {
    await tester.runAsync(loadFonts);
    setup(tester);
    await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: key, child: const SplashScreen())));
    await tester.pump(const Duration(milliseconds: 2500));
    await shot(tester, 'splash');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('partida', (tester) async {
    await tester.runAsync(loadFonts);
    setup(tester);
    await tester.pumpWidget(MaterialApp(home: RepaintBoundary(key: key, child: const GameScreen())));
    final st = tester.state(find.byType(GameScreen)) as dynamic;
    final Game g = st.game;
    final GameInput input = st.input;
    final p = g.p;
    g.firstEncounterT = 1e9;

    void calm() {
      for (final f in g.world.floors) {
        f.enemies.clear();
        f.spawnTimer = 1e9;
      }
      p.hp = maxPoints;
      p.energy = maxPoints;
      g.whisperT = 1e9;
      g.searchResult = null;
      g.searching = null;
      g.hiding = null;
      g.bigTextT = 0;
      g.faceScare = 0;
      g.redFlash = 0;
      g.shake = 0;
      g.messages.clear();
    }

    void goFloor(int f) {
      g.fi = f;
      g.floor.firstVisit = false;
    }

    calm();
    // 1. Inicio
    await step(tester, 30);
    g.say('Has entrado. La puerta se cierra detrás de ti.', const Color(0xFFBBBBBB));
    g.say('Encuentra la Caja de Otros Mundos.', const Color(0xFFB98CFF));
    await step(tester);
    await shot(tester, 'inicio_planta_baja');

    // Pausa
    st.paused = true;
    await step(tester);
    await shot(tester, 'menu_pausa');
    st.paused = false;
    await step(tester);

    // Tiendas con interruptor: oscura y encendida
    final room = g.floor.rooms.firstWhere((r) => r.switchPos != null, orElse: () => g.floor.rooms.first);
    if (room.switchPos != null) {
      calm();
      p.pos = room.switchPos!;
      await step(tester, 3);
      await shot(tester, 'interruptor_luz_apagada');
      input.action = true;
      await step(tester, 20);
      await shot(tester, 'tienda_luz_encendida');
      room.lit = false;
    }

    // Registrar cajas: buscando, objeto, vacío, rata
    Future<void> search(ItemType? loot, String name, {bool rat = false}) async {
      calm();
      final c = g.floor.crates.firstWhere((c) => !c.searched);
      c.loot = loot;
      c.rat = rat;
      p.pos = c.pos;
      input.action = true;
      await step(tester, 40);
      if (name == 'registrando') {
        await shot(tester, name);
        await step(tester, 80);
        await shot(tester, 'objeto_encontrado');
      } else {
        await step(tester, 80);
        await shot(tester, name);
      }
    }

    await search(ItemType.water, 'registrando');
    await search(null, 'caja_vacia');
    await search(null, 'rata_salta', rat: true);
    await search(ItemType.pistol, 'pistola_encontrada');
    await search(ItemType.pipe, 'barra_hierro');

    // Escondites
    calm();
    final h = g.floor.hideSpots.first;
    p.pos = h.pos;
    input.action = true;
    await step(tester, 10);
    await shot(tester, 'escondido');
    g.hidingSeen = true;
    await step(tester);
    await shot(tester, 'escondido_te_han_visto');
    g.hiding = null;
    g.hidingSeen = false;
    g.big('¡TE HAN ENCONTRADO!', const Color(0xFFFF2020), 1.4);
    g.redFlash = 0.6;
    await step(tester, 5);
    await shot(tester, 'sacado_del_escondite');

    // Primer sicario y combate
    calm();
    p.pos = g.world.start;
    p.angle = -pi / 2;
    g.firstSicarioSeen = false;
    g.firstEncounterT = 0;
    await step(tester, 40);
    await shot(tester, 'primer_sicario');
    g.firstSicarioSeen = true;
    g.firstEncounterT = 1e9;

    calm();
    // Buscar un pasillo largo para que la escena se vea bien.
    for (final t in g.floor.freeTiles) {
      final c = tileCenter(t);
      if (castRay(g.floor, c.dx, c.dy, 1, 0, 12) > 10) {
        p.pos = c;
        break;
      }
    }
    p.angle = 0;
    final e = Enemy(p.pos + const Offset(7, 0), pi, 0)
      ..state = EState.aim
      ..aimT = 0.02;
    g.floor.enemies.add(e);
    await step(tester, 6);
    await shot(tester, 'sicario_dispara');
    p.hasPistol = true;
    p.ammo = 3;
    e.state = EState.chase;
    input.attack = true;
    await step(tester, 4);
    await shot(tester, 'disparo_pistola');
    await step(tester, 30);
    calm();
    p.hasPipe = true;
    p.ammo = 0;
    final e2 = Enemy(p.pos + const Offset(1, 0), pi, 0)..hp = 1;
    g.floor.enemies.add(e2);
    p.angle = 0;
    input.attack = true;
    await step(tester, 20);
    await shot(tester, 'sicario_abatido_barra');

    // Herida oscura
    calm();
    p.hp = 4;
    p.darkWound = true;
    g.big('HERIDA OSCURA', const Color(0xFFB98CFF), 2.2);
    g.say('¡Bala maldita! La herida se vuelve negra. Las medicinas no la curan.', const Color(0xFFB98CFF));
    await step(tester, 10);
    await shot(tester, 'herida_oscura');

    // Ordenadores
    Pc? findPc(bool working) {
      for (final f in g.world.floors) {
        for (final pc in f.pcs) {
          if (pc.working == working) {
            goFloor(f.index);
            return pc;
          }
        }
      }
      return null;
    }

    calm();
    final broken = findPc(false);
    if (broken != null) {
      p.pos = broken.pos + const Offset(0, 0.5);
      input.action = true;
      await step(tester, 6);
      await shot(tester, 'ordenador_roto');
    }
    calm();
    final pc = findPc(true);
    if (pc != null) {
      p.hasManuscript = false;
      p.pos = pc.pos + const Offset(0, 0.5);
      input.action = true;
      await step(tester, 10);
      await shot(tester, 'ordenador_ia_pide_manuscrito');
    }

    // Manuscrito
    goFloor(g.world.manuscriptFloor);
    await search(ItemType.manuscript, 'manuscrito_encontrado');

    if (pc != null) {
      calm();
      findPc(true);
      p.manuscriptRevealed = true;
      p.pos = pc.pos + const Offset(0, 0.5);
      input.action = true;
      await step(tester, 20);
      await shot(tester, 'conjuro_aprendido');
    }

    // Magia
    calm();
    p.hp = 3;
    p.darkWound = true;
    p.spellLearned = true;
    p.magicCd = 0;
    g.floor.enemies.add(Enemy(p.pos + const Offset(3, 0), pi, 0)..state = EState.chase);
    input.magic = true;
    await step(tester, 12);
    await shot(tester, 'magia_sanacion');

    // Plantas, del garaje a la quinta
    for (var f = 0; f < roofFloor; f++) {
      calm();
      g.fi = f;
      p.pos = tileCenter(arrivalTile(g.floor));
      g.big(floorNames[f].toUpperCase(), const Color(0xFFCCCCCC), 1.8);
      await step(tester, 20);
      await shot(tester, 'planta_${f}_${floorNames[f].split(' ').first.toLowerCase()}');
    }

    // Garaje: coches que se pueden registrar
    calm();
    goFloor(garageFloor);
    final car = g.floor.cars.firstWhere((c) => c.crate != null, orElse: () => g.floor.cars.first);
    p.pos = car.center + const Offset(1, -0.5);
    p.angle = pi;
    await step(tester, 10);
    await shot(tester, 'garaje_coches');

    // Ascensor
    calm();
    goFloor(groundFloor);
    p.pos = tileCenter(g.floor.elevator!);
    input.action = true;
    await step(tester, 6);
    await shot(tester, 'ascensor_panel');
    g.elevatorOpen = false;

    // Maniquí que grita
    calm();
    g.faceScare = 0.7;
    g.shake = 14;
    await step(tester, 4);
    await shot(tester, 'susto_cara');

    // La hoja en blanco y las gafas
    calm();
    p.hasManuscript = true;
    p.manuscriptRevealed = false;
    p.hasGlasses = true;
    p.wearingGlasses = false;
    await step(tester, 3);
    await shot(tester, 'inventario_hoja_en_blanco_y_gafas');
    input.use = ItemType.glasses;
    await step(tester, 10);
    await shot(tester, 'gafas_letras_ocultas');
    input.use = ItemType.glasses;
    await step(tester, 2);

    // LA CAJA y EL CARNICERO
    calm();
    goFloor(g.world.boxFloor);
    final box = g.floor.box!;
    p.spellLearned = false;
    p.pos = box + const Offset(0, 1);
    p.angle = -pi / 2;
    input.action = true;
    await step(tester, 10);
    await shot(tester, 'caja_sellada_sin_conjuro');
    calm();
    p.spellLearned = true;
    await step(tester, 20);
    await shot(tester, 'carnicero_aparece');
    final boss = g.floor.boss!;
    p.hasPistol = true;
    p.ammo = 30;
    for (var i = 0; i < 40; i++) {
      p.hp = maxPoints;
      p.angle = (boss.pos - p.pos).direction;
      if (i % 20 == 0) input.attack = true;
      await step(tester);
    }
    await shot(tester, 'carnicero_combate');
    while (boss.alive) {
      p.hp = maxPoints;
      p.angle = (boss.pos - p.pos).direction;
      input.attack = true;
      await step(tester, 25);
    }
    calm();
    await step(tester, 30);
    await shot(tester, 'carnicero_abatido');
    p.pos = box + const Offset(0, 1);
    await step(tester, 3);
    await shot(tester, 'caja_meter_invento');
    input.action = true;
    await step(tester, 20);
    await shot(tester, 'a_la_azotea');

    // Derrotas (en partidas aparte)
    final keep = st.game;
    st.game = Game();
    final g2 = st.game as Game;
    g2.firstEncounterT = 1e9;
    await step(tester, 5);
    g2.p.hp = 0;
    await step(tester, 100);
    await shot(tester, 'derrota_atrapado');

    st.game = Game();
    final g3 = st.game as Game;
    g3.firstEncounterT = 1e9;
    await step(tester, 5);
    g3.headshot = true;
    g3.p.hp = 0;
    await step(tester, 100);
    await shot(tester, 'derrota_tiro_en_la_cabeza');
    st.game = keep;

    // Azotea: puerta, emboscada y helicóptero
    calm();
    goFloor(roofFloor - 1);
    p.pos = tileCenter(g.floor.up!);
    input.action = true;
    await step(tester, 70);
    for (final e in g.floor.enemies) {
      e.shootCd = 99;
    }
    await step(tester, 30);
    await shot(tester, 'azotea_emboscada');
    for (var wave = 0; wave < 2; wave++) {
      for (final e in g.floor.enemies) {
        e.state = EState.dead;
      }
      await step(tester, 3);
    }
    p.pos = g.floor.helipad! + const Offset(0, 4);
    p.angle = -pi / 2;
    await step(tester, 90);
    await shot(tester, 'helicoptero_llega');
    while (!g.heliLanded) {
      await step(tester, 10);
    }
    p.pos = g.floor.helipad!;
    await step(tester, 3);
    await shot(tester, 'helicoptero_subir');
    input.action = true;
    await step(tester);
    for (final (secs, name) in [(0.4, 'victoria_destello'), (1.5, 'victoria_despegue'), (3.5, 'victoria_alejandose')]) {
      while (g.endT < secs) {
        await step(tester);
      }
      await shot(tester, name);
    }

    await tester.pumpWidget(const SizedBox());
  });
}
