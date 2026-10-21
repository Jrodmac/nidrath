import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Punto de control guardado en el teléfono (uno solo, se sobrescribe).
/// Se lee al arrancar y se guarda en segundo plano; si falla, el juego sigue sin guardar.
class SaveStore {
  static const _key = 'nidrath_checkpoint_v1';
  static String? _cached;

  static bool get hasSave => _cached != null;

  static Map<String, dynamic>? read() {
    final c = _cached;
    if (c == null) return null;
    try {
      return jsonDecode(c) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Nombre de la planta guardada, para el botón de continuar.
  static int? get savedFloor => read()?['fi'] as int?;

  static Future<void> load() async {
    try {
      _cached = (await SharedPreferences.getInstance()).getString(_key);
    } catch (_) {}
  }

  static void write(Map<String, dynamic> data) {
    _cached = jsonEncode(data);
    _persist();
  }

  static void clear() {
    _cached = null;
    _persist();
  }

  static Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final c = _cached;
      c == null ? await sp.remove(_key) : await sp.setString(_key, c);
    } catch (_) {}
  }
}
