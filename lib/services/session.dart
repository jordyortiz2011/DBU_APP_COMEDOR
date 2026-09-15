import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Estado de sesión persistente: URL del servidor, token, usuario, sedes y un
/// verificador local de contraseña para permitir el login sin conexión de un
/// usuario que ya inició sesión en línea antes en este dispositivo.
class Session {
  Session._();
  static final Session instance = Session._();
  late SharedPreferences _sp;

  Future<void> init() async => _sp = await SharedPreferences.getInstance();

  String get baseUrl {
    var u = _sp.getString('base_url') ?? AppConfig.defaultBaseUrl;
    if (!u.endsWith('/')) u = '$u/';
    return u;
  }

  Future<void> setBaseUrl(String v) async =>
      _sp.setString('base_url', v.trim());

  String? get token => _sp.getString('token');
  Future<void> setToken(String? v) async =>
      v == null ? _sp.remove('token') : _sp.setString('token', v);

  int get userId => _sp.getInt('user_id') ?? 0;
  String get userNombre => _sp.getString('user_nombre') ?? '';

  Future<void> setUsuario(Map<String, dynamic> u) async {
    await _sp.setInt('user_id', int.tryParse('${u['id']}') ?? 0);
    await _sp.setString('user_nombre', '${u['nombre_completo'] ?? u['username'] ?? ''}');
    await _sp.setString('user_email', '${u['email'] ?? ''}');
  }

  List<Map<String, dynamic>> get sedes {
    final raw = _sp.getString('sedes');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> setSedes(List sedes) async =>
      _sp.setString('sedes', jsonEncode(sedes));

  DateTime? get ultimaSync {
    final s = _sp.getString('ultima_sync');
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setUltimaSync(DateTime t) async =>
      _sp.setString('ultima_sync', t.toIso8601String());

  int? get lastSede => _sp.getInt('last_sede');
  Future<void> setLastSede(int id) async => _sp.setInt('last_sede', id);

  bool get logueado => (token ?? '').isNotEmpty;

  // ── Verificador de login offline ───────────────────────────────────────
  static String _hash(String email, String pass) =>
      sha256.convert(utf8.encode('$email::$pass')).toString();

  Future<void> guardarVerificador(String email, String pass) async {
    final map = _verificadores();
    map[email.toLowerCase()] = _hash(email.toLowerCase(), pass);
    await _sp.setString('verificadores', jsonEncode(map));
  }

  bool verificarOffline(String email, String pass) {
    final map = _verificadores();
    final h = map[email.toLowerCase()];
    return h != null && h == _hash(email.toLowerCase(), pass);
  }

  Map<String, String> _verificadores() {
    final raw = _sp.getString('verificadores');
    if (raw == null) return {};
    return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
  }

  Future<void> cerrarSesion() async {
    await _sp.remove('token');
    await _sp.remove('user_id');
    await _sp.remove('user_nombre');
    await _sp.remove('sedes');
    // Se conservan base_url y verificadores para futuros inicios (incl. offline).
  }
}
