import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/audio.dart';
import '../game/save.dart';
import 'game_screen.dart';
import 'intro_screen.dart';

/// Pantalla de inicio: lluvia, relámpagos, título que parpadea y un rostro
/// subliminal que aparece durante un instante.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double t = 0;
  double lightning = 0;
  double nextLightning = 0.6;
  bool faceShown = false;
  double face = 0;
  bool audioReady = false;
  bool leaving = false;
  final rng = Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      final nt = d.inMicroseconds / 1e6;
      final dt = (nt - t).clamp(0.0, 0.05);
      t = nt;
      lightning = max(0, lightning - dt * 2.5);
      face = max(0, face - dt);
      if (t > nextLightning) {
        lightning = 1;
        nextLightning = t + 4 + rng.nextDouble() * 5;
        GameAudio.instance.play(Sfx.thunder, volume: 0.9);
      }
      if (!faceShown && t > 3.4) {
        faceShown = true;
        face = 0.12;
        GameAudio.instance.play(Sfx.stinger, volume: 0.6);
        HapticFeedback.heavyImpact();
      }
      setState(() {});
    })
      ..start();
    SaveStore.load().then((_) {
      if (mounted) setState(() {});
    });
    GameAudio.instance.init().then((_) {
      if (!mounted) return;
      audioReady = true;
      GameAudio.instance.startRain(volume: 0.5);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// La primera vez se ve la intro; después se entra directamente a jugar.
  /// Con partida guardada, tocar la pantalla continúa; «NUEVA PARTIDA» empieza de cero.
  void _go({bool intro = false, bool fresh = false}) {
    if (leaving || t < 1.5) return;
    leaving = true;
    GameAudio.instance.play(Sfx.glitch, volume: 0.6);
    final resume = SaveStore.hasSave && !fresh && !intro;
    final showIntro = !resume && (intro || !IntroScreen.seen);
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 900),
      pageBuilder: (_, _, _) => showIntro ? const IntroScreen() : GameScreen(resume: resume),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _go,
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent) _go();
            return KeyEventResult.handled;
          },
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _SplashPainter(t, lightning, face, rng))),
            if (SaveStore.hasSave && t > 2.6)
              Positioned(
                left: 20,
                bottom: 16,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                    'TOCA PARA CONTINUAR',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFFBBBBBB), letterSpacing: 2),
                  ),
                  GestureDetector(
                    onTap: () => _go(fresh: true),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'NUEVA PARTIDA ›',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: Color(0xFF888888), letterSpacing: 2),
                      ),
                    ),
                  ),
                ]),
              ),
            if (IntroScreen.seen && t > 2.6)
              Positioned(
                right: 20,
                bottom: 16,
                child: GestureDetector(
                  onTap: () => _go(intro: true),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'VER INTRO ›',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: Color(0xFF888888), letterSpacing: 2),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  final double t, lightning, face;
  final Random rng;
  _SplashPainter(this.t, this.lightning, this.face, this.rng);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    canvas.drawRect(full, Paint()..color = Color.lerp(const Color(0xFF050308), const Color(0xFF8890A8), lightning * 0.5)!);

    // Silueta del centro comercial al fondo, iluminada solo por el relámpago.
    final px = size.height / 90;
    final base = size.height * 0.78;
    final sil = Paint()..color = Color.lerp(const Color(0xFF0A080E), const Color(0xFF2A2838), lightning)!;
    canvas.drawRect(Rect.fromLTWH(size.width * 0.18, base - 26 * px, size.width * 0.64, 26 * px), sil);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.38, base - 36 * px, size.width * 0.24, 12 * px), sil);
    final win = Paint();
    final wr = Random(4);
    for (var i = 0; i < 28; i++) {
      final x = size.width * 0.2 + wr.nextDouble() * size.width * 0.6;
      final y = base - 24 * px + wr.nextDouble() * 20 * px;
      final on = wr.nextDouble() < 0.15 && sin(t * (3 + i) + i) > 0.6;
      win.color = on ? const Color(0xFF6A5A30) : const Color(0xFF050407);
      canvas.drawRect(Rect.fromLTWH(x, y, 3 * px, 2 * px), win);
    }
    canvas.drawRect(Rect.fromLTWH(0, base, size.width, size.height - base), Paint()..color = const Color(0xFF040305));

    // Lluvia.
    final rain = Paint()
      ..color = const Color(0x557A8AA0)
      ..strokeWidth = 1.2;
    final rr = Random(9);
    for (var i = 0; i < 160; i++) {
      final x0 = rr.nextDouble() * size.width;
      final sp = 600 + rr.nextDouble() * 400;
      final y = (rr.nextDouble() * size.height + t * sp) % size.height;
      final x = (x0 - t * 60) % size.width;
      canvas.drawLine(Offset(x, y), Offset(x - 3, y + 14), rain);
    }

    // Título con aberración cromática y letras que fallan.
    const title = 'NIDRATH';
    final fs = size.shortestSide * 0.2;
    final appear = (t / 1.2).clamp(0.0, 1.0);
    final tw = fs * 0.62 * title.length;
    final x0 = (size.width - tw) / 2;
    final y0 = size.height * 0.2;
    for (var i = 0; i < title.length; i++) {
      final flick = sin(t * (7 + i * 3.1) + i * 2) > -0.85 || rng.nextDouble() < 0.5;
      if (!flick || appear < (i + 1) / title.length * 0.9) continue;
      final jit = rng.nextDouble() < 0.06 ? Offset((rng.nextDouble() - 0.5) * 14, 0) : Offset.zero;
      final pos = Offset(x0 + i * fs * 0.62, y0) + jit;
      for (final (off, col) in [
        (const Offset(-3, 0), const Color(0x8800E5FF)),
        (const Offset(3, 0), const Color(0x88FF0030)),
        (Offset.zero, const Color(0xFFB00010)),
      ]) {
        final tp = TextPainter(
          text: TextSpan(
            text: title[i],
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w900,
              fontSize: fs,
              color: col,
              shadows: col == const Color(0xFFB00010)
                  ? const [Shadow(color: Color(0xFFFF0020), blurRadius: 18)]
                  : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, pos + off);
      }
      // Goteo de sangre bajo algunas letras.
      if (i % 3 == 1) {
        final drip = ((t * 0.3 + i) % 2.5) / 2.5;
        canvas.drawRect(
            Rect.fromLTWH(pos.dx + fs * 0.3, y0 + fs * 1.05, 4, fs * 0.5 * drip), Paint()..color = const Color(0xFF7A0008));
      }
    }

    void label(String s, double y, double fsz, Color c) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: fsz, color: c, letterSpacing: 6),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
    }

    if (t > 1.6) {
      label('LA CAJA DE OTROS MUNDOS', y0 + fs * 1.25, size.shortestSide * 0.045,
          Color.fromRGBO(185, 140, 255, ((t - 1.6) / 1.2).clamp(0.0, 1.0)));
    }
    if (t > 2.6 && sin(t * 3) > -0.3) {
      label('toca para entrar', size.height * 0.86, size.shortestSide * 0.04, const Color(0xFF888888));
    }

    // Ruido.
    final g = Paint();
    for (var i = 0; i < 200; i++) {
      g.color = Color.fromRGBO(255, 255, 255, 0.02 + rng.nextDouble() * 0.05);
      canvas.drawRect(Rect.fromLTWH(rng.nextDouble() * size.width, rng.nextDouble() * size.height, 2, 2), g);
    }

    // Viñeta.
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x00000000), Color(0xEE000000)],
          stops: const [0.4, 1],
        ).createShader(full),
    );

    // Rostro subliminal.
    if (face > 0) {
      canvas.drawRect(full, Paint()..color = Colors.black);
      final c = size.center(Offset.zero);
      final r = size.height * 0.42;
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 1.3, height: r * 1.9), Paint()..color = const Color(0xFFD8D0C0));
      final eye = Paint()..color = Colors.black;
      canvas.drawOval(Rect.fromCenter(center: c + Offset(-r * 0.25, -r * 0.2), width: r * 0.3, height: r * 0.38), eye);
      canvas.drawOval(Rect.fromCenter(center: c + Offset(r * 0.25, -r * 0.2), width: r * 0.3, height: r * 0.38), eye);
      canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * 0.45), width: r * 0.35, height: r * 0.6), eye);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
