import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'session.dart';

class ApiException implements Exception {
  final String mensaje;
  final int? codigo;
  ApiException(this.mensaje, [this.codigo]);
  @override
  String toString() => mensaje;
}

/// Cliente de la API móvil del comedor (api/comedor/*). Token Bearer de Shield.
class Api {
  Api._();
  static final Api instance = Api._();

  final Session _s = Session.instance;

  Uri _uri(String path) => Uri.parse('${_s.baseUrl}$path');

  Map<String, String> _headers({bool auth = false}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (auth) 'Authorization': 'Bearer ${_s.token ?? ''}',
      };

  /// Inicia sesión y guarda el token. Devuelve el mapa de respuesta.
  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http
        .post(_uri('api/comedor/login'),
            headers: _headers(),
            body: jsonEncode({'email': email, 'password': password}))
        .timeout(AppConfig.syncTimeout);
    final body = _json(res);
    if (res.statusCode != 200 || body['ok'] != true) {
      throw ApiException(body['mensaje'] ?? 'No se pudo iniciar sesión.', res.statusCode);
    }
    await _s.setToken(body['token']);
    await _s.setUsuario((body['usuario'] as Map).cast<String, dynamic>());
    await _s.setSedes((body['sedes'] as List?) ?? []);
    return body;
  }

  /// Descarga usuarios, estudiantes, servicios, sedes y metas.
  Future<Map<String, dynamic>> sync() async {
    final res = await http
        .get(_uri('api/comedor/sync'), headers: _headers(auth: true))
        .timeout(AppConfig.syncTimeout);
    if (res.statusCode == 401) throw ApiException('Sesión expirada.', 401);
    final body = _json(res);
    if (res.statusCode != 200 || body['ok'] != true) {
      throw ApiException('No se pudieron descargar los datos.', res.statusCode);
    }
    return body;
  }

  /// Sube un lote de atenciones. Timeout corto: si tarda, el llamador las deja
  /// en cola. Devuelve la lista de resultados por uuid.
  Future<List<Map<String, dynamic>>> subirAtenciones(
      List<Map<String, dynamic>> atenciones) async {
    final res = await http
        .post(_uri('api/comedor/atenciones'),
            headers: _headers(auth: true),
            body: jsonEncode({'atenciones': atenciones}))
        .timeout(AppConfig.envioTimeout);
    if (res.statusCode == 401) throw ApiException('Sesión expirada.', 401);
    final body = _json(res);
    if (res.statusCode != 200 || body['ok'] != true) {
      throw ApiException('El servidor rechazó el envío.', res.statusCode);
    }
    return ((body['resultados'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> logout() async {
    try {
      await http
          .post(_uri('api/comedor/logout'), headers: _headers(auth: true))
          .timeout(AppConfig.envioTimeout);
    } catch (_) {
      // El cierre local procede aunque el servidor no responda.
    }
  }

  Map<String, dynamic> _json(http.Response res) {
    try {
      return (jsonDecode(res.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw ApiException('Respuesta inválida del servidor.', res.statusCode);
    }
  }
}
