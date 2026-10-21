import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/audio.dart';
import '../game/game.dart';
import '../game/painter.dart';
import '../game/sprites.dart';
import '../game/world.dart';
import 'ending_screen.dart';
import 'splash_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Game game;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  final GameInput input = GameInput();
  final FocusNode _focus = FocusNode();
  bool paused = false;
  bool _runHeld = false;
  bool showMap = true;
  bool _endingShown = false;

  // Joystick
  int? _joyPointer;
  Offset? _joyOrigin;
  Offset _joyKnob = Offset.zero;
  static const double _joyRadius = 55;

  @override
  void initState() {
    super.initState();
    game = Game();
    GameAudio.instance.startDrone();
    _ticker = createTicker(_tick)..start();
    WidgetsBinding.instance.addObserver(this);
  }

  // Si sales de la app o te llaman, la partida se pausa sola.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !game.won && !game.lost) _pause();
  }

  /// Pausa: todo se congela tal cual y se continúa en el mismo sitio.
  void _pause() {
    if (paused) return;
    setState(() {
      paused = true;
      _releaseAll();
      GameAudio.instance.setAmbientVolume(0.05);
    });
  }

  void _resume() => setState(() {
        paused = false;
        _releaseAll();
        GameAudio.instance.setAmbientVolume(0.3);
      });

  void _releaseAll() {
    _joyPointer = null;
    _joyOrigin = null;
    _joyKnob = Offset.zero;
    _runHeld = false;
    input.attack = input.action = input.magic = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (paused) return;
    input.move = _keyboardMove() ?? (_joyOrigin == null ? Offset.zero : _joyKnob / _joyRadius);
    input.run = HardwareKeyboard.instance.isShiftPressed || _runHeld;
    game.update(dt, input);
    // Tras subir al helicóptero: el vídeo final.
    if (game.won && game.endT > 4 && !_endingShown) {
      _endingShown = true;
      _ticker.stop();
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 1200),
        pageBuilder: (_, _, _) => EndingScreen(kills: game.kills, time: game.time),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ));
      return;
    }
    setState(() {});
  }

  Offset? _keyboardMove() {
    final k = HardwareKeyboard.instance.logicalKeysPressed;
    var x = 0.0, y = 0.0;
    if (k.contains(LogicalKeyboardKey.keyA) || k.contains(LogicalKeyboardKey.arrowLeft)) x -= 1;
    if (k.contains(LogicalKeyboardKey.keyD) || k.contains(LogicalKeyboardKey.arrowRight)) x += 1;
    if (k.contains(LogicalKeyboardKey.keyW) || k.contains(LogicalKeyboardKey.arrowUp)) y -= 1;
    if (k.contains(LogicalKeyboardKey.keyS) || k.contains(LogicalKeyboardKey.arrowDown)) y += 1;
    if (x == 0 && y == 0) return null;
    final v = Offset(x, y);
    return v / v.distance * 0.85;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space) {
      input.attack = true;
    } else if (k == LogicalKeyboardKey.keyE || k == LogicalKeyboardKey.enter) {
      input.action = true;
    } else if (k == LogicalKeyboardKey.keyQ) {
      input.magic = true;
    } else if (k == LogicalKeyboardKey.keyM) {
      setState(() => showMap = !showMap);
    } else if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP) {
      paused ? _resume() : _pause();
    } else if (k == LogicalKeyboardKey.digit1) {
      input.use = ItemType.water;
    } else if (k == LogicalKeyboardKey.digit2) {
      input.use = ItemType.food;
    } else if (k == LogicalKeyboardKey.digit3) {
      input.use = _bestMedicine();
    } else if (k == LogicalKeyboardKey.digit4) {
      input.use = ItemType.pills;
    } else if (k == LogicalKeyboardKey.digit5) {
      input.use = ItemType.glasses;
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  ItemType? _bestMedicine() {
    for (final t in [ItemType.medkit, ItemType.bandage, ItemType.painkiller]) {
      if ((game.p.inv[t] ?? 0) > 0) return t;
    }
    return null;
  }

  void _restart() {
    setState(() {
      game = Game();
      paused = false;
      _runHeld = false;
      GameAudio.instance.startDrone();
    });
  }

  /// Vuelve a la pantalla de inicio (no a la intro).
  void _exitToTitle() {
    _ticker.stop();
    GameAudio.instance.stopAmbient();
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, _, _) => const SplashScreen(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(builder: (context, c) {
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: GamePainter(game))),
              if (!game.won && !game.lost) ..._controls(c),
              _topHud(),
              if (showMap && !game.won && !game.lost) _minimap(),
              if (game.elevatorOpen && !game.won && !game.lost) _elevatorPanel(),
              if (paused) _pauseMenu(),
              if (game.lost && game.endT > 1.2) _endOverlay(false),
            ],
          );
        }),
      ),
    );
  }

  // --- Controles -------------------------------------------------------------

  List<Widget> _controls(BoxConstraints c) {
    final p = game.p;
    return [
      // Zona del joystick: mitad izquierda.
      Positioned(
        left: 0,
        top: 70,
        bottom: 0,
        width: c.maxWidth * 0.45,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (_joyPointer != null) return;
            _joyPointer = e.pointer;
            _joyOrigin = e.localPosition;
            _joyKnob = Offset.zero;
          },
          onPointerMove: (e) {
            if (e.pointer != _joyPointer) return;
            var d = e.localPosition - _joyOrigin!;
            if (d.distance > _joyRadius) d = d / d.distance * _joyRadius;
            _joyKnob = d;
          },
          onPointerUp: (e) => _releaseJoy(e.pointer),
          onPointerCancel: (e) => _releaseJoy(e.pointer),
          child: CustomPaint(painter: _JoyPainter(_joyOrigin, _joyKnob, _joyRadius)),
        ),
      ),
      // Botonera de la derecha: ataque (o correr) grande en la esquina,
      // acción a su izquierda, correr y magia encima.
      Positioned(
        right: 18,
        bottom: 18,
        child: game.armed
            ? _RoundButton(
                size: 88,
                color: const Color(0xFF8A1C1C),
                onDown: () => input.attack = true,
                badge: p.hasPistol ? '${p.ammo}' : null,
                child: _Icon(p.hasPistol && p.ammo > 0 ? 'pistol' : 'pipe', 40),
              )
            : _runButton(88),
      ),
      Positioned(
        right: 120,
        bottom: 22,
        child: Opacity(
          opacity: game.hint != null ? 1 : 0.45,
          child: _RoundButton(
            size: 70,
            color: game.hint != null ? const Color(0xFF7A6A1A) : const Color(0xFF2A2A2A),
            onDown: () => input.action = true,
            child: Icon(_actionIcon(game.actionKind), color: Colors.white, size: 32),
          ),
        ),
      ),
      if (game.hint != null)
        Positioned(
          right: 120,
          bottom: 96,
          width: 160,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xDD000000),
                border: Border.all(color: const Color(0xFF7A6A1A)),
              ),
              child: Text(game.hint!, textAlign: TextAlign.center, style: _hudText(12, const Color(0xFFE8D468))),
            ),
          ),
        ),
      if (game.armed) Positioned(right: 30, bottom: 122, child: _runButton(60)),
      if (p.spellLearned)
        Positioned(
          right: game.armed ? 104 : 30,
          bottom: game.armed ? 160 : 122,
          child: Opacity(
            opacity: p.magicCd > 0 ? 0.4 : 1,
            child: _RoundButton(
              size: 58,
              color: const Color(0xFF5A2A8A),
              onDown: () => input.magic = true,
              child: const _Icon('magic', 30),
            ),
          ),
        ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 8,
        child: Center(child: _inventory()),
      ),
    ];
  }

  Widget _runButton(double size) => _RoundButton(
        size: size,
        color: _runHeld ? const Color(0xFF2A6A3A) : const Color(0xFF1E3A26),
        onDown: () => _runHeld = true,
        onUp: () => _runHeld = false,
        child: Icon(Icons.directions_run, color: Colors.white, size: size * 0.48),
      );

  IconData _actionIcon(String kind) => switch (kind) {
        'up' => Icons.north,
        'down' => Icons.south,
        'box' => Icons.all_inclusive,
        'boxSealed' => Icons.lock,
        'pc' => Icons.computer,
        'elevator' => Icons.elevator,
        'locked' => Icons.lock,
        'heli' => Icons.flight_takeoff,
        'lightOn' => Icons.lightbulb,
        'lightOff' => Icons.lightbulb_outline,
        'search' => Icons.search,
        'hide' => Icons.sensor_door,
        'unhide' => Icons.exit_to_app,
        _ => Icons.pan_tool,
      };

  void _releaseJoy(int pointer) {
    if (pointer != _joyPointer) return;
    _joyPointer = null;
    _joyOrigin = null;
    _joyKnob = Offset.zero;
  }

  Widget _inventory() {
    final p = game.p;
    final chips = <Widget>[];
    for (final t in [
      ItemType.water,
      ItemType.food,
      ItemType.medkit,
      ItemType.bandage,
      ItemType.painkiller,
      ItemType.pills,
    ]) {
      final n = p.inv[t] ?? 0;
      if (n <= 0) continue;
      chips.add(GestureDetector(
        onTapDown: (_) => input.use = t,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xCC111111),
            border: Border.all(color: const Color(0xFF555555), width: 2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Icon(itemInfo[t]!.icon, 26),
            const SizedBox(width: 3),
            Text('$n', style: _hudText(13)),
          ]),
        ),
      ));
    }
    if (p.hasManuscript) {
      // Hasta verla con las gafas es solo una hoja en blanco.
      final revealed = p.manuscriptRevealed;
      chips.add(Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: revealed ? const Color(0xCC1A0F22) : const Color(0xCC111111),
          border: Border.all(color: revealed ? const Color(0xFF6A3A8A) : const Color(0xFF555555), width: 2),
        ),
        child: _Icon(revealed ? 'manuscript' : 'sheet', 26),
      ));
    }
    if (p.hasGlasses) {
      chips.add(GestureDetector(
        onTapDown: (_) => input.use = ItemType.glasses,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: p.wearingGlasses ? const Color(0xCC3A2A08) : const Color(0xCC111111),
            border: Border.all(color: p.wearingGlasses ? const Color(0xFFE0A030) : const Color(0xFF555555), width: 2),
          ),
          child: const _Icon('glasses', 26),
        ),
      ));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: chips);
  }

  // --- HUD -------------------------------------------------------------------

  Widget _topHud() {
    final p = game.p;
    return Positioned(
      left: 12,
      top: 10,
      right: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pips('SALUD', p.hp, const Color(0xFFD03030), p.darkWound ? const Color(0xFF8E44AD) : null),
              const SizedBox(height: 4),
              _pips('ENERGÍA', p.energy, const Color(0xFFE8C030), null),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [
                if (p.darkWound) _tag('HERIDA OSCURA', const Color(0xFF8E44AD)),
                if (p.energy <= 0) _tag('AGOTADO', const Color(0xFFB06020)),
                if (p.hasPipe) _tag('BARRA', const Color(0xFF555555)),
                if (p.wearingGlasses) _tag('GAFAS', const Color(0xFF8A6010)),
              ]),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                Text(floorNames[game.fi].toUpperCase(), style: _hudText(14, const Color(0xFF999999))),
                const SizedBox(height: 4),
                for (final m in game.messages)
                  Opacity(
                    opacity: (1 - max(0.0, m.t - 4.5) / 1.5).clamp(0.0, 1.0),
                    child: Text(
                      m.text,
                      textAlign: TextAlign.center,
                      style: _hudText(13, m.color),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _smallButton(Icons.map, () => setState(() => showMap = !showMap)),
                const SizedBox(width: 6),
                _smallButton(Icons.pause, _pause),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pips(String label, double value, Color color, Color? border) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 62, child: Text(label, style: _hudText(11, const Color(0xFFAAAAAA)))),
      for (var i = 0; i < maxPoints; i++)
        Container(
          width: 11,
          height: 13,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: Color.lerp(const Color(0xFF1A1A1A), color, (value - i).clamp(0.0, 1.0)),
            border: Border.all(color: border ?? Colors.black, width: 2),
          ),
        ),
    ]);
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        color: c,
        child: Text(t, style: _hudText(10)),
      );

  Widget _smallButton(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          color: const Color(0xAA111111),
          child: Icon(icon, color: const Color(0xFFAAAAAA), size: 20),
        ),
      );

  Widget _minimap() {
    return Positioned(
      right: 12,
      top: 54,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xAA000000),
            border: Border.all(color: const Color(0xFF333333), width: 2),
          ),
          child: CustomPaint(size: const Size(mapW * 2.6, mapH * 2.6), painter: _MiniMapPainter(game)),
        ),
      ),
    );
  }

  /// Botonera del ascensor: las plantas donde no para salen tachadas.
  Widget _elevatorPanel() {
    return Positioned(
      right: 200,
      bottom: 110,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xEE15171B),
          border: Border.all(color: const Color(0xFF40D0FF), width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ASCENSOR', style: _hudText(12, const Color(0xFF40D0FF))),
          const SizedBox(height: 6),
          for (var i = roofFloor - 1; i >= 0; i--)
            GestureDetector(
              onTap: () => game.rideElevator(i),
              child: Container(
                width: 150,
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: i == game.fi
                    ? const Color(0xFF2A4A5A)
                    : (game.canRide(i) ? const Color(0xFF22262C) : const Color(0xFF181818)),
                child: Text(
                  floorNames[i].toUpperCase(),
                  textAlign: TextAlign.center,
                  style: _hudText(11, game.canRide(i) || i == game.fi ? const Color(0xFFDDDDDD) : const Color(0xFF555555))
                      .copyWith(decoration: game.world.floors[i].elevatorWorks ? null : TextDecoration.lineThrough),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _pauseMenu() {
    return Positioned.fill(
      child: Container(
        color: const Color(0xDD000000),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('PAUSA', style: _hudText(34, const Color(0xFFCC2020))),
                const SizedBox(height: 4),
                Text('La partida está congelada. Sigues en el mismo sitio.', style: _hudText(12, const Color(0xFF888888))),
                const SizedBox(height: 14),
                Text(
                  'Joystick: moverse · al fondo o botón verde: correr\n'
                  'Botón rojo: atacar (solo con arma)\n'
                  'Botón de acción: registrar, esconderse, usar, escaleras\n'
                  'Toca los objetos de abajo para usarlos\n'
                  'Ascensor: botón de acción y elige planta\n\n'
                  'Sin armas no puedes atacar: corre y escóndete\n'
                  'en taquillas y probadores.\n'
                  'Si te quedas quieto mientras te apuntan, irán a la cabeza.',
                  style: _hudText(13, const Color(0xFFAAAAAA)),
                ),
              ]),
              const SizedBox(width: 40),
              Column(mainAxisSize: MainAxisSize.min, children: [
                _menuButton('CONTINUAR', _resume),
                _menuButton('NUEVA PARTIDA', _restart),
                _menuButton('SALIR', _exitToTitle),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _endOverlay(bool won) {
    final g = game;
    return Positioned.fill(
      child: Container(
        color: won ? const Color(0x55000000) : const Color(0xCC1A0000),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              won ? 'EL CENTRO COMERCIAL VUELVE A LA VIDA' : 'TE HAN ATRAPADO',
              textAlign: TextAlign.center,
              style: _hudText(30, won ? const Color(0xFFFFF2B0) : const Color(0xFFFF2020)),
            ),
            const SizedBox(height: 10),
            Text(
              won
                  ? 'El invento viaja a otra dimensión. Nadie podrá usarlo jamás.\n'
                      'Las luces se encienden. La música vuelve. Los sicarios se desvanecen como humo.'
                  : g.headshot
                      ? 'Te quedaste quieto. Un solo disparo, en la cabeza.\nEl invento cae en sus manos.'
                      : 'El invento cae en sus manos.',
              textAlign: TextAlign.center,
              style: _hudText(14, const Color(0xFFDDDDDD)),
            ),
            const SizedBox(height: 8),
            Text('Sicarios abatidos: ${g.kills} · Tiempo: ${(g.time ~/ 60)}:${(g.time % 60).floor().toString().padLeft(2, '0')}',
                style: _hudText(12, const Color(0xFF999999))),
            const SizedBox(height: 20),
            _menuButton('JUGAR DE NUEVO', _restart),
            _menuButton('SALIR', _exitToTitle),
          ]),
          ),
        ),
      ),
    );
  }

  Widget _menuButton(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 240,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: const Color(0xFF6A1A1A), width: 2),
            ),
            child: Text(label, textAlign: TextAlign.center, style: _hudText(16)),
          ),
        ),
      );
}

TextStyle _hudText(double size, [Color color = const Color(0xFFEEEEEE)]) => TextStyle(
      fontFamily: 'monospace',
      fontWeight: FontWeight.bold,
      fontSize: size,
      color: color,
      shadows: const [Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1))],
    );

class _Icon extends StatelessWidget {
  final String name;
  final double size;
  const _Icon(this.name, this.size);

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _IconPainter(Sprites.i.icons[name]!));
}

class _IconPainter extends CustomPainter {
  final Sprite sprite;
  _IconPainter(this.sprite);

  @override
  void paint(Canvas canvas, Size size) => sprite.draw(canvas, size.center(Offset.zero), size.width);

  @override
  bool shouldRepaint(covariant _IconPainter old) => old.sprite != sprite;
}

class _RoundButton extends StatelessWidget {
  final double size;
  final Color color;
  final VoidCallback onDown;
  final VoidCallback? onUp;
  final String? badge;
  final Widget child;
  const _RoundButton({
    required this.size,
    required this.color,
    required this.onDown,
    required this.child,
    this.onUp,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => onDown(),
        onPointerUp: (_) => onUp?.call(),
        onPointerCancel: (_) => onUp?.call(),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color.lerp(color, Colors.white, 0.15)!.withValues(alpha: 0.85), color.withValues(alpha: 0.75)],
                ),
                border: Border.all(color: const Color(0x66FFFFFF), width: 2),
                boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 8)],
              ),
              child: Center(child: child),
            ),
            if (badge != null)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE8C468)),
                  ),
                  child: Text(badge!, style: _hudText(12, const Color(0xFFE8C468))),
                ),
              ),
          ]),
        ),
      );
}

class _JoyPainter extends CustomPainter {
  final Offset? origin;
  final Offset knob;
  final double radius;
  _JoyPainter(this.origin, this.knob, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final o = origin ?? Offset(90, size.height - 90);
    final a = origin == null ? 0.15 : 0.35;
    canvas.drawCircle(o, radius, Paint()..color = Color.fromRGBO(255, 255, 255, a * 0.4));
    canvas.drawCircle(o, radius, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Color.fromRGBO(255, 255, 255, a));
    canvas.drawCircle(o + knob, radius * 0.42, Paint()..color = Color.fromRGBO(255, 255, 255, a + 0.1));
  }

  @override
  bool shouldRepaint(covariant _JoyPainter old) => true;
}

class _MiniMapPainter extends CustomPainter {
  final Game g;
  _MiniMapPainter(this.g);

  @override
  void paint(Canvas canvas, Size size) {
    final f = g.floor;
    final cw = size.width / mapW, ch = size.height / mapH;
    final wall = Paint()..color = const Color(0xFF555566);
    final floorP = Paint()..color = const Color(0xFF1E1E24);
    for (final i in f.explored) {
      final x = i % mapW, y = i ~/ mapW;
      final t = f.at(x, y);
      final r = Rect.fromLTWH(x * cw, y * ch, cw + 0.3, ch + 0.3);
      switch (t) {
        case Tile.wall:
          canvas.drawRect(r, wall);
        case Tile.stairUp:
          canvas.drawRect(r, Paint()..color = const Color(0xFF6FBF73));
        case Tile.stairDown:
          canvas.drawRect(r, Paint()..color = const Color(0xFFBF6F6F));
        case Tile.elevator:
          canvas.drawRect(r, Paint()..color = const Color(0xFF40D0FF));
        case Tile.car:
          canvas.drawRect(r, Paint()..color = const Color(0xFF3A3A44));
        default:
          canvas.drawRect(r, floorP);
      }
    }
    if (f.box != null && f.explored.contains(tileOf(f.box!).y * mapW + tileOf(f.box!).x)) {
      canvas.drawRect(Rect.fromCenter(center: Offset(f.box!.dx * cw, f.box!.dy * ch), width: cw * 1.6, height: ch * 1.6),
          Paint()..color = const Color(0xFFB04CFF));
    }
    final pad = f.helipad;
    if (pad != null) {
      canvas.drawCircle(Offset(pad.dx * cw, pad.dy * ch), cw * 2, Paint()..color = const Color(0xFFB89A30));
    }
    final blink = (g.time * 3).floor() % 2 == 0;
    canvas.drawRect(
        Rect.fromCenter(center: Offset(g.p.pos.dx * cw, g.p.pos.dy * ch), width: cw * 1.5, height: ch * 1.5),
        Paint()..color = blink ? const Color(0xFFFFFFFF) : const Color(0xFFE8C468));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
