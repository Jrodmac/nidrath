import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../game/audio.dart';
import 'game_screen.dart';

/// Línea de narración con su instante de aparición (segundos del vídeo).
class _Line {
  final double at;
  final String text;
  final bool voice; // grito de los perseguidores, fuera de cuadro
  const _Line(this.at, this.text, {this.voice = false});
}

// Sincronizadas con los planos de assets/video/intro.mp4 (20 s).
const _lines = [
  _Line(0.3, 'Llevo tres noches sin dormir. Desde que terminé el invento, me siguen.'),
  _Line(4.0, '¡NO DEJÉIS QUE ESCAPE!', voice: true),
  _Line(5.6, 'La mafia lo quiere. Y no les importa cómo conseguirlo.'),
  _Line(8.3, 'Las afueras. Aquí la ciudad se rinde.'),
  _Line(12.0, 'El viejo centro comercial. Dicen que dentro hay una caja... que lleva a otros mundos.'),
  _Line(15.8, 'Si la encuentro, el invento desaparecerá para siempre.'),
];

/// Tras el vídeo: fundido a negro y texto final.
const double _fadeTime = 0.6;
const double _promptAt = 2.0;

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  /// Ya se ha visto (o saltado) en esta sesión.
  static bool seen = false;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  final _video = VideoPlayerController.asset('assets/video/intro.mp4');
  late final Ticker _ticker;
  double t = 0; // posición del vídeo
  double clock = 0;
  double? endedAt;
  int _typed = 0;
  int _lineIdx = -1;
  bool leaving = false;

  double get sinceEnd => endedAt == null ? 0 : clock - endedAt!;
  bool get ended => endedAt != null;

  @override
  void initState() {
    super.initState();
    // El vídeo trae su propio sonido: se corta la lluvia de la portada.
    GameAudio.instance.stopAmbient();
    _video.initialize().then((_) {
      if (!mounted) return;
      _video.play();
      setState(() {});
    }).catchError((_) {
      // Sin vídeo no hay intro: directos al juego.
      if (mounted) _start();
    });
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _video.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    clock = d.inMicroseconds / 1e6;
    final v = _video.value;
    if (v.isInitialized) t = v.position.inMicroseconds / 1e6;
    if (!ended && v.isInitialized && v.duration > Duration.zero && (v.isCompleted || v.position >= v.duration)) {
      endedAt = clock;
      GameAudio.instance.play(Sfx.punch);
      HapticFeedback.heavyImpact();
    }

    var idx = -1;
    for (var i = 0; i < _lines.length; i++) {
      if (t >= _lines[i].at) idx = i;
    }
    if (idx != _lineIdx) {
      _lineIdx = idx;
      _typed = 0;
    }
    if (idx >= 0) {
      final line = _lines[idx];
      final target = ((t - line.at) * (line.voice ? 60 : 32)).floor().clamp(0, line.text.length);
      if (target > _typed) {
        if (!line.voice && target ~/ 2 != _typed ~/ 2) GameAudio.instance.play(Sfx.typeKey, volume: 0.25);
        _typed = target;
      }
    }
    setState(() {});
  }

  void _start() {
    if (leaving) return;
    leaving = true;
    IntroScreen.seen = true;
    _video.pause();
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 1200),
      pageBuilder: (_, _, _) => const GameScreen(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final line = _lineIdx >= 0 ? _lines[_lineIdx] : null;
    final v = _video.value;
    final canEnter = ended && sinceEnd > _promptAt;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canEnter ? _start : null,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent && (canEnter || e.logicalKey == LogicalKeyboardKey.escape)) _start();
            return KeyEventResult.handled;
          },
          child: Stack(children: [
            if (v.isInitialized)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(width: v.size.width, height: v.size.height, child: VideoPlayer(_video)),
                ),
              ),
            // Fundido a negro al terminar.
            if (ended)
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: (sinceEnd / _fadeTime).clamp(0.0, 1.0))),
              ),
            if (line != null && !line.voice && !ended)
              Positioned(
                left: 40,
                right: 40,
                bottom: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  color: const Color(0xAA000000),
                  child: Text(
                    line.text.substring(0, _typed),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.4, color: Color(0xFFE0E0E0), letterSpacing: 0.3),
                  ),
                ),
              ),
            if (line != null && line.voice && t - line.at < 1.6)
              Positioned(
                left: 0,
                right: 0,
                bottom: 90,
                child: Center(
                  child: Text(
                    '«${line.text.substring(0, _typed)}»',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                      fontSize: 24,
                      color: const Color(0xFFFF3030).withValues(alpha: (1.6 - (t - line.at)).clamp(0.0, 1.0)),
                      shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                ),
              ),
            if (ended && sinceEnd > _fadeTime)
              Positioned.fill(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      'Detrás de ti, la puerta se cierra.\nDelante, solo oscuridad.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.5,
                        color: const Color(0xFFBBBBBB).withValues(alpha: ((sinceEnd - _fadeTime) / 1.2).clamp(0.0, 1.0)),
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (canEnter && sin(clock * 3) > -0.4)
                      const Text(
                        'TOCA PARA ENTRAR',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                          letterSpacing: 4,
                          color: Color(0xFFB00010),
                          shadows: [Shadow(color: Color(0xFFFF0020), blurRadius: 12)],
                        ),
                      ),
                  ]),
                ),
              ),
            if (!ended)
              Positioned(
                right: 16,
                top: 12,
                child: GestureDetector(
                  onTap: _start,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('SALTAR ›',
                        style: TextStyle(fontSize: 13, color: Color(0xFFAAAAAA), shadows: [Shadow(blurRadius: 4)])),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
