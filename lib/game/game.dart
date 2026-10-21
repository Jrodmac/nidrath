import 'dart:math';

import 'package:flutter/services.dart';

import 'audio.dart';
import 'world.dart';

const double maxPoints = 10;

class GameInput {
  Offset move = Offset.zero;
  bool run = false;
  bool attack = false;
  bool action = false;
  bool magic = false;
  ItemType? use;
}

class Player {
  Offset pos;
  double angle = -pi / 2;
  double hp = maxPoints;
  double energy = maxPoints;
  bool darkWound = false;
  bool hasPistol = false;
  bool hasPipe = false;
  bool hasManuscript = false; // la hoja en blanco
  bool manuscriptRevealed = false; // con las gafas aparecen las letras
  bool hasGlasses = false;
  bool wearingGlasses = false;
  bool spellLearned = false;
  int ammo = 0;
  final Map<ItemType, int> inv = {};
  double attackCd = 0;
  double magicCd = 0;
  double hurtT = 0;
  double stillT = 0;
  bool moving = false;
  bool running = false;
  Offset vel = Offset.zero;
  double walkPhase = 0;
  Player(this.pos);
}

class Msg {
  final String text;
  final Color color;
  double t = 0;
  Msg(this.text, this.color);
}

class Bullet {
  Offset pos;
  final Offset dir;
  final double speed;
  final bool fromPlayer;
  double life = 0.9;
  Bullet(this.pos, this.dir, this.speed, this.fromPlayer);
}

/// Fogonazo de un disparo: ilumina un instante lo que hay alrededor.
class Flash {
  final Offset pos;
  final List<Offset> poly;
  double t = 0.1;
  Flash(this.pos, this.poly);
}

/// Lo que ha salido al registrar un mueble, para la animación.
class SearchResult {
  final int kind;
  final ItemType? item;
  final bool rat;
  double t = 0;
  SearchResult(this.kind, this.item, this.rat);
}

class Spark {
  Offset pos, vel;
  double life;
  final Color color;
  Spark(this.pos, this.vel, this.life, this.color);
}

class Game {
  final Random rng = Random();
  final GameAudio audio = GameAudio.instance;
  late final int seed; // el mapa se regenera igual a partir de la semilla
  late final World world;
  late final Player p;
  int fi = groundFloor;
  FloorData get floor => world.floors[fi];

  double time = 0;

  // Luz
  static const double coneHalf = 0.55;
  static const double coneLenBase = 13.0;
  static const double ambientBase = 2.6;
  double flashPower = 1;
  double flashOutT = 0;
  double nextFlashFail = 40;
  List<Offset> ambientPoly = const [];
  List<Offset> conePoly = const [];
  double coneLen = coneLenBase;
  double ambientR = ambientBase;
  List<Offset> flashPoly = const [];
  double muzzleFlash = 0;
  double magicFlash = 0;

  // Efectos
  double shake = 0;
  double redFlash = 0;
  double whiteFlash = 0;
  double faceScare = 0;
  double glitch = 0;
  double zoomPunch = 0;
  String? bigText;
  double bigTextT = 0;
  Color bigTextColor = const Color(0xFFFF2020);
  final List<Msg> messages = [];
  final List<Bullet> bullets = [];
  final List<Flash> flashes = [];
  final List<Spark> sparks = [];
  SearchResult? searchResult;

  // Estado
  bool won = false;
  bool lost = false;
  bool headshot = false;
  double endT = 0;
  double scareCd = 8;
  double whisperT = 25;
  double heartbeatT = 0;
  double stepCd = 0;
  double breathCd = 0;
  bool firstSicarioSeen = false;
  Crate? searching;
  double searchT = 0;
  static const double searchTime = 1.6;
  String? hint;
  String actionKind = 'none';
  HideSpot? hiding;
  bool hidingSeen = false;
  double hideBreathT = 0;
  double unarmedMsgT = 0;
  int kills = 0;
  int? pendingFloor;
  Point<int>? pendingArrival;
  bool elevatorOpen = false;

  // Huida: caja, jefe, azotea y helicóptero.
  bool boxDone = false;
  bool roofWave = false, roofWave2 = false;
  double heliT = -1; // >= 0: el helicóptero está llegando
  static const double heliLandTime = 5;
  bool get heliLanded => heliT >= heliLandTime;
  double transition = 0;
  double firstEncounterT = 18;
  double switchAlertT = 0;

  /// Punto de control pendiente de guardar (lo recoge la pantalla de juego).
  Map<String, dynamic>? pendingSave;

  Game({Map<String, dynamic>? save}) {
    seed = (save?['seed'] as int?) ?? Random().nextInt(1 << 31);
    world = generateWorld(Random(seed));
    p = Player(world.start);
    firstEncounterT = 18 + rng.nextDouble() * 10;
    if (save != null) {
      _restore(save);
    } else {
      say('Has entrado. La puerta se cierra detrás de ti.', const Color(0xFFBBBBBB));
      say('Encuentra la Caja de Otros Mundos.', const Color(0xFFB98CFF));
      _checkpoint();
    }
    _updateLight();
  }

  // --- Puntos de control -----------------------------------------------------------

  void _checkpoint() => pendingSave = snapshot();

  Map<String, dynamic> snapshot() => {
        'seed': seed,
        'fi': fi,
        'x': p.pos.dx,
        'y': p.pos.dy,
        'time': time,
        'kills': kills,
        'hp': p.hp,
        'energy': p.energy,
        'dark': p.darkWound,
        'pistol': p.hasPistol,
        'pipe': p.hasPipe,
        'sheet': p.hasManuscript,
        'revealed': p.manuscriptRevealed,
        'glasses': p.hasGlasses,
        'wearing': p.wearingGlasses,
        'spell': p.spellLearned,
        'ammo': p.ammo,
        'inv': {for (final e in p.inv.entries) e.key.name: e.value},
        'boxDone': boxDone,
        'firstSicario': firstSicarioSeen,
        'floors': [
          for (final f in world.floors)
            {
              'visited': !f.firstVisit,
              'cap': f.enemyCap,
              'searched': [for (var i = 0; i < f.crates.length; i++) if (f.crates[i].searched) i],
              'pcs': [for (var i = 0; i < f.pcs.length; i++) if (f.pcs[i].used) i],
              'lit': [for (var i = 0; i < f.rooms.length; i++) if (f.rooms[i].lit) i],
              'items': [for (final it in f.items) [it.type.name, it.pos.dx, it.pos.dy]],
              if (f.boss != null && !f.boss!.alive) 'boss': [f.boss!.pos.dx, f.boss!.pos.dy],
            }
        ],
      };

  void _restore(Map<String, dynamic> s) {
    fi = s['fi'] as int;
    p.pos = Offset((s['x'] as num).toDouble(), (s['y'] as num).toDouble());
    time = (s['time'] as num).toDouble();
    kills = s['kills'] as int;
    // Volver con media vida como mínimo: si no, un mal guardado sería una trampa.
    p.hp = max((s['hp'] as num).toDouble(), maxPoints / 2);
    p.energy = maxPoints;
    p.darkWound = s['dark'] as bool;
    p.hasPistol = s['pistol'] as bool;
    p.hasPipe = s['pipe'] as bool;
    p.hasManuscript = s['sheet'] as bool;
    p.manuscriptRevealed = s['revealed'] as bool;
    p.hasGlasses = s['glasses'] as bool;
    p.wearingGlasses = s['wearing'] as bool;
    p.spellLearned = s['spell'] as bool;
    p.ammo = s['ammo'] as int;
    (s['inv'] as Map<String, dynamic>).forEach((k, v) => p.inv[ItemType.values.byName(k)] = v as int);
    boxDone = s['boxDone'] as bool;
    firstSicarioSeen = s['firstSicario'] as bool;
    final floors = s['floors'] as List;
    for (var i = 0; i < world.floors.length; i++) {
      final f = world.floors[i];
      final d = floors[i] as Map<String, dynamic>;
      f.firstVisit = !(d['visited'] as bool);
      f.enemyCap = d['cap'] as int;
      for (final c in d['searched'] as List) {
        f.crates[c as int].searched = true;
      }
      for (final c in d['pcs'] as List) {
        f.pcs[c as int].used = true;
      }
      for (final r in d['lit'] as List) {
        f.rooms[r as int].lit = true;
      }
      f.items
        ..clear()
        ..addAll([
          for (final it in d['items'] as List)
            GroundItem(Offset((it[1] as num).toDouble(), (it[2] as num).toDouble()), ItemType.values.byName(it[0] as String)),
        ]);
      final b = d['boss'] as List?;
      if (b != null) {
        f.boss = Boss(Offset((b[0] as num).toDouble(), (b[1] as num).toDouble()))
          ..hp = 0
          ..deadT = 5;
      }
      if (boxDone && i != roofFloor) f.spawnTimer = min(f.spawnTimer, 8 + rng.nextDouble() * 10);
    }
    _clearArrival();
    big(floorNames[fi].toUpperCase(), const Color(0xFFCCCCCC), 1.8);
    say('Vuelves en ti. No ha terminado.', const Color(0xFFBBBBBB));
    if (fi == roofFloor) _roofAmbush();
  }

  /// Nadie te espera pegado a la escalera al llegar.
  void _clearArrival() {
    for (final e in floor.enemies) {
      if (e.alive && (e.pos - p.pos).distance < 7) {
        final far = _farTile(14);
        if (far != null) e.pos = tileCenter(far);
        e.state = EState.patrol;
        e.path = [];
      }
    }
  }

  void say(String text, [Color color = const Color(0xFFDDDDDD)]) {
    messages.add(Msg(text, color));
    if (messages.length > 4) messages.removeAt(0);
  }

  void big(String text, [Color color = const Color(0xFFFF2020), double secs = 2.2]) {
    bigText = text;
    bigTextColor = color;
    bigTextT = secs;
  }

  // ---------------------------------------------------------------------------

  void update(double dt, GameInput input) {
    time += dt;
    _updateFx(dt);
    if (won || lost) {
      endT += dt;
      _clearInput(input);
      return;
    }
    if (transition > 0) {
      transition -= dt;
      if (pendingFloor != null && transition < 0.45) _switchFloor();
    }
    _updatePlayer(dt, input);
    _updateLight();
    _updateFlashlight(dt);
    _updateEnemies(dt);
    _updateBoss(dt);
    _updateRoof(dt);
    _updateBullets(dt);
    _scriptedEncounter();
    _updateSwitchAlert(dt);
    _updateMannequins(dt);
    _updateLamps(dt);
    _updateAmbient(dt);
    _computeHint();
    _clearInput(input);
  }

  void _clearInput(GameInput input) {
    input.attack = false;
    input.action = false;
    input.magic = false;
    input.use = null;
  }

  void _updateFx(double dt) {
    shake = max(0, shake - dt * 30);
    redFlash = max(0, redFlash - dt * 1.5);
    whiteFlash = max(0, whiteFlash - dt * 0.6);
    faceScare = max(0, faceScare - dt);
    glitch = max(0, glitch - dt);
    zoomPunch = max(0, zoomPunch - dt * 1.5);
    muzzleFlash = max(0, muzzleFlash - dt);
    magicFlash = max(0, magicFlash - dt);
    bigTextT = max(0, bigTextT - dt);
    unarmedMsgT = max(0, unarmedMsgT - dt);
    if (searchResult != null) {
      searchResult!.t += dt;
      if (searchResult!.t > 1.8) searchResult = null;
    }
    for (final f in flashes) {
      f.t -= dt;
    }
    flashes.removeWhere((f) => f.t <= 0);
    for (final m in messages) {
      m.t += dt;
    }
    messages.removeWhere((m) => m.t > 6);
    for (final s in sparks) {
      s.pos += s.vel * dt;
      s.vel = s.vel * 0.92;
      s.life -= dt;
    }
    sparks.removeWhere((s) => s.life <= 0);
    if (won) {
      for (final e in floor.enemies) {
        e.fade = max(0, e.fade - dt * 0.7);
      }
    }
  }

  // --- Jugador ---------------------------------------------------------------

  void _updatePlayer(double dt, GameInput input) {
    final mv = hiding != null ? Offset.zero : input.move;
    final mag = min(1.0, mv.distance);
    final exhausted = p.energy <= 0;
    p.moving = mag > 0.12 && transition <= 0.3;
    p.running = p.moving && (input.run || mag > 0.92) && !exhausted;
    if (p.moving) {
      p.angle = lerpAngle(p.angle, mv.direction, dt * 14);
      final speed = (p.running ? 4.0 : 2.5) * mag * (exhausted ? 0.7 : 1);
      final before = p.pos;
      p.pos = moveWithCollision(floor, p.pos, Offset(cos(mv.direction), sin(mv.direction)) * speed * dt, 0.28);
      p.vel = dt > 0 ? (p.pos - before) / dt : Offset.zero;
      p.walkPhase += dt * speed * 2.2;
      p.stillT = 0;
      if (searching != null) {
        searching = null;
        say('Dejas de registrar.', const Color(0xFF888888));
      }
    } else {
      p.stillT += dt;
      p.vel = Offset.zero;
    }

    if (hiding != null) {
      hideBreathT -= dt;
      if (hideBreathT <= 0) {
        hideBreathT = 3.2;
        audio.play(Sfx.breath, volume: 0.35);
      }
    }

    if (searching != null) {
      searchT += dt;
      if (searchT >= searchTime) _finishSearch(searching!);
    }

    final before = p.energy;
    p.energy = max(0, p.energy - dt * (1 / 35 + (p.running ? 1 / 12 : 0)));
    if (before > 3 && p.energy <= 3) {
      say('Te flaquean las piernas. Bebe o come algo pronto.', const Color(0xFFE8C030));
    }
    if (before > 0 && p.energy <= 0) {
      say('AGOTADO: ya no puedes correr y vas más lento. ¡Come o bebe!', const Color(0xFFFF9040));
    }
    if (exhausted) _damage(dt / 25, quiet: true);
    if (p.darkWound) _damage(dt / 20, quiet: true);

    p.attackCd = max(0, p.attackCd - dt);
    p.magicCd = max(0, p.magicCd - dt);
    p.hurtT = max(0, p.hurtT - dt);

    for (final it in [...floor.items]) {
      if ((it.pos - p.pos).distance < 0.6) {
        floor.items.remove(it);
        _gain(it.type);
      }
    }

    if (input.attack) _attack();
    if (input.action) _action();
    if (input.magic) castMagic();
    if (input.use != null) useItem(input.use!);

    // Latido con poca salud o energía.
    final danger = min(p.hp, p.energy * 1.5);
    if (danger < 4) {
      heartbeatT -= dt;
      if (heartbeatT <= 0) {
        audio.play(Sfx.heartbeat, volume: 0.9);
        HapticFeedback.lightImpact();
        heartbeatT = 0.5 + danger * 0.15;
      }
    }

    if (p.hp <= 0) _lose();
  }

  void _damage(double amount, {bool quiet = false}) {
    p.hp = max(0, p.hp - amount);
    if (!quiet) {
      p.hurtT = 0.4;
      redFlash = max(redFlash, 0.7);
      shake = max(shake, 7);
      HapticFeedback.mediumImpact();
      audio.play(Sfx.hurt);
    }
  }

  void _gain(ItemType t) {
    audio.play(Sfx.pickup, volume: 0.7);
    switch (t) {
      case ItemType.pistol:
        if (p.hasPistol) {
          p.ammo += 3;
          say('Otra pistola. Le sacas 3 balas.', const Color(0xFFE8C468));
        } else {
          p.hasPistol = true;
          p.ammo += 4;
          say('¡Una pistola! Con 4 balas.', const Color(0xFFE8C468));
        }
      case ItemType.ammo:
        p.ammo += 4;
        say('Munición: +4 balas.', const Color(0xFFE8C468));
      case ItemType.pipe:
        if (p.hasPipe) {
          say('Otra barra de hierro. Ya tienes una.', const Color(0xFF999999));
        } else {
          p.hasPipe = true;
          say('Barra de hierro. Mejor que los puños.', const Color(0xFFE8C468));
        }
      case ItemType.manuscript:
        p.hasManuscript = true;
        say('Una hoja vieja y amarillenta. Está en blanco.', const Color(0xFFAAAAAA));
        _checkReveal();
      case ItemType.glasses:
        p.hasGlasses = true;
        say('Unas gafas de montura gruesa. Los cristales son de color ámbar.', const Color(0xFFAAAAAA));
      default:
        p.inv[t] = (p.inv[t] ?? 0) + 1;
        say('Encuentras: ${itemInfo[t]!.name}.', const Color(0xFF9FE0A0));
    }
  }

  void useItem(ItemType t) {
    if (t == ItemType.glasses) {
      _toggleGlasses();
      return;
    }
    final n = p.inv[t] ?? 0;
    if (n <= 0 || won || lost) return;
    p.inv[t] = n - 1;
    switch (t) {
      case ItemType.water:
      case ItemType.food:
        p.energy = min(maxPoints, p.energy + 2);
        say(t == ItemType.water ? 'Bebes. +2 energía.' : 'Comes algo. +2 energía.', const Color(0xFFE8D468));
        audio.play(Sfx.pickup, volume: 0.5);
      case ItemType.medkit:
      case ItemType.bandage:
      case ItemType.painkiller:
        p.hp = min(maxPoints, p.hp + 2);
        say('${itemInfo[t]!.name}: +2 salud.', const Color(0xFF9FE0A0));
        if (p.darkWound) say('La herida oscura no se cierra... necesitas magia.', const Color(0xFFB98CFF));
        audio.play(Sfx.pickup, volume: 0.5);
      case ItemType.pills:
        final r = rng.nextDouble();
        if (r < 0.4) {
          p.hp = min(maxPoints, p.hp + 2);
          say('Las pastillas funcionan. +2 salud.', const Color(0xFF9FE0A0));
        } else if (r < 0.75) {
          say('No pasa nada. Caducadas.', const Color(0xFF999999));
        } else {
          _damage(1);
          say('Sabían a óxido... -1 salud.', const Color(0xFFFF6060));
        }
      default:
        break;
    }
  }

  void _toggleGlasses() {
    if (!p.hasGlasses || won || lost) return;
    p.wearingGlasses = !p.wearingGlasses;
    audio.play(Sfx.cock, volume: 0.3);
    say(p.wearingGlasses ? 'Te pones las gafas. Todo se vuelve ámbar.' : 'Te quitas las gafas.',
        const Color(0xFFE0B060));
    _checkReveal();
  }

  /// Tinta invisible: solo se ve con las gafas puestas.
  void _checkReveal() {
    if (!p.wearingGlasses || !p.hasManuscript || p.manuscriptRevealed) return;
    p.manuscriptRevealed = true;
    audio.play(Sfx.magic);
    big('LETRAS OCULTAS', const Color(0xFFE0B060), 2.4);
    say('¡Con las gafas aparecen letras en la hoja en blanco!', const Color(0xFFE0B060));
    say('Símbolos imposibles. Tú no sabes leerlos. Una IA, quizá sí.', const Color(0xFFB98CFF));
  }

  void castMagic() {
    if (!p.spellLearned || won || lost) return;
    if (p.magicCd > 0) {
      say('El conjuro aún no ha vuelto a ti (${p.magicCd.ceil()} s).', const Color(0xFF8C6FBF));
      return;
    }
    if (p.energy < 2) {
      say('Estás demasiado agotado para invocarlo.', const Color(0xFF8C6FBF));
      return;
    }
    p.energy -= 2;
    p.magicCd = 25;
    final cured = p.darkWound;
    p.darkWound = false;
    p.hp = min(maxPoints, p.hp + 4);
    magicFlash = 1.4;
    flashPoly = lightPolygon(floor, p.pos, 8, 120);
    audio.play(Sfx.magic);
    big('SANACIÓN', const Color(0xFFD9B3FF), 1.5);
    say(cured ? 'La herida oscura se disuelve en luz violeta.' : 'Una luz violeta te recorre. +4 salud.',
        const Color(0xFFD9B3FF));
    for (final e in floor.enemies) {
      if (e.alive && (e.pos - p.pos).distance < 9) _makeFlee(e, 6);
    }
  }

  Offset? _autoAim() {
    Offset? best;
    var bestScore = 1e9;
    void consider(Offset pos) {
      final d = (pos - p.pos).distance;
      if (d > 12) return;
      final diff = angleDiff((pos - p.pos).direction, p.angle);
      if (diff > 0.7 || !lineOfSight(floor, p.pos, pos)) return;
      final score = d + diff * 6;
      if (score < bestScore) {
        bestScore = score;
        best = pos;
      }
    }

    for (final e in floor.enemies) {
      if (e.alive) consider(e.pos);
    }
    final b = floor.boss;
    if (b != null && b.alive) consider(b.pos);
    return best;
  }

  bool get armed => (p.hasPistol && p.ammo > 0) || p.hasPipe;

  void _attack() {
    if (p.attackCd > 0 || transition > 0.3 || hiding != null) return;
    if (!armed) {
      if (p.hasPistol) audio.play(Sfx.cock, volume: 0.6);
      if (unarmedMsgT <= 0) {
        unarmedMsgT = 4;
        say(p.hasPistol ? 'Sin balas. Corre.' : 'No tienes armas. Corre y escóndete.', const Color(0xFFFF9060));
      }
      return;
    }
    final target = _autoAim();
    if (target != null) p.angle = (target - p.pos).direction;
    final dir = Offset(cos(p.angle), sin(p.angle));
    if (p.hasPistol && p.ammo > 0) {
      p.ammo--;
      p.attackCd = 0.35;
      muzzleFlash = 0.12;
      flashPoly = lightPolygon(floor, p.pos, 7, 90);
      shake = max(shake, 4);
      audio.play(Sfx.gunshot);
      bullets.add(Bullet(p.pos + dir * 0.45, dir, 34, true));
      // El disparo se oye: unos huyen, otros vienen.
      for (final e in floor.enemies) {
        if (!e.alive) continue;
        if ((e.pos - p.pos).distance < 14) {
          if (rng.nextDouble() < 0.4) {
            _makeFlee(e, 4);
          } else if (e.state == EState.patrol) {
            e.state = EState.chase;
            e.lastKnown = p.pos;
            e.unseenT = 0;
          }
        }
      }
      if (p.ammo == 0) say('Última bala.', const Color(0xFFFF9060));
      return;
    }
    if (p.hasPistol && p.ammo == 0) audio.play(Sfx.cock, volume: 0.6);
    // Barra de hierro.
    p.attackCd = 0.5;
    audio.play(Sfx.swing, volume: 0.7);
    const range = 1.3;
    const dmg = 2;
    final b = floor.boss;
    if (b != null && b.alive) {
      final rel = b.pos - p.pos;
      if (rel.distance <= range + 0.2 && angleDiff(rel.direction, p.angle) <= 1.0) {
        audio.play(Sfx.punch);
        _hitBoss(0.5);
        return;
      }
    }
    for (final e in floor.enemies) {
      if (!e.alive) continue;
      final rel = e.pos - p.pos;
      if (rel.distance > range) continue;
      if (angleDiff(rel.direction, p.angle) > 1.0) continue;
      audio.play(Sfx.punch);
      _hitEnemy(e, dmg);
      break;
    }
  }

  void _hitEnemy(Enemy e, int dmg) {
    e.hp -= dmg;
    for (var i = 0; i < 8; i++) {
      final a = rng.nextDouble() * 2 * pi;
      sparks.add(Spark(e.pos, Offset(cos(a), sin(a)) * (1 + rng.nextDouble() * 2), 0.4, const Color(0xFF8A0000)));
    }
    if (e.hp <= 0) {
      e.state = EState.dead;
      e.deadT = 0;
      kills++;
      say(['El sicario cae.', 'Uno menos.', 'No se levanta.'][rng.nextInt(3)], const Color(0xFFDDAAAA));
      if (rng.nextDouble() < 0.4) floor.items.add(GroundItem(e.pos + const Offset(0.2, 0.1), ItemType.ammo));
      for (final o in floor.enemies) {
        if (o.alive && (o.pos - e.pos).distance < 9 && lineOfSight(floor, o.pos, e.pos)) _makeFlee(o, 5);
      }
    } else {
      _makeFlee(e, 4.5);
      say('¡Huye como una rata!', const Color(0xFFDDAAAA));
    }
  }

  void _action() {
    if (transition > 0) return;
    if (hiding != null) {
      say('Sales de ${hiding!.name} con cuidado.', const Color(0xFF999999));
      audio.play(Sfx.cock, volume: 0.4);
      hiding = null;
      hidingSeen = false;
      return;
    }
    final t = tileOf(p.pos);
    if (floor.at(t.x, t.y) == Tile.stairUp) {
      if (fi + 1 == roofFloor && !boxDone) {
        audio.play(Sfx.cock, volume: 0.5);
        say('La puerta de la azotea está cerrada. No cede.', const Color(0xFF999999));
        return;
      }
      _goFloor(fi + 1);
      return;
    }
    if (floor.at(t.x, t.y) == Tile.stairDown) {
      _goFloor(fi - 1);
      return;
    }
    if (floor.at(t.x, t.y) == Tile.elevator) {
      if (floor.elevatorWorks) {
        elevatorOpen = !elevatorOpen;
        audio.play(Sfx.typeKey);
      } else {
        audio.play(Sfx.cock, volume: 0.4);
        say('El botón no responde. El ascensor no para en esta planta.', const Color(0xFF999999));
      }
      return;
    }
    if (_atHelipad) {
      _win();
      return;
    }
    if (!boxDone && floor.box != null && (floor.box! - p.pos).distance < 1.2) {
      final boss = floor.boss;
      if (!p.spellLearned) {
        _boxSealed();
      } else if (boss == null) {
        _spawnBoss();
      } else if (boss.alive) {
        say('Con el carnicero encima, imposible.', const Color(0xFFFF7070));
      } else {
        _sealInvention();
      }
      return;
    }
    final pc = _nearPc();
    if (pc != null) {
      _usePc(pc);
      return;
    }
    final room = _nearSwitch();
    if (room != null) {
      _toggleLight(room);
      return;
    }
    final c = _nearCrate();
    final h = _nearHide();
    if (h != null && (c == null || (h.pos - p.pos).distance < (c.pos - p.pos).distance)) {
      _hide(h);
      return;
    }
    if (c != null && searching == null) {
      searching = c;
      searchT = 0;
      audio.play(Sfx.search, volume: 0.6);
    }
  }

  HideSpot? _nearHide() {
    for (final h in floor.hideSpots) {
      if ((h.pos - p.pos).distance < 1.0) return h;
    }
    return null;
  }

  void _hide(HideSpot h) {
    searching = null;
    hiding = h;
    p.pos = h.pos;
    p.vel = Offset.zero;
    audio.play(Sfx.cock, volume: 0.4);
    hidingSeen = floor.enemies.any((e) => e.alive && e.unseenT < 0.3);
    if (hidingSeen) {
      say('¡Te han visto entrar en ${h.name}!', const Color(0xFFFF6060));
    } else {
      say('Te escondes en ${h.name}. Contén la respiración...', const Color(0xFFAAAAAA));
    }
  }

  void _dragOut() {
    final h = hiding!;
    hiding = null;
    hidingSeen = false;
    p.pos = h.pos + const Offset(0, 0.6);
    if (collides(floor, p.pos.dx, p.pos.dy, 0.28)) p.pos = h.pos;
    audio.play(Sfx.stinger);
    shake = 12;
    redFlash = 0.6;
    HapticFeedback.heavyImpact();
    big('¡TE HAN ENCONTRADO!', const Color(0xFFFF2020), 1.4);
  }

  Room? _nearSwitch() {
    for (final r in floor.rooms) {
      if (r.switchPos != null && (r.switchPos! - p.pos).distance < 1.0) return r;
    }
    return null;
  }

  Room? roomAt(Offset pt) {
    for (final r in floor.rooms) {
      if (r.rect.contains(pt)) return r;
    }
    return null;
  }

  void _toggleLight(Room r) {
    r.lit = !r.lit;
    audio.play(Sfx.cock, volume: 0.5);
    if (r.lit) {
      audio.play(Sfx.buzz, volume: 0.8);
      say('Los fluorescentes parpadean y se encienden. El zumbido resuena por toda la planta...',
          const Color(0xFFFFE6B0));
      say('Si lo oyes tú, lo oyen ellos.', const Color(0xFFFF9090));
      _alertTo(r.rect.center);
      switchAlertT = 12;
    } else {
      say('Apagas la luz. Vuelve la penumbra.', const Color(0xFF999999));
    }
  }

  /// Los sicarios de la planta acuden a investigar.
  void _alertTo(Offset where) {
    for (final e in floor.enemies) {
      if (!e.alive || e.state == EState.flee) continue;
      if (e.state == EState.patrol) e.state = EState.chase;
      e.lastKnown = where;
      e.unseenT = 0;
      e.repath = 0;
    }
  }

  void _updateSwitchAlert(double dt) {
    final lit = floor.rooms.where((r) => r.lit).toList();
    if (lit.isEmpty) return;
    switchAlertT -= dt;
    if (switchAlertT <= 0) {
      switchAlertT = 12;
      _alertTo(lit[rng.nextInt(lit.length)].rect.center);
    }
  }

  /// Planta baja: el primer sicario aparece al fondo de la linterna, de frente.
  void _scriptedEncounter() {
    if (firstSicarioSeen || fi != groundFloor || time < firstEncounterT || transition > 0 || hiding != null) return;
    final dir = Offset(cos(p.angle), sin(p.angle));
    final d = castRay(floor, p.pos.dx, p.pos.dy, dir.dx, dir.dy, 11);
    if (d < 6) {
      firstEncounterT = time + 0.5; // volver a intentarlo cuando haya un pasillo largo delante
      return;
    }
    final pos = p.pos + dir * (d - 1.2);
    if (collides(floor, pos.dx, pos.dy, 0.3)) {
      firstEncounterT = time + 0.5;
      return;
    }
    final e = Enemy(pos, (p.pos - pos).direction, rng.nextDouble() * 10);
    e.light = lightPolygon(floor, e.pos, 8, 24, startAngle: e.angle - 0.4, sweep: 0.8);
    floor.enemies.add(e);
  }

  bool enemyVisible(Enemy e) {
    final d = (e.pos - p.pos).distance;
    return d < 14 && lineOfSight(floor, p.pos, e.pos);
  }

  Pc? _nearPc() {
    for (final pc in floor.pcs) {
      if ((pc.pos - p.pos).distance < 1.0) return pc;
    }
    return null;
  }

  Crate? _nearCrate() {
    Crate? best;
    var bd = 1.0;
    for (final c in floor.crates) {
      if (c.searched) continue;
      // Los coches se registran desde el lado: llegan un poco más lejos.
      final d = (c.pos - p.pos).distance - (c.kind == carCrate ? 0.35 : 0);
      if (d < bd) {
        bd = d;
        best = c;
      }
    }
    return best;
  }

  void _computeHint() {
    hint = null;
    actionKind = 'none';
    void set(String kind, String text) {
      actionKind = kind;
      hint = text;
    }

    final t = tileOf(p.pos);
    if (hiding != null) {
      set('unhide', 'Salir');
    } else if (floor.at(t.x, t.y) == Tile.stairUp) {
      if (fi + 1 == roofFloor && !boxDone) {
        set('locked', 'Puerta de la azotea cerrada');
      } else {
        set('up', 'Subir a ${floorNames[fi + 1].toLowerCase()}');
      }
    } else if (floor.at(t.x, t.y) == Tile.stairDown) {
      set('down', 'Bajar a ${floorNames[fi - 1].toLowerCase()}');
    } else if (floor.at(t.x, t.y) == Tile.elevator) {
      if (floor.elevatorWorks) {
        set('elevator', elevatorOpen ? 'Elige planta' : 'Llamar al ascensor');
      } else {
        set('locked', 'Ascensor averiado');
      }
    } else if (_atHelipad) {
      set('heli', 'Subir al helicóptero');
    } else if (!boxDone && floor.box != null && (floor.box! - p.pos).distance < 1.2) {
      final boss = floor.boss;
      if (!p.spellLearned) {
        set('boxSealed', 'Caja sellada');
      } else if (boss != null && boss.alive) {
        set('boxSealed', 'El carnicero la protege');
      } else {
        set('box', 'Recitar el conjuro y meter el invento');
      }
    } else if (_nearPc() != null) {
      set('pc', 'Usar ordenador');
    } else if (_nearSwitch() != null) {
      final lit = _nearSwitch()!.lit;
      set(lit ? 'lightOff' : 'lightOn', lit ? 'Apagar la luz' : 'Encender la luz');
    } else {
      final c = _nearCrate();
      final h = _nearHide();
      if (h != null && (c == null || (h.pos - p.pos).distance < (c.pos - p.pos).distance)) {
        set('hide', 'Esconderse');
      } else if (c != null) {
        set('search', searching == c ? 'Registrando...' : 'Registrar ${crateNames[c.kind]}');
      }
    }
  }

  void _finishSearch(Crate c) {
    searching = null;
    c.searched = true;
    searchResult = SearchResult(c.kind, c.rat ? null : c.loot, c.rat);
    if (c.rat) {
      audio.play(Sfx.rat);
      shake = max(shake, 6);
      redFlash = max(redFlash, 0.25);
      HapticFeedback.mediumImpact();
      big('¡!', const Color(0xFFFFFFFF), 0.6);
      say('¡Una rata salta de dentro y desaparece en la oscuridad!', const Color(0xFFFF9090));
      return;
    }
    if (c.loot == null) {
      say(['Vacío.', 'Solo polvo y cristales.', 'Alguien llegó antes.', 'Nada. Huele a podrido.'][rng.nextInt(4)],
          const Color(0xFF888888));
      return;
    }
    _gain(c.loot!);
    c.loot = null;
  }

  void _usePc(Pc pc) {
    final first = !pc.used;
    pc.used = true;
    if (!pc.working) {
      glitch = 0.7;
      audio.play(Sfx.glitch, volume: 0.8);
      const lines = [
        'La pantalla escupe letras: «TE ESTÁN VIENDO».',
        'Pantalla rota. Algo se mueve en el reflejo... detrás de ti.',
        'ERROR ERROR ERROR... «¿por qué has vuelto?»',
        'Sin corriente. El teclado está húmedo. Es sangre.',
        'Un rostro pixelado te sonríe y se apaga.',
        'Solo estática. Y una respiración en los altavoces.',
      ];
      say(lines[rng.nextInt(lines.length)], const Color(0xFF7FFFB0));
      if (first && scareCd <= 0 && rng.nextDouble() < 0.25) {
        faceScare = 0.45;
        audio.play(Sfx.scream, volume: 0.8);
        HapticFeedback.heavyImpact();
        scareCd = 25;
      }
      return;
    }
    audio.play(Sfx.typeKey);
    final boxAt = 'La caja está en la ${floorNames[world.boxFloor].toLowerCase()}.';
    if (p.spellLearned) {
      say('La IA susurra: «Ya conoces las palabras. $boxAt»', const Color(0xFF7FFFB0));
    } else if (!p.manuscriptRevealed) {
      // Ni una pista sobre la hoja ni sobre las gafas.
      if (p.hasManuscript) {
        say('La IA: «¿Una hoja en blanco? Aquí no hay nada que leer.»', const Color(0xFF7FFFB0));
      } else {
        say('Una IA despierta: «Tráeme el manuscrito. Yo puedo leerlo.»', const Color(0xFF7FFFB0));
      }
      say('«$boxAt»', const Color(0xFF7FFFB0));
    } else {
      p.spellLearned = true;
      audio.play(Sfx.magic);
      big('CONJURO APRENDIDO', const Color(0xFFD9B3FF), 2.6);
      say('La IA traduce los símbolos: son las palabras que abren la Caja de Otros Mundos.', const Color(0xFFD9B3FF));
      say('Y algo más: «Sanación de Otros Mundos». Botón violeta. $boxAt', const Color(0xFFD9B3FF));
    }
  }

  void _goFloor(int target) {
    if (target < 0 || target >= floorCount) return;
    pendingFloor = target;
    pendingArrival = target > fi ? world.floors[target].down : world.floors[target].up;
    transition = 0.9;
    searching = null;
    elevatorOpen = false;
    audio.play(Sfx.stairs);
  }

  /// El ascensor no llega a la azotea ni para donde está averiado.
  bool canRide(int target) =>
      target != fi && target != roofFloor && world.floors[target].elevatorWorks && floor.elevatorWorks;

  void rideElevator(int target) {
    if (!elevatorOpen || transition > 0 || !canRide(target)) return;
    elevatorOpen = false;
    pendingFloor = target;
    pendingArrival = world.floors[target].elevator;
    transition = 1.4;
    searching = null;
    audio.play(Sfx.typeKey);
    audio.play(Sfx.stairs, volume: 0.5);
  }

  void _switchFloor() {
    final target = pendingFloor!;
    pendingFloor = null;
    fi = target;
    p.pos = tileCenter(pendingArrival!);
    _clearArrival();
    big(floorNames[fi].toUpperCase(), const Color(0xFFCCCCCC), 1.8);
    if (floor.firstVisit) {
      floor.firstVisit = false;
      const intros = [
        'Gasolina, humedad y coches abandonados. Algo gotea en la oscuridad.',
        '',
        'Huele a humedad. Algo gotea en algún sitio.',
        'Los maniquíes están por todas partes aquí arriba.',
        'Silencio absoluto. Demasiado silencio.',
        'El viento silba entre los cristales rotos.',
        'La última planta. Huele a quemado.',
        'Aire libre, lluvia... y no estás solo.',
      ];
      if (intros[fi].isNotEmpty) say(intros[fi], const Color(0xFFAAAAAA));
    }
    _checkpoint();
    if (fi == roofFloor && !roofWave) _roofAmbush();
  }

  Point<int>? _farTile(double minD, {bool hidden = true}) {
    for (var i = 0; i < 80; i++) {
      final t = floor.freeTiles[rng.nextInt(floor.freeTiles.length)];
      final c = tileCenter(t);
      if ((c - p.pos).distance < minD) continue;
      if (hidden && lineOfSight(floor, c, p.pos)) continue;
      return t;
    }
    return null;
  }

  // --- Luz -------------------------------------------------------------------

  void _updateLight() {
    final f = floor;
    void visit(int x, int y) {
      if (x >= 0 && y >= 0 && x < mapW && y < mapH) f.explored.add(y * mapW + x);
    }

    coneLen = coneLenBase * flashPower;
    ambientR = ambientBase * (flashOutT > 0 ? 0.55 : 1);
    ambientPoly = lightPolygon(f, p.pos, ambientR, 72, visit: visit);
    conePoly = coneLen > 0.3
        ? lightPolygon(f, p.pos, coneLen, 70, startAngle: p.angle - coneHalf, sweep: coneHalf * 2, visit: visit)
        : const [];
    // Con la luz de emergencia, lo que tienes alrededor también queda en el mapa.
    lightPolygon(f, p.pos, 6, 48, visit: visit);
  }

  void _updateFlashlight(double dt) {
    if (flashOutT > 0) {
      flashOutT -= dt;
      flashPower = rng.nextDouble() < 0.06 ? 0.6 : 0.0;
      if (flashOutT <= 0) flashPower = 1;
      return;
    }
    nextFlashFail -= dt;
    final r = rng.nextDouble();
    flashPower = r < 0.015 ? 0.35 : (r < 0.04 ? 0.8 : 1.0);
    if (nextFlashFail <= 0) {
      flashOutT = 1.2 + rng.nextDouble() * 1.8;
      nextFlashFail = 35 + rng.nextDouble() * 50;
      audio.play(Sfx.buzz, volume: 0.5);
      say(['La linterna falla...', 'No. No. No, ahora no...', 'Oscuridad total.'][rng.nextInt(3)],
          const Color(0xFF999999));
    }
  }

  bool isLit(Offset pt) {
    if (roomAt(pt)?.lit ?? false) return true;
    final d = (pt - p.pos).distance;
    final los = d < 0.5 || lineOfSight(floor, p.pos, pt);
    if (!los) return _lampLit(pt);
    if (d < ambientR * 0.95) return true;
    if (d < coneLen && angleDiff((pt - p.pos).direction, p.angle) < coneHalf) return true;
    if ((muzzleFlash > 0 || magicFlash > 0) && d < 7) return true;
    return _lampLit(pt);
  }

  bool _lampLit(Offset pt) {
    for (final l in floor.lamps) {
      if (!l.alive || l.level < 0.3) continue;
      if ((l.pos - pt).distance < l.radius * 0.8 && lineOfSight(floor, l.pos, pt)) return true;
    }
    return false;
  }

  // --- Sicarios --------------------------------------------------------------

  void _makeFlee(Enemy e, double secs) {
    if (!e.alive || e.fearless) return;
    e.state = EState.flee;
    e.fleeT = secs;
    e.fear = 0;
    Point<int>? best;
    var bd = -1.0;
    for (var i = 0; i < 8; i++) {
      final t = floor.freeTiles[rng.nextInt(floor.freeTiles.length)];
      final d = (tileCenter(t) - p.pos).distance;
      if (d > bd) {
        bd = d;
        best = t;
      }
    }
    e.goal = best;
    e.path = best == null ? [] : findPath(floor, tileOf(e.pos), best);
  }

  void _follow(Enemy e, double speed, double dt, {Offset? finalTarget}) {
    e.moving = false;
    Offset? target;
    if (e.path.isNotEmpty) {
      target = tileCenter(e.path.first);
      if ((target - e.pos).distance < 0.1) {
        e.path.removeAt(0);
        target = e.path.isNotEmpty ? tileCenter(e.path.first) : finalTarget;
      }
    } else {
      target = finalTarget;
    }
    if (target == null) return;
    final delta = target - e.pos;
    final d = delta.distance;
    if (d < 0.05) return;
    final step = min(d, speed * dt);
    e.pos = moveWithCollision(floor, e.pos, delta / d * step, 0.26);
    e.angle = lerpAngle(e.angle, delta.direction, dt * 10);
    e.moving = true;
  }

  void _updateEnemies(double dt) {
    final f = floor;
    Enemy? loudest;
    var loudestD = 1e9;

    for (final e in f.enemies) {
      if (!e.alive) {
        e.deadT += dt;
        continue;
      }
      e.shootCd -= dt;
      e.repath -= dt;
      final toP = p.pos - e.pos;
      final dist = toP.distance;
      final los = dist < 14 && lineOfSight(f, e.pos, p.pos);
      final canSee = hiding != null
          ? hidingSeen && dist < 2.5
          : los && (angleDiff(e.angle, toP.direction) < 1.2 || dist < 3.5 || muzzleFlash > 0 || p.running && dist < 6);
      if (hiding != null && hidingSeen && (e.pos - hiding!.pos).distance < 1.5) _dragOut();
      if (canSee) {
        e.lastKnown = p.pos;
        e.unseenT = 0;
      } else {
        e.unseenT += dt;
      }

      // Primer avistamiento: el gran susto.
      if (!firstSicarioSeen && dist < 12 && enemyVisible(e)) {
        firstSicarioSeen = true;
        _firstSighting(e);
      }

      // Cobardes: si les apuntas con la pistola, se acobardan.
      if (e.state != EState.flee && los && p.hasPistol && p.ammo > 0 && dist < 8 &&
          angleDiff((e.pos - p.pos).direction, p.angle) < 0.3) {
        e.fear += dt;
        if (e.fear > 0.9 && rng.nextDouble() < 0.6) _makeFlee(e, 4);
      } else {
        e.fear = max(0, e.fear - dt * 0.5);
      }

      switch (e.state) {
        case EState.patrol:
          if (e.path.isEmpty) {
            final t = f.freeTiles[rng.nextInt(f.freeTiles.length)];
            e.path = findPath(f, tileOf(e.pos), t);
          }
          _follow(e, 1.5, dt);
          if (canSee) {
            e.state = EState.chase;
            e.shootCd = max(e.shootCd, 0.5);
            if (firstSicarioSeen && scareCd <= 0 && dist < 7 && enemyVisible(e)) {
              audio.play(Sfx.stinger, volume: 0.9);
              shake = max(shake, 10);
              redFlash = max(redFlash, 0.5);
              HapticFeedback.heavyImpact();
              big('¡TE HAN VISTO!', const Color(0xFFFF2020), 1.2);
              scareCd = 22;
            }
          }
        case EState.chase:
          if (canSee && hiding == null && dist < 9 && e.shootCd <= 0) {
            e.state = EState.aim;
            e.aimT = 0.75;
            audio.play(Sfx.cock, volume: max(0.2, 1 - dist / 10));
            break;
          }
          if (e.repath <= 0) {
            e.repath = 0.4;
            e.path = findPath(f, tileOf(e.pos), tileOf(e.lastKnown));
          }
          if (canSee && dist < 2.6) {
            e.angle = lerpAngle(e.angle, toP.direction, dt * 10);
            e.moving = false;
          } else {
            _follow(e, 3.3, dt, finalTarget: e.lastKnown);
          }
          if (e.unseenT > 6) {
            e.state = EState.patrol;
            e.path = [];
          }
        case EState.aim:
          e.moving = false;
          e.angle = lerpAngle(e.angle, toP.direction, dt * 12);
          if (!los || hiding != null) {
            e.state = EState.chase;
            break;
          }
          e.aimT -= dt;
          if (e.aimT <= 0) {
            _enemyShoot(e, dist);
            e.state = EState.chase;
            e.shootCd = 1.6 + rng.nextDouble();
          }
        case EState.flee:
          e.fleeT -= dt;
          if (e.path.isEmpty && e.goal != null) {
            e.path = findPath(f, tileOf(e.pos), e.goal!);
          }
          _follow(e, 3.8, dt);
          if (e.fleeT <= 0) {
            e.state = EState.patrol;
            e.path = [];
          }
        case EState.dead:
          break;
      }

      e.light = dist < 28
          ? lightPolygon(f, e.pos, 8, 24, startAngle: e.angle - 0.4, sweep: 0.8)
          : const [];

      if (e.moving && dist < 10 && dist < loudestD) {
        loudest = e;
        loudestD = dist;
      }
    }

    // Pasos y respiración: más fuertes cuanto más cerca.
    stepCd -= dt;
    breathCd -= dt;
    if (loudest != null && stepCd <= 0) {
      final fast = loudest.state == EState.chase || loudest.state == EState.flee;
      stepCd = fast ? 0.27 : 0.5;
      audio.play(Sfx.step, volume: (1 - loudestD / 10) * 0.9);
    }
    final nearest = f.enemies.where((e) => e.alive).fold<double>(1e9, (m, e) => min(m, (e.pos - p.pos).distance));
    if (nearest < 4.5 && breathCd <= 0) {
      breathCd = 2.2;
      audio.play(Sfx.breath, volume: (1 - nearest / 4.5) * 0.8 + 0.2);
    }

    // Refuerzos de la mafia.
    f.spawnTimer -= dt;
    if (f.spawnTimer <= 0) {
      f.spawnTimer = 50 + rng.nextDouble() * 40;
      if (f.enemies.where((e) => e.alive).length < f.enemyCap) {
        final t = _farTile(18);
        if (t != null) {
          f.enemies.add(Enemy(tileCenter(t), rng.nextDouble() * 2 * pi, rng.nextDouble() * 10));
          say(['Un portazo a lo lejos... llegan más.', 'Voces. Están entrando más.', 'Oyes un coche frenar fuera.'][
              rng.nextInt(3)], const Color(0xFFFF9090));
        }
      }
    }
  }

  void _firstSighting(Enemy e) {
    audio.play(Sfx.stinger);
    audio.play(Sfx.scream, volume: 0.5);
    HapticFeedback.heavyImpact();
    shake = 16;
    redFlash = 0.9;
    zoomPunch = 1;
    big('¡SICARIO!', const Color(0xFFFF2020), 2.0);
    say('Traje negro. Gafas oscuras. Te ha encontrado.', const Color(0xFFFF7070));
    say('Son rápidos y no fallan... pero son cobardes.', const Color(0xFFFFAAAA));
    e.state = EState.chase;
    e.lastKnown = p.pos;
    e.shootCd = 1.4; // da un respiro para reaccionar
    scareCd = 20;
  }

  void _enemyShoot(Enemy e, double dist) {
    audio.play(Sfx.enemyShot, volume: max(0.4, 1 - dist / 14));
    const speed = 24.0;
    var chance = 0.85 - (p.running ? 0.18 : 0) - (dist > 5 ? 0.1 : 0);
    if (flashOutT > 0) chance -= 0.2;
    // Apuntan con anticipación a donde vas a estar.
    var target = p.pos + p.vel * (dist / speed);
    if (rng.nextDouble() >= chance) {
      final off = (0.12 + rng.nextDouble() * 0.18) * (rng.nextBool() ? 1 : -1);
      final a = (target - e.pos).direction + off;
      target = e.pos + Offset(cos(a), sin(a)) * dist;
    }
    final dir = (target - e.pos) / max(0.01, (target - e.pos).distance);
    final gun = e.pos + dir * 0.45;
    bullets.add(Bullet(gun, dir, speed, false));
    flashes.add(Flash(gun, lightPolygon(floor, gun, 3.5, 36)));
    e.angle = dir.direction;
  }

  void _updateBullets(double dt) {
    for (final b in [...bullets]) {
      var remaining = b.speed * dt;
      var dead = false;
      while (remaining > 0 && !dead) {
        final step = min(0.2, remaining);
        remaining -= step;
        b.pos += b.dir * step;
        if (floor.solidPos(b.pos)) {
          for (var i = 0; i < 7; i++) {
            final a = b.dir.direction + pi + (rng.nextDouble() - 0.5) * 2;
            sparks.add(Spark(b.pos - b.dir * 0.1, Offset(cos(a), sin(a)) * (1.5 + rng.nextDouble() * 3), 0.3,
                const Color(0xFFFFD27F)));
          }
          dead = true;
        } else if (b.fromPlayer) {
          final boss = floor.boss;
          if (boss != null && boss.alive && (boss.pos - b.pos).distance < 0.55) {
            _hitBoss(1);
            dead = true;
            break;
          }
          for (final e in floor.enemies) {
            if (e.alive && (e.pos - b.pos).distance < 0.42) {
              _hitEnemy(e, 2);
              dead = true;
              break;
            }
          }
        } else if (hiding == null && (p.pos - b.pos).distance < 0.34) {
          _playerHit();
          dead = true;
        }
      }
      b.life -= dt;
      if (dead || b.life <= 0) bullets.remove(b);
    }
  }

  void _playerHit() {
    if (lost) return;
    // Quieto = blanco fácil para un tiro a la cabeza.
    final headChance = p.stillT > 0.5 ? 0.3 : 0.04;
    if (rng.nextDouble() < headChance) {
      headshot = true;
      p.hp = 0;
      _damage(0);
      _lose();
      return;
    }
    _damage(2);
    if (!p.darkWound && rng.nextDouble() < 0.18) {
      p.darkWound = true;
      big('HERIDA OSCURA', const Color(0xFFB98CFF), 2.2);
      say('¡Bala maldita! La herida se vuelve negra. Las medicinas no la curan.', const Color(0xFFB98CFF));
    } else {
      say(['¡Te han dado!', '¡Un balazo en el hombro!', '¡Arde!'][rng.nextInt(3)], const Color(0xFFFF6060));
    }
  }

  // --- Maniquíes ---------------------------------------------------------------

  void _updateMannequins(double dt) {
    for (final m in floor.mannequins) {
      if (m.fallen) continue;
      final d = (m.pos - p.pos).distance;
      final lit = isLit(m.pos);
      if (m.screamer && d < 1.7 && lit && scareCd <= 5) {
        m.fallen = true;
        faceScare = 0.7;
        audio.play(Sfx.scream);
        shake = 14;
        HapticFeedback.heavyImpact();
        scareCd = 20;
        say('...solo era un maniquí. ¿Verdad?', const Color(0xFFAAAAAA));
        continue;
      }
      // Se mueven cuando no los miras.
      if (!lit && d > 2.2 && d < 9) {
        m.moveT -= dt;
        if (m.moveT <= 0) {
          m.moveT = 2 + rng.nextDouble() * 4;
          if (rng.nextDouble() < 0.6) {
            final dir = (p.pos - m.pos) / d;
            final np = m.pos + dir * 0.6;
            if (!collides(floor, np.dx, np.dy, 0.25)) m.pos = np;
            m.angle = dir.direction;
          }
        }
      }
    }
  }

  // --- Lámparas y neones ----------------------------------------------------

  void _updateLamps(double dt) {
    for (final l in floor.lamps) {
      if (!l.alive) {
        l.level = 0;
        continue;
      }
      switch (l.mode) {
        case 1:
          l.timer -= dt;
          if (l.timer <= 0) {
            final on = l.level < 0.5;
            l.level = on ? (0.7 + rng.nextDouble() * 0.3) : (rng.nextDouble() < 0.5 ? 0 : 0.15);
            l.timer = on ? 0.3 + rng.nextDouble() * 2.5 : 0.04 + rng.nextDouble() * 0.5;
          }
        case 2:
          l.level = 0.85 + rng.nextDouble() * 0.15;
          if ((l.pos - p.pos).distance < 1.6) {
            l.alive = false;
            l.level = 0;
            audio.play(Sfx.buzz, volume: 0.9);
            shake = max(shake, 4);
            for (var i = 0; i < 18; i++) {
              final a = rng.nextDouble() * 2 * pi;
              sparks.add(Spark(l.pos, Offset(cos(a), sin(a)) * (1 + rng.nextDouble() * 3), 0.5 + rng.nextDouble() * 0.5,
                  const Color(0xFFFFD27F)));
            }
            say('La luz revienta sobre tu cabeza.', const Color(0xFFAAAAAA));
          }
        default:
          l.level = 0.9 + sin(time * 3 + l.pos.dx) * 0.05;
      }
    }
  }

  // --- Ambiente --------------------------------------------------------------

  void _updateAmbient(double dt) {
    scareCd = max(0, scareCd - dt);
    whisperT -= dt;
    if (whisperT <= 0) {
      whisperT = 20 + rng.nextDouble() * 25;
      audio.play(Sfx.whisper, volume: 0.55);
      const whispers = [
        '...te huelo...',
        'No estás solo.',
        'Pasos en el piso de arriba.',
        'Algo ha caído en la oscuridad.',
        '¿Has oído eso?',
        'Ellos saben que estás aquí.',
        'La caja te llama...',
        'Alguien respira detrás de la pared.',
        'Un carrito rueda solo por el pasillo.',
      ];
      say(whispers[rng.nextInt(whispers.length)], const Color(0xFF8C8CA8));
    }
  }

  /// Sin el conjuro la caja no se abre.
  void _boxSealed() {
    glitch = 0.3;
    audio.play(Sfx.glitch, volume: 0.5);
    say('La caja no se abre. En la tapa brillan signos que no entiendes.', const Color(0xFFB98CFF));
    say('Hacen falta unas palabras que no conoces.', const Color(0xFF8C6FBF));
  }

  /// El invento entra en la caja: ahora hay que salir vivo por la azotea.
  void _sealInvention() {
    boxDone = true;
    whiteFlash = 1.2;
    shake = 10;
    audio.play(Sfx.magic);
    audio.play(Sfx.win, volume: 0.6);
    HapticFeedback.heavyImpact();
    big('¡A LA AZOTEA!', const Color(0xFFFFE6B0), 3);
    say('Metes el invento en la caja. Se cierra sola y se apaga.', const Color(0xFFFFE6B0));
    say('Arriba revienta una puerta: la de la azotea. Es tu única salida.', const Color(0xFFFFE6B0));
    say('Sirenas fuera. Vienen todos a por ti.', const Color(0xFFFF9090));
    say('Punto de control guardado.', const Color(0xFF777777));
    for (final f in world.floors) {
      if (f.index == roofFloor) continue;
      f.enemyCap += 2;
      f.spawnTimer = min(f.spawnTimer, 6 + rng.nextDouble() * 10);
    }
    _checkpoint();
  }

  // --- El carnicero --------------------------------------------------------------

  void _spawnBoss() {
    final f = floor;
    Offset? best;
    var bd = -1.0;
    for (final t in f.freeTiles) {
      final c = tileCenter(t);
      final db = (c - f.box!).distance;
      if (db < 1 || db > 4.5 || !lineOfSight(f, c, f.box!)) continue;
      final dp = (c - p.pos).distance;
      if (dp > bd) {
        bd = dp;
        best = c;
      }
    }
    final at = best ?? f.box!;
    f.boss = Boss(at)..angle = (p.pos - at).direction;
    audio.play(Sfx.stinger);
    audio.play(Sfx.scream, volume: 0.5);
    HapticFeedback.heavyImpact();
    shake = 16;
    redFlash = 0.8;
    zoomPunch = 1;
    big('EL CARNICERO', const Color(0xFFFF2020), 2.4);
    say('Un tipo enorme sale de la sombra. Lleva un cuchillo de carnicero.', const Color(0xFFFF7070));
    say('Guarda la caja. Hará falta mucho plomo para tumbarlo.', const Color(0xFFFFAAAA));
  }

  void _hitBoss(double dmg) {
    final b = floor.boss!;
    b.hp = max(0, b.hp - dmg);
    b.stagger = 0.22;
    b.windup = 0;
    for (var i = 0; i < 10; i++) {
      final a = rng.nextDouble() * 2 * pi;
      sparks.add(Spark(b.pos, Offset(cos(a), sin(a)) * (1 + rng.nextDouble() * 2), 0.45, const Color(0xFF8A0000)));
    }
    if (b.alive) {
      if (rng.nextDouble() < 0.3) {
        say(['Ni se inmuta.', 'Gruñe y sigue.', 'Sangra, pero avanza.'][rng.nextInt(3)], const Color(0xFFDDAAAA));
      }
      return;
    }
    kills++;
    shake = 12;
    audio.play(Sfx.scream, volume: 0.4);
    big('¡ABATIDO!', const Color(0xFFFFE6B0), 2);
    // Llevaba munición encima.
    floor.items.add(GroundItem(b.pos + const Offset(0.3, 0.2), ItemType.ammo));
    floor.items.add(GroundItem(b.pos + const Offset(-0.3, 0.25), ItemType.ammo));
    say('El carnicero se desploma junto a la caja. Ya nadie la guarda.', const Color(0xFFFFE6B0));
  }

  void _updateBoss(double dt) {
    final f = floor;
    if (!boxDone && f.box != null && f.boss == null && (f.box! - p.pos).distance < 6.5 &&
        lineOfSight(f, p.pos, f.box!)) {
      _spawnBoss();
    }
    final b = f.boss;
    if (b == null) return;
    if (!b.alive) {
      b.deadT += dt;
      return;
    }
    b.cooldown -= dt;
    b.repath -= dt;
    b.stagger = max(0, b.stagger - dt);
    b.moving = false;
    final toP = p.pos - b.pos;
    final d = toP.distance;
    if (hiding != null && d < 1.6) _dragOut();
    if (b.windup > 0) {
      b.windup -= dt;
      b.angle = lerpAngle(b.angle, toP.direction, dt * 6);
      if (b.windup <= 0) {
        b.cooldown = 1.0;
        audio.play(Sfx.swing);
        if (d < 1.35 && hiding == null) {
          _damage(3);
          for (var i = 0; i < 10; i++) {
            final a = rng.nextDouble() * 2 * pi;
            sparks.add(Spark(p.pos, Offset(cos(a), sin(a)) * (1 + rng.nextDouble() * 2), 0.4, const Color(0xFFAA0000)));
          }
          say(['¡El cuchillo te abre el brazo!', '¡Te apuñala!', '¡Un tajo en el costado!'][rng.nextInt(3)],
              const Color(0xFFFF6060));
        }
      }
      return;
    }
    if (b.stagger > 0) return;
    if (d < 1.15 && b.cooldown <= 0 && hiding == null) {
      b.windup = 0.45;
      audio.play(Sfx.cock, volume: 0.5);
      return;
    }
    if (b.repath <= 0) {
      b.repath = 0.35;
      b.path = findPath(f, tileOf(b.pos), tileOf(hiding?.pos ?? p.pos));
    }
    Offset? target;
    if (b.path.isNotEmpty) {
      target = tileCenter(b.path.first);
      if ((target - b.pos).distance < 0.12) {
        b.path.removeAt(0);
        target = b.path.isNotEmpty ? tileCenter(b.path.first) : p.pos;
      }
    } else if (d > 0.9) {
      target = p.pos;
    }
    if (target == null) return;
    final delta = target - b.pos;
    final dd = delta.distance;
    if (dd < 0.05) return;
    b.pos = moveWithCollision(f, b.pos, delta / dd * min(dd, 3.0 * dt), 0.3);
    b.angle = lerpAngle(b.angle, delta.direction, dt * 8);
    b.moving = true;
  }

  // --- Azotea ---------------------------------------------------------------------

  bool get _atHelipad => fi == roofFloor && heliLanded && (floor.helipad! - p.pos).distance < 1.8;

  void _spawnRoofThugs(int n) {
    for (var i = 0; i < n; i++) {
      final t = _farTile(10, hidden: false) ?? floor.freeTiles[rng.nextInt(floor.freeTiles.length)];
      final e = Enemy(tileCenter(t), rng.nextDouble() * 2 * pi, rng.nextDouble() * 10)
        ..fearless = true
        ..state = EState.chase
        ..lastKnown = p.pos
        ..unseenT = 0
        ..shootCd = 1.5 + rng.nextDouble() * 2;
      floor.enemies.add(e);
    }
  }

  void _roofAmbush() {
    roofWave = true;
    _spawnRoofThugs(6);
    audio.play(Sfx.stinger);
    shake = 12;
    redFlash = 0.6;
    big('¡EMBOSCADA!', const Color(0xFFFF2020), 2.2);
    say('Te estaban esperando arriba. Esta vez no huirán.', const Color(0xFFFF7070));
  }

  void _updateRoof(double dt) {
    if (fi != roofFloor || !roofWave) return;
    final alive = floor.enemies.where((e) => e.alive).length;
    if (!roofWave2 && alive <= 2) {
      roofWave2 = true;
      _spawnRoofThugs(3);
      say('¡Suben más por la escalera de incendios!', const Color(0xFFFF9090));
    }
    if (roofWave2 && alive == 0 && heliT < 0) {
      heliT = 0;
      audio.play(Sfx.thunder, volume: 0.6);
      big('¡UN HELICÓPTERO!', const Color(0xFFFFE6B0), 2.6);
      say('Un helicóptero baja hacia el helipuerto. ¡Corre!', const Color(0xFFFFE6B0));
    }
    if (heliT >= 0) {
      final before = heliT;
      heliT += dt;
      if (before < heliLandTime && heliLanded) say('Ha aterrizado. ¡Sube!', const Color(0xFFFFE6B0));
    }
  }

  void _win() {
    won = true;
    endT = 0;
    whiteFlash = 1.6;
    audio.stopAmbient();
    audio.play(Sfx.win);
    HapticFeedback.heavyImpact();
    say('Saltas al helicóptero. El centro comercial se queda abajo, en la oscuridad.', const Color(0xFFFFE6B0));
  }

  void _lose() {
    if (lost) return;
    lost = true;
    endT = 0;
    redFlash = 1;
    shake = 18;
    audio.play(Sfx.hurt);
    audio.play(Sfx.scream, volume: 0.6);
    audio.setAmbientVolume(0.3);
    HapticFeedback.heavyImpact();
  }
}
