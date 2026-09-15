import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../util.dart';
import 'api.dart';
import 'db.dart';
import 'session.dart';

/// Qué hizo el servidor con una atención enviada en el momento.
enum EstadoEnvio {
  /// Quedó registrada.
  aceptada,

  /// El comensal ya tenía su ración: no cuenta.
  duplicada,

  /// El servidor la rechazó por otro motivo (datos, permisos).
  rechazada,

  /// No contestó a tiempo: se reintenta sola.
  enCola,
}

class ResultadoEnvio {
  final EstadoEnvio estado;

  /// Dónde y cuándo fue la ración anterior: {sede, fecha, hora}.
  final Map<String, dynamic>? previo;
  final String? mensaje;

  const ResultadoEnvio(this.estado, {this.previo, this.mensaje});
}

/// El 'previo' de un resultado, solo cuando el rechazo es por duplicado lógico.
///
/// El servidor también responde 'duplicado' sin 'previo' cuando reconoce un uuid
/// que ya recibió: eso es la idempotencia del reenvío y la atención SÍ vale, así
/// que la distinción es la presencia de 'previo', no el estado.
Map<String, dynamic>? previoDe(Map<String, dynamic> resultado) {
  if ('${resultado['estado']}' != 'duplicado') return null;
  final previo = resultado['previo'];
  return previo is Map ? previo.cast<String, dynamic>() : null;
}

/// 'Ya registrada en Iquitos · 20/08/2026 · 12:04:31' con lo que haya.
String motivoDuplicado(Map<String, dynamic> previo) {
  final partes = [
    if ('${previo['sede'] ?? ''}'.isNotEmpty) '${previo['sede']}',
    if ('${previo['fecha'] ?? ''}'.isNotEmpty) fechaCorta('${previo['fecha']}'),
    if ('${previo['hora'] ?? ''}'.isNotEmpty) '${previo['hora']}',
  ];
  return partes.isEmpty
      ? 'Ya tenía su ración de este servicio.'
      : 'Ya registrada: ${partes.join(' · ')}';
}

/// Envío en segundo plano de las atenciones en cola y descarga de datos.
/// Reintenta periódicamente y en cuanto vuelve la conexión (requisito:
/// registrar offline y enviar al recuperar internet).
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  final ValueNotifier<bool> enLinea = ValueNotifier(true);
  final ValueNotifier<int> pendientes = ValueNotifier(0);

  Timer? _timer;
  StreamSubscription? _connSub;
  bool _enviando = false;

  void iniciar() {
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) => flush());
    _connSub ??= Connectivity().onConnectivityChanged.listen((res) {
      final hay = res.any((r) => r != ConnectivityResult.none);
      enLinea.value = hay;
      if (hay) flush();
    });
    _refrescarConectividad();
    actualizarPendientes();
  }

  void detener() {
    _timer?.cancel();
    _timer = null;
    _connSub?.cancel();
    _connSub = null;
  }

  Future<void> _refrescarConectividad() async {
    final res = await Connectivity().checkConnectivity();
    enLinea.value = res.any((r) => r != ConnectivityResult.none);
  }

  Future<void> actualizarPendientes() async {
    pendientes.value = await AppDb.instance.contarPendientes();
  }

  /// Sube las atenciones pendientes. Devuelve cuántas quedaron sin enviar.
  Future<int> flush() async {
    if (_enviando || !Session.instance.logueado) {
      return pendientes.value;
    }
    _enviando = true;
    try {
      final List<Atencion> cola = await AppDb.instance.pendientes();
      if (cola.isEmpty) return 0;
      final resultados =
          await Api.instance.subirAtenciones(cola.map((a) => a.toApi()).toList());
      for (final r in resultados) {
        final uuid = '${r['uuid']}';
        final previo = previoDe(r);
        if (previo != null) {
          // El comensal ya tenía su ración (la registraron en la web o en otro
          // equipo). Se marca para que deje de contar; la fila queda como
          // constancia de lo que pasó.
          await AppDb.instance.marcarRechazada(uuid, motivoDuplicado(previo));
          continue;
        }
        final estado = '${r['estado']}';
        if (estado == 'ok' || estado == 'duplicado') {
          await AppDb.instance.marcarEnviada(uuid);
        }
      }
      enLinea.value = true;
    } catch (_) {
      // Sin conexión o timeout: se conservan en cola para el próximo intento.
      enLinea.value = false;
    } finally {
      _enviando = false;
      await actualizarPendientes();
    }
    return pendientes.value;
  }

  /// Envía UNA atención y espera la respuesta del servidor, para poder aceptar
  /// o rechazar en el acto en vez de dar por buena una ración que el servidor
  /// va a rechazar. Si no contesta dentro de [AppConfig.envioTimeout] queda en
  /// cola, que es el comportamiento offline de siempre.
  Future<ResultadoEnvio> enviarInmediato(Atencion a) async {
    if (_enviando) return const ResultadoEnvio(EstadoEnvio.enCola);
    _enviando = true;
    try {
      final resultados = await Api.instance.subirAtenciones([a.toApi()]);
      final r = resultados.firstWhere((x) => '${x['uuid']}' == a.uuid,
          orElse: () => const <String, dynamic>{});
      final estado = '${r['estado']}';
      final previo = previoDe(r);

      if (previo != null) {
        await AppDb.instance.marcarRechazada(a.uuid, motivoDuplicado(previo));
        enLinea.value = true;
        return ResultadoEnvio(EstadoEnvio.duplicada, previo: previo);
      }
      if (estado == 'ok' || estado == 'duplicado') {
        await AppDb.instance.marcarEnviada(a.uuid);
        enLinea.value = true;
        return const ResultadoEnvio(EstadoEnvio.aceptada);
      }
      // 'error' del servidor (datos incompletos, sede sin permiso...).
      return ResultadoEnvio(EstadoEnvio.rechazada,
          mensaje: '${r['mensaje'] ?? 'El servidor rechazó el registro.'}');
    } catch (_) {
      // Timeout o sin conexión: queda en cola para el reintento periódico.
      enLinea.value = false;
      return const ResultadoEnvio(EstadoEnvio.enCola);
    } finally {
      _enviando = false;
      await actualizarPendientes();
    }
  }

  /// Descarga y guarda localmente el padrón y la configuración.
  /// Devuelve la cantidad de estudiantes descargados.
  Future<int> descargarDatos() async {
    final data = await Api.instance.sync();

    final estudiantes = ((data['estudiantes'] as List?) ?? [])
        .map((m) => Estudiante.fromMap((m as Map).cast<String, dynamic>()))
        .toList();
    final servicios = ((data['servicios'] as List?) ?? [])
        .map((m) => Servicio.fromMap((m as Map).cast<String, dynamic>()))
        .toList();
    final sedes = ((data['sedes'] as List?) ?? [])
        .map((m) => Sede.fromMap((m as Map).cast<String, dynamic>()))
        .toList();
    final metas =
        ((data['metas'] as List?) ?? []).cast<Map<String, dynamic>>();
    // Plantilla del período: resuelve la meta de los días que aún no tienen
    // fila diaria generada, sin depender de tener conexión.
    final metasConfig =
        ((data['metas_config'] as List?) ?? []).cast<Map<String, dynamic>>();

    await AppDb.instance.reemplazarEstudiantes(estudiantes);
    await AppDb.instance.reemplazarServicios(servicios);
    await AppDb.instance.reemplazarSedes(sedes);
    await AppDb.instance.reemplazarMetas(metas);
    await AppDb.instance.reemplazarMetasConfig(metasConfig);
    await Session.instance.setSedes((data['sedes'] as List?) ?? []);
    await Session.instance.setUltimaSync(DateTime.now());

    return estudiantes.length;
  }
}
