import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Efectos de sonido. Todos se sintetizan en memoria: no hay ficheros de audio.
enum Sfx {
  gunshot,
  enemyShot,
  scream,
  stinger,
  heartbeat,
  whisper,
  step,
  breath,
  pickup,
  search,
  buzz,
  cock,
  hurt,
  swing,
  punch,
  magic,
  win,
  stairs,
  rat,
  glitch,
  thunder,
  typeKey,
  carCrash,
}

const int _sr = 22050;

class GameAudio {
  GameAudio._();
  static final GameAudio instance = GameAudio._();

  final Map<Sfx, Uint8List> _bank = {};
  Uint8List? _drone;
  Uint8List? _rain;
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  AudioPlayer? _ambient;
  bool _ready = false;
  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      final rng = Random(7);
      _bank[Sfx.gunshot] = _wav(_gunshot(rng, 75, 12));
      _bank[Sfx.enemyShot] = _wav(_gunshot(rng, 95, 16, distant: true));
      _bank[Sfx.scream] = _wav(_scream(rng));
      _bank[Sfx.stinger] = _wav(_stinger(rng));
      _bank[Sfx.heartbeat] = _wav(_heartbeat());
      _bank[Sfx.whisper] = _wav(_whisper(rng));
      _bank[Sfx.step] = _wav(_step(rng));
      _bank[Sfx.breath] = _wav(_breath(rng));
      _bank[Sfx.pickup] = _wav(_pickup());
      _bank[Sfx.search] = _wav(_search(rng));
      _bank[Sfx.buzz] = _wav(_buzz(rng));
      _bank[Sfx.cock] = _wav(_cock(rng));
      _bank[Sfx.hurt] = _wav(_hurt(rng));
      _bank[Sfx.swing] = _wav(_swing(rng));
      _bank[Sfx.punch] = _wav(_punch(rng));
      _bank[Sfx.magic] = _wav(_magic());
      _bank[Sfx.win] = _wav(_winSound());
      _bank[Sfx.stairs] = _wav(_stairs(rng));
      _bank[Sfx.rat] = _wav(_rat(rng));
      _bank[Sfx.glitch] = _wav(_glitch(rng));
      _bank[Sfx.thunder] = _wav(_thunder(rng));
      _bank[Sfx.typeKey] = _wav(_typeKey(rng));
      _bank[Sfx.carCrash] = _wav(_carCrash(rng));
      _drone = _wav(_droneLoop(rng));
      _rain = _wav(_rainLoop(rng));
      for (var i = 0; i < 8; i++) {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
      _ambient = AudioPlayer();
      await _ambient!.setReleaseMode(ReleaseMode.loop);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  void play(Sfx s, {double volume = 1}) {
    if (!_ready) return;
    final bytes = _bank[s];
    if (bytes == null) return;
    final p = _pool[_next];
    _next = (_next + 1) % _pool.length;
    p
        .stop()
        .then((_) => p.play(BytesSource(bytes, mimeType: 'audio/wav'),
            volume: volume.clamp(0.0, 1.0)))
        .catchError((_) {});
  }

  /// Ambiente en bucle: zumbido grave del centro comercial.
  void startDrone({double volume = 0.7}) => _loop(_drone, volume);

  /// Ambiente en bucle: lluvia de la ciudad (intro).
  void startRain({double volume = 0.6}) => _loop(_rain, volume);

  void _loop(Uint8List? bytes, double volume) {
    if (!_ready || bytes == null) return;
    final a = _ambient!;
    a
        .stop()
        .then((_) => a.play(BytesSource(bytes, mimeType: 'audio/wav'), volume: volume))
        .catchError((_) {});
  }

  void setAmbientVolume(double v) {
    if (!_ready) return;
    _ambient!.setVolume(v.clamp(0.0, 1.0)).catchError((_) {});
  }

  void stopAmbient() {
    if (!_ready) return;
    _ambient!.stop().catchError((_) {});
  }
}

// ---------------------------------------------------------------------------
// Síntesis

Float64List _buf(double secs) => Float64List((secs * _sr).round());

double _noise(Random r) => r.nextDouble() * 2 - 1;

void _normalize(Float64List s, [double peak = 0.9]) {
  var m = 0.0;
  for (final v in s) {
    if (v.abs() > m) m = v.abs();
  }
  if (m == 0) return;
  final k = peak / m;
  for (var i = 0; i < s.length; i++) {
    s[i] *= k;
  }
}

Uint8List _wav(Float64List s) {
  final n = s.length;
  final b = ByteData(44 + n * 2);
  void str(int o, String t) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  const l = Endian.little;
  str(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, l);
  str(8, 'WAVE');
  str(12, 'fmt ');
  b.setUint32(16, 16, l);
  b.setUint16(20, 1, l);
  b.setUint16(22, 1, l);
  b.setUint32(24, _sr, l);
  b.setUint32(28, _sr * 2, l);
  b.setUint16(32, 2, l);
  b.setUint16(34, 16, l);
  str(36, 'data');
  b.setUint32(40, n * 2, l);
  for (var i = 0; i < n; i++) {
    b.setInt16(44 + i * 2, (s[i].clamp(-1.0, 1.0) * 32767).round(), l);
  }
  return b.buffer.asUint8List();
}

Float64List _gunshot(Random r, double boomHz, double decay, {bool distant = false}) {
  final s = _buf(0.6);
  var lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    final a = distant ? 0.12 : 0.5;
    lp += (_noise(r) - lp) * (a + 0.5 * exp(-t * 30));
    s[i] = lp * exp(-t * decay) + sin(2 * pi * boomHz * t * (1 - t)) * exp(-t * 9) * 0.9;
    if (i < 60) s[i] += _noise(r);
  }
  _normalize(s, distant ? 0.75 : 0.95);
  return s;
}

Float64List _scream(Random r) {
  final s = _buf(1.4);
  var ph1 = 0.0, ph2 = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    final f = 900 - 420 * t + 60 * sin(2 * pi * 7.5 * t);
    ph1 += f / _sr;
    ph2 += f * 1.07 / _sr;
    final saw = (ph1 % 1) * 2 - 1;
    final saw2 = (ph2 % 1) * 2 - 1;
    final env = min(1.0, t / 0.02) * (t > 1.0 ? max(0.0, 1 - (t - 1.0) / 0.4) : 1.0);
    final x = (saw + saw2 * 0.7 + _noise(r) * 0.5) * env;
    s[i] = _tanh(x * 3);
  }
  _normalize(s, 0.95);
  return s;
}

Float64List _stinger(Random r) {
  final s = _buf(2.0);
  const fs = [523.0, 554.0, 740.0, 784.0, 1108.0, 1175.0, 1480.0];
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    var v = 0.0;
    for (final f in fs) {
      v += sin(2 * pi * f * t + sin(2 * pi * 5 * t) * 0.6);
    }
    final trem = 0.6 + 0.4 * sin(2 * pi * 13 * t);
    final env = min(1.0, t / 0.01) * exp(-t * 1.6);
    s[i] = v * trem * env * 0.25 +
        sin(2 * pi * 42 * t) * exp(-t * 2.5) * 1.2 +
        _noise(r) * exp(-t * 20) * 0.8;
    s[i] = _tanh(s[i] * 1.5);
  }
  _normalize(s, 0.95);
  return s;
}

Float64List _heartbeat() {
  final s = _buf(0.7);
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    var v = 0.0;
    for (final (t0, amp) in [(0.0, 1.0), (0.22, 0.7)]) {
      final dt = t - t0;
      if (dt >= 0) v += sin(2 * pi * (60 - 25 * dt) * dt) * exp(-dt * 16) * amp;
    }
    s[i] = v;
  }
  _normalize(s, 0.95);
  return s;
}

Float64List _whisper(Random r) {
  final s = _buf(2.4);
  var lp = 0.0, lp2 = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    final n = _noise(r);
    lp += (n - lp) * 0.35;
    lp2 += (lp - lp2) * 0.05;
    final band = lp - lp2;
    final syl = pow(sin(pi * 3.1 * t).abs(), 2) * (0.6 + 0.4 * sin(2 * pi * 0.7 * t));
    final env = sin(pi * t / 2.4);
    s[i] = band * syl * env;
  }
  _normalize(s, 0.6);
  return s;
}

Float64List _step(Random r) {
  final s = _buf(0.16);
  var lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    lp += (_noise(r) - lp) * 0.2;
    s[i] = lp * exp(-t * 45) + sin(2 * pi * 85 * t) * exp(-t * 35) * 0.8;
  }
  _normalize(s, 0.9);
  return s;
}

Float64List _breath(Random r) {
  final s = _buf(1.6);
  var lp = 0.0, lp2 = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    lp += (_noise(r) - lp) * 0.25;
    lp2 += (lp - lp2) * 0.04;
    final inhale = t < 0.6 ? sin(pi * t / 0.6) : 0.0;
    final exhale = t > 0.75 ? sin(pi * (t - 0.75) / 0.85) * 1.3 : 0.0;
    s[i] = (lp - lp2) * (inhale * 0.7 + exhale);
  }
  _normalize(s, 0.7);
  return s;
}

Float64List _pickup() {
  final s = _buf(0.25);
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    final f = t < 0.09 ? 520.0 : 780.0;
    s[i] = sin(2 * pi * f * t) * exp(-(t % 0.09) * 18) * 0.6;
  }
  return s;
}

Float64List _search(Random r) {
  final s = _buf(1.0);
  var lp = 0.0;
  var g = 0.0;
  for (var i = 0; i < s.length; i++) {
    lp += (_noise(r) - lp) * 0.3;
    if (r.nextDouble() < 0.0015) g = 1;
    g *= 0.9993;
    s[i] = lp * (0.15 + g);
  }
  _normalize(s, 0.5);
  return s;
}

Float64List _buzz(Random r) {
  final s = _buf(0.9);
  var crack = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    final sq = sin(2 * pi * 120 * t) > 0 ? 1.0 : -1.0;
    if (r.nextDouble() < 0.002) crack = 1;
    crack *= 0.995;
    final on = r.nextDouble() < 0.97 ? 1.0 : 0.0;
    s[i] = sq * 0.25 * on * (1 - t / 0.9) + _noise(r) * crack;
  }
  _normalize(s, 0.6);
  return s;
}

Float64List _cock(Random r) {
  final s = _buf(0.22);
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    var v = 0.0;
    for (final t0 in [0.0, 0.09]) {
      final dt = t - t0;
      if (dt >= 0) v += _noise(r) * exp(-dt * 120) + sin(2 * pi * 2400 * dt) * exp(-dt * 80) * 0.5;
    }
    s[i] = v;
  }
  _normalize(s, 0.7);
  return s;
}

Float64List _hurt(Random r) {
  final s = _buf(0.45);
  var lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    lp += (_noise(r) - lp) * 0.1;
    s[i] = sin(2 * pi * (110 - 80 * t) * t) * exp(-t * 8) + lp * exp(-t * 10) * 2;
  }
  _normalize(s, 0.9);
  return s;
}

Float64List _swing(Random r) {
  final s = _buf(0.25);
  var lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    lp += (_noise(r) - lp) * (0.05 + 0.4 * sin(pi * t / 0.25));
    s[i] = lp * sin(pi * t / 0.25);
  }
  _normalize(s, 0.5);
  return s;
}

Float64List _punch(Random r) {
  final s = _buf(0.2);
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    s[i] = sin(2 * pi * 90 * t) * exp(-t * 25) + _noise(r) * exp(-t * 60) * 0.6;
  }
  _normalize(s, 0.9);
  return s;
}

Float64List _magic() {
  final s = _buf(2.4);
  const notes = [392.0, 523.0, 659.0, 784.0, 1046.0, 1318.0];
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    var v = 0.0;
    for (var k = 0; k < notes.length; k++) {
      final t0 = k * 0.12;
      for (var echo = 0; echo < 3; echo++) {
        final dt = t - t0 - echo * 0.28;
        if (dt >= 0) v += sin(2 * pi * notes[k] * dt) * exp(-dt * 3) * pow(0.5, echo);
      }
    }
    s[i] = v;
  }
  _normalize(s, 0.7);
  return s;
}

Float64List _winSound() {
  final s = _buf(5.0);
  const chord = [261.6, 329.6, 392.0, 523.3, 659.3];
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    var v = 0.0;
    for (final f in chord) {
      v += sin(2 * pi * f * t) + 0.3 * sin(4 * pi * f * t);
    }
    final env = min(1.0, t / 1.5) * (t > 3.5 ? (5 - t) / 1.5 : 1.0);
    s[i] = v * env;
  }
  _normalize(s, 0.7);
  return s;
}

Float64List _stairs(Random r) {
  final s = _buf(0.9);
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    var v = 0.0;
    for (var k = 0; k < 4; k++) {
      final dt = t - k * 0.2;
      if (dt >= 0) v += sin(2 * pi * 95 * dt) * exp(-dt * 30) + _noise(r) * exp(-dt * 60) * 0.3;
    }
    s[i] = v;
  }
  _normalize(s, 0.7);
  return s;
}

Float64List _rat(Random r) {
  final s = _buf(0.6);
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    final chirp = (t * 7) % 1;
    final f = 2800 + 1600 * chirp;
    ph += f / _sr;
    s[i] = sin(2 * pi * ph) * (chirp < 0.5 ? sin(pi * chirp * 2) : 0) + _noise(r) * 0.2 * exp(-t * 5);
  }
  _normalize(s, 0.6);
  return s;
}

Float64List _glitch(Random r) {
  final s = _buf(0.7);
  var f = 300.0;
  var ph = 0.0;
  for (var i = 0; i < s.length; i++) {
    if (i % 900 == 0) f = 80 + r.nextDouble() * 1800;
    ph += f / _sr;
    final sq = (ph % 1) < 0.5 ? 1.0 : -1.0;
    s[i] = (r.nextDouble() < 0.1 ? _noise(r) : sq) * 0.5;
  }
  return s;
}

Float64List _thunder(Random r) {
  final s = _buf(3.5);
  var lp = 0.0, lp2 = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    lp += (_noise(r) - lp) * 0.06;
    lp2 += (lp - lp2) * 0.08;
    final env = (t < 0.05 ? t / 0.05 : exp(-(t - 0.05) * 1.2)) *
        (0.6 + 0.4 * sin(2 * pi * 2.3 * t) * sin(2 * pi * 0.9 * t));
    s[i] = lp2 * env + _noise(r) * exp(-t * 25) * 0.3;
  }
  _normalize(s, 0.95);
  return s;
}

Float64List _typeKey(Random r) {
  final s = _buf(0.05);
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    s[i] = _noise(r) * exp(-t * 200) + sin(2 * pi * 1800 * t) * exp(-t * 150) * 0.3;
  }
  _normalize(s, 0.35);
  return s;
}

Float64List _carCrash(Random r) {
  final s = _buf(2.2);
  var lp = 0.0;
  for (var i = 0; i < s.length; i++) {
    final t = i / _sr;
    // Chirrido de frenos y golpe metálico.
    final screech = t < 0.8 ? sin(2 * pi * (1900 + 300 * sin(2 * pi * 9 * t)) * t) * 0.4 : 0.0;
    final dt = t - 0.8;
    lp += (_noise(r) - lp) * 0.4;
    final crash = dt >= 0
        ? (lp * exp(-dt * 3) + sin(2 * pi * 55 * dt) * exp(-dt * 6) +
                sin(2 * pi * 1320 * dt) * exp(-dt * 4) * 0.3 * (r.nextDouble() < 0.5 ? 1 : 0))
        : 0.0;
    s[i] = screech + crash;
  }
  _normalize(s, 0.95);
  return s;
}

Float64List _droneLoop(Random r) {
  const secs = 8.0, fade = 1.0;
  final total = _buf(secs + fade);
  var lp = 0.0, lp2 = 0.0;
  for (var i = 0; i < total.length; i++) {
    final t = i / _sr;
    lp += (_noise(r) - lp) * 0.02;
    lp2 += (lp - lp2) * 0.02;
    final wind = lp2 * (0.6 + 0.4 * sin(2 * pi * t / 4)) * 6;
    total[i] = sin(2 * pi * 41.25 * t) * 0.35 +
        sin(2 * pi * 55.0 * t) * 0.25 * (0.6 + 0.4 * sin(2 * pi * t / 8)) +
        sin(2 * pi * 58.25 * t) * 0.2 +
        sin(2 * pi * 233.0 * t) * 0.03 * (0.5 + 0.5 * sin(2 * pi * t / 2)) +
        wind;
  }
  final n = (secs * _sr).round();
  final f = (fade * _sr).round();
  final s = Float64List(n);
  for (var i = 0; i < n; i++) {
    s[i] = total[i];
  }
  for (var i = 0; i < f; i++) {
    final k = i / f;
    s[i] = s[i] * k + total[n + i] * (1 - k);
  }
  _normalize(s, 0.8);
  return s;
}

Float64List _rainLoop(Random r) {
  const secs = 6.0, fade = 0.5;
  final total = _buf(secs + fade);
  var lp = 0.0, hp = 0.0;
  for (var i = 0; i < total.length; i++) {
    final n = _noise(r);
    lp += (n - lp) * 0.5;
    hp += (lp - hp) * 0.1;
    final drop = r.nextDouble() < 0.002 ? _noise(r) * 2 : 0.0;
    total[i] = (lp - hp) * 0.6 + drop;
  }
  final n = (secs * _sr).round();
  final f = (fade * _sr).round();
  final s = Float64List(n);
  for (var i = 0; i < n; i++) {
    s[i] = total[i];
  }
  for (var i = 0; i < f; i++) {
    final k = i / f;
    s[i] = s[i] * k + total[n + i] * (1 - k);
  }
  _normalize(s, 0.5);
  return s;
}

double _tanh(double x) {
  final e = exp(2 * x.clamp(-10.0, 10.0));
  return (e - 1) / (e + 1);
}
