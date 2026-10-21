import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import 'game_screen.dart';
import 'splash_screen.dart';

/// Final: la huida en helicóptero (vídeo) y el resumen de la partida.
/// Si todavía no hay vídeo en assets/video/final.mp4, se muestra solo el texto.
class EndingScreen extends StatefulWidget {
  final int kills;
  final double time;
  const EndingScreen({super.key, required this.kills, required this.time});

  @override
  State<EndingScreen> createState() => _EndingScreenState();
}

class _EndingScreenState extends State<EndingScreen> with SingleTickerProviderStateMixin {
  final _video = VideoPlayerController.asset('assets/video/final.mp4');
  late final Ticker _ticker;
  double clock = 0;
  double? textAt; // cuándo empieza el texto final

  @override
  void initState() {
    super.initState();
    _video.initialize().then((_) {
      if (!mounted) return;
      _video.play();
      setState(() {});
    }).catchError((_) {
      if (mounted) textAt = clock;
    });
    _ticker = createTicker((d) {
      clock = d.inMicroseconds / 1e6;
      final v = _video.value;
      if (textAt == null && v.isInitialized && v.duration > Duration.zero && (v.isCompleted || v.position >= v.duration)) {
        textAt = clock;
      }
      setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _video.dispose();
    super.dispose();
  }

  void _skip() {
    if (textAt != null) return;
    _video.pause();
    textAt = clock;
  }

  void _go(Widget page) {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _video.value;
    final k = textAt == null ? 0.0 : ((clock - textAt!) / 1.2).clamp(0.0, 1.0);
    final t = widget.time;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: Stack(children: [
          if (v.isInitialized)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(width: v.size.width, height: v.size.height, child: VideoPlayer(_video)),
              ),
            ),
          if (textAt != null) Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.75 * k))),
          if (textAt != null)
            Positioned.fill(
              child: Opacity(
                opacity: k,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('HAS ESCAPADO', style: _text(34, const Color(0xFFFFF2B0))),
                        const SizedBox(height: 10),
                        Text(
                          'El invento está en otro mundo. Nadie podrá usarlo jamás.\n'
                          'Abajo, el centro comercial se apaga para siempre.',
                          textAlign: TextAlign.center,
                          style: _text(14, const Color(0xFFDDDDDD)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sicarios abatidos: ${widget.kills} · Tiempo: ${t ~/ 60}:${(t % 60).floor().toString().padLeft(2, '0')}',
                          style: _text(12, const Color(0xFF999999)),
                        ),
                        const SizedBox(height: 20),
                        _button('JUGAR DE NUEVO', () => _go(const GameScreen())),
                        _button('SALIR', () => _go(const SplashScreen())),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          if (textAt == null && v.isInitialized && sin(clock * 2) > -0.6)
            Positioned(
              right: 16,
              top: 12,
              child: Text('TOCA PARA SALTAR', style: _text(11, const Color(0x99FFFFFF))),
            ),
        ]),
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap) => Padding(
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
            child: Text(label, textAlign: TextAlign.center, style: _text(16, const Color(0xFFEEEEEE))),
          ),
        ),
      );
}

TextStyle _text(double size, Color color) => TextStyle(
      fontFamily: 'monospace',
      fontWeight: FontWeight.bold,
      fontSize: size,
      color: color,
      shadows: const [Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1))],
    );
