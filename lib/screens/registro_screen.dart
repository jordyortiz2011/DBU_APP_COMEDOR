import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/api.dart';
import '../services/db.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import '../util.dart';
import 'scan_screen.dart';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => RegistroScreenState();
}

class RegistroScreenState extends State<RegistroScreen> {
  final _doc = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  List<Sede> _sedes = [];
  List<Servicio> _servicios = [];
  int? _idSede;
  int? _idServicio;
  String _tipo = 'ambos';

  /// Fecha y servicio siguen al reloj salvo que el operador los cambie a mano:
  /// sin conexión lo que queda grabado es la hora del dispositivo, así que la
  /// pantalla tiene que mostrar en todo momento con qué datos va a registrar.
  DateTime _fecha = DateTime.now();
  bool _fechaManual = false;
  bool _servicioManual = false;
  Timer? _reloj;

  int _total = 0;
  int _meta = AppConfig.racionesDefecto;

  /// Lo que otros equipos y la web registraron, por 'sede|servicio|fecha'.
  /// Se fija al pulsar "Total de la sede": servidor menos lo que este equipo ya
  /// había subido. Lo que se registre después suma por el conteo local, sin
  /// sincronizar en tiempo real. Junto va la hora de la consulta.
  final Map<String, ({int ajuste, DateTime hora})> _otros = {};
  bool _consultandoTotal = false;

  /// Teclado numérico por defecto (DNI/código); letras para buscar por nombre.
  bool _tecladoNumerico = true;
  String? _menu;
  Widget? _resultado;
  List<Estudiante> _opciones = [];
  bool _cargandoResultado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) => _tic());
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _scroll.dispose();
    _doc.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// La llama Home después de "Actualizar datos": la pantalla vive dentro de un
  /// IndexedStack y no se reconstruye sola, así que sin esto había que cerrar y
  /// volver a abrir la app para ver los datos recién descargados.
  Future<void> recargar() => _cargar();

  Future<void> _cargar() async {
    final sedesSesion =
        Session.instance.sedes.map((m) => Sede.fromMap(m)).toList();
    final servicios = await AppDb.instance.getServicios();
    final sedesDb = await AppDb.instance.getSedes();
    final sedes = sedesSesion.isNotEmpty ? sedesSesion : sedesDb;

    // Se conserva lo que el operador tenga elegido: recargar no puede cambiarle
    // por debajo la sede ni el servicio con los que está registrando.
    int? sedeSel = _idSede ?? Session.instance.lastSede;
    if (sedeSel == null || !sedes.any((s) => s.idSede == sedeSel)) {
      sedeSel = sedes.isNotEmpty ? sedes.first.idSede : null;
    }
    final servicioSel =
        _servicioManual && servicios.any((s) => s.idServicio == _idServicio)
            ? _idServicio
            : servicioActual(servicios)?.idServicio ??
                (servicios.isNotEmpty ? servicios.first.idServicio : null);

    if (!mounted) return; // la carga es asíncrona y la pantalla puede haberse ido
    setState(() {
      _sedes = sedes;
      _servicios = servicios;
      _idSede = sedeSel;
      _idServicio = servicioSel;
    });
    _refrescarContador();
  }

  /// Un tic por segundo que, si el operador no fijó nada a mano, hace rodar la
  /// fecha a medianoche y cambia de servicio al cruzar el horario. Solo repinta
  /// cuando algo cambia de verdad: ya no hay reloj en pantalla que mover.
  void _tic() {
    final ahora = DateTime.now();
    var cambio = false;

    if (!_fechaManual && fechaHoy(ahora) != fechaHoy(_fecha)) {
      _fecha = ahora;
      cambio = true;
    }
    if (!_servicioManual) {
      final s = servicioActual(_servicios, ahora);
      if (s != null && s.idServicio != _idServicio) {
        _idServicio = s.idServicio;
        cambio = true;
      }
    }
    if (!cambio) return;
    setState(() {});
    _refrescarContador();
  }

  String get _fechaStr => fechaHoy(_fecha);

  String get _claveConteo => '$_idSede|$_idServicio|$_fechaStr';

  Future<void> _consultarTotal() async {
    if (_idSede == null || _idServicio == null || _consultandoTotal) return;
    final clave = _claveConteo;
    final sede = _idSede!, servicio = _idServicio!, fecha = _fechaStr;
    setState(() => _consultandoTotal = true);
    try {
      final servidor = await Api.instance.conteo(sede, servicio, fecha);
      // Se lee después de la respuesta: lo que se subió mientras tanto ya
      // está en el total del servidor y también tiene que restarse.
      final propias = await AppDb.instance.enviadasDia(sede, servicio, fecha);
      if (!mounted) return;
      setState(() =>
          _otros[clave] = (ajuste: servidor - propias, hora: DateTime.now()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException
              ? 'No se pudo obtener el total: ${e.mensaje}'
              : 'No se pudo obtener el total: sin conexión con el servidor.')));
    } finally {
      if (mounted) setState(() => _consultandoTotal = false);
    }
  }

  Future<void> _refrescarContador() async {
    if (_idSede == null || _idServicio == null) return;
    final t = await AppDb.instance.conteoDia(_idSede!, _idServicio!, _fechaStr);
    // La meta va por sede: la misma fecha y servicio valen distinto en cada una.
    final m = await AppDb.instance.metaDe(_fechaStr, _idSede!, _idServicio!);
    final menu = await AppDb.instance.menuDe(_fechaStr, _idSede!, _idServicio!);
    if (mounted) {
      setState(() {
        _total = t;
        _meta = m;
        _menu = menu;
      });
    }
  }

  Future<void> _buscar({bool auto = false}) async {
    final q = _doc.text.trim();
    if (q.length < 2 || _idSede == null || _idServicio == null) return;
    setState(() {
      _cargandoResultado = true;
      _opciones = [];
    });
    final lista = await AppDb.instance.buscarEstudiantes(q, _tipo);
    setState(() => _cargandoResultado = false);

    if (lista.isEmpty) {
      _mostrarError('No matriculado en el periodo vigente o no encontrado: $q');
      _verBloqueDocumento();
      return;
    }
    final exacto =
        lista.where((e) => e.numDocumento == q || e.codigoUniversitario == q);
    if (exacto.isNotEmpty && (auto || lista.length == 1)) {
      _registrar(exacto.first);
      return;
    }
    if (lista.length == 1) {
      _registrar(lista.first);
      return;
    }
    setState(() => _opciones = lista); // el usuario elige
    _verBloqueDocumento();
  }

  /// El comedor atiende a la filial Iquitos. Un comensal de otra filial puede
  /// ser un traslado o una visita, así que se pregunta en vez de bloquear,
  /// igual que en la web. Funciona sin conexión: la filial viene en el padrón.
  static const String _filialSede = 'IQUITOS';

  bool _esOtraFilial(Estudiante e) {
    final f = norm(e.filial ?? '');
    return f.isNotEmpty && f != norm(_filialSede);
  }

  Future<bool> _confirmarOtraFilial(Estudiante e) async {
    Widget fila(String etq, String? valor) => (valor == null || valor.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 92,
                  child: Text(etq,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textoSuave,
                          fontSize: 13))),
              Expanded(
                  child: Text(valor,
                      style: const TextStyle(
                          color: AppColors.texto, fontSize: 13))),
            ]),
          );

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: AppColors.avisoTexto, size: 40),
        title: const Text('Estudiante de otra filial'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Este estudiante pertenece a la filial ${e.filial}, no a Iquitos.',
              style: const TextStyle(color: AppColors.textoSuave, fontSize: 13)),
          const SizedBox(height: 12),
          fila('Estudiante', e.nombreCompleto),
          fila('Documento', e.numDocumento),
          fila('Código', e.codigoUniversitario),
          fila('Filial', e.filial),
          fila('Facultad', e.facultad),
          fila('Escuela', e.escuela),
          const SizedBox(height: 12),
          const Text('¿Desea registrar la asistencia del estudiante?',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.texto)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No',
                  style: TextStyle(color: AppColors.peligro))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.exito),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, registrar')),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Si lo escrito coincide con el documento o con el código, por ahí se lo
  /// identificó; si no, se lo eligió de la búsqueda por nombre.
  String _metodoDe(Estudiante e, String q) {
    if (q.isNotEmpty && e.numDocumento == q) return 'DNI';
    if (q.isNotEmpty && e.codigoUniversitario == q) return 'CODIGO';
    return 'NOMBRE';
  }

  Future<void> _registrar(Estudiante e) async {
    setState(() => _opciones = []);
    // Se captura antes de cualquier await: el campo se limpia al terminar.
    final metodo = _metodoDe(e, _doc.text.trim());

    if (_esOtraFilial(e)) {
      final seguir = await _confirmarOtraFilial(e);
      if (!mounted) return;
      if (!seguir) {
        _mostrarError(
            'No se registró la asistencia de ${e.nombreCompleto} (filial ${e.filial}).');
        _limpiar();
        return;
      }
    }

    final previo = await AppDb.instance
        .registroPrevio(_idServicio!, _fechaStr, e.numDocumento);
    if (previo != null) {
      _mostrarResultado(e, 'duplicado', previo: previo);
      _limpiar();
      return;
    }

    final online = SyncService.instance.enLinea.value;
    if (online) setState(() => _cargandoResultado = true);
    final atencion = Atencion(
      uuid: generarUuid(),
      idSede: _idSede!,
      idServicio: _idServicio!,
      idEstudiante: e.idEstudiante,
      numDocumento: e.numDocumento,
      fechaAtencion: _fechaStr,
      fechaHoraRegistro: DateTime.now().toIso8601String(),
      origen: online ? 'MOVIL' : 'MOVIL_OFFLINE',
      metodo: metodo,
      nombreEstudiante: e.nombreCompleto,
      sedeNombre: _nombreSede(_idSede!),
      servicioNombre: _nombreServicio(_idServicio!),
    );
    await AppDb.instance.insertarAtencion(atencion);
    await SyncService.instance.actualizarPendientes();

    if (online) {
      // Con conexión se espera la respuesta del servidor antes de dar la ración
      // por buena: puede que el comensal ya haya pasado por la web o por otro
      // equipo, y ahí no debe contar. Si no contesta en 3 s, queda en cola.
      final res = await SyncService.instance.enviarInmediato(atencion);
      if (!mounted) return;
      setState(() => _cargandoResultado = false);

      switch (res.estado) {
        case EstadoEnvio.aceptada:
          _mostrarResultado(e, 'ok');
        case EstadoEnvio.duplicada:
          _mostrarResultado(e, 'duplicado',
              detalle:
                  res.previo == null ? null : _detalleServidor(res.previo!));
        case EstadoEnvio.rechazada:
          await AppDb.instance.borrarAtencion(atencion.uuid);
          await SyncService.instance.actualizarPendientes();
          _mostrarError(res.mensaje ?? 'El servidor rechazó el registro.');
        case EstadoEnvio.enCola:
          _mostrarResultado(e, 'offline');
      }
    } else {
      _mostrarResultado(e, 'offline');
    }

    _limpiar();
    await _refrescarContador();
  }

  void _limpiar() {
    _doc.clear();
    _focus.requestFocus();
    _verBloqueDocumento();
  }

  /// Deja el bloque del documento —mensaje y campo— al final de lo visible.
  ///
  /// Con el teclado en pantalla el alto útil se parte al medio. El campo suele
  /// tener ya el foco (se acaba de escanear), así que Flutter no scrollea solo,
  /// y el mensaje nuevo empuja el contenido fuera de la vista. Se salta al
  /// final en vez de recordar el scroll anterior: ese desplazamiento se midió
  /// con el teclado cerrado y ya no apunta al mismo lugar.
  void _verBloqueDocumento() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String _nombreSede(int id) => _sedes
      .firstWhere((s) => s.idSede == id,
          orElse: () => Sede(idSede: id, nombre: ''))
      .nombre;

  String _nombreServicio(int id) => _servicios
      .firstWhere((s) => s.idServicio == id,
          orElse: () => Servicio(
              idServicio: id,
              nombre: '',
              horaInicio: '',
              horaFin: '',
              orden: 0))
      .nombre;

  Future<void> _escanear() async {
    final code = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (code != null && code.isNotEmpty) {
      _doc.text = code.trim();
      _buscar(auto: true);
    }
  }

  // ── Mensajes embebidos ──────────────────────────────────────────────────
  void _mostrarResultado(Estudiante e, String modo,
      {Atencion? previo, String? detalle}) {
    final Color bg;
    final Color color;
    final IconData icon;
    final String titulo;
    switch (modo) {
      case 'duplicado':
        // En rojo, igual que la web: el rechazo tiene que verse de un vistazo
        // en la puerta del comedor.
        bg = AppColors.peligroSuave;
        color = AppColors.peligro;
        icon = Icons.warning_rounded;
        titulo = 'Ya pasó hoy por este servicio.';
        break;
      case 'offline':
        bg = AppColors.avisoSuave;
        color = AppColors.avisoTexto;
        icon = Icons.cloud_upload;
        titulo = 'Registrado sin conexión: se enviará automáticamente.';
        break;
      default:
        bg = AppColors.exitoSuave;
        color = AppColors.exito;
        icon = Icons.check_circle;
        titulo = '¡Ración registrada!';
    }
    setState(() {
      _resultado = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, color: color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.nombreCompleto,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.texto)),
              if (e.datos.isNotEmpty)
                Text(e.datos,
                    style: const TextStyle(
                        color: AppColors.textoSuave, fontSize: 12)),
              Text('Doc: ${e.numDocumento}',
                  style: const TextStyle(
                      color: AppColors.textoSuave, fontSize: 12)),
              const SizedBox(height: 4),
              Text(titulo,
                  style:
                      TextStyle(fontWeight: FontWeight.w600, color: color)),
              // Dónde y cuándo pasó: el operador tiene que poder explicárselo
              // al comensal ahí mismo, sobre todo si fue en la otra sede.
              if (previo != null || detalle != null)
                Text(detalle ?? _detallePrevio(previo!),
                    style: TextStyle(color: color, fontSize: 13)),
            ]),
          ),
        ]),
      );
    });
  }

  /// Lo mismo pero con el {sede, fecha, hora} que devuelve el servidor cuando
  /// la ración anterior se registró en la web o en otro equipo.
  String _detalleServidor(Map<String, dynamic> previo) => [
        if ('${previo['sede'] ?? ''}'.isNotEmpty) '${previo['sede']}',
        if ('${previo['fecha'] ?? ''}'.isNotEmpty)
          fechaCorta('${previo['fecha']}'),
        if ('${previo['hora'] ?? ''}'.isNotEmpty) '${previo['hora']}',
      ].join(' · ');

  /// 'Iquitos · 20/08/2026 · 12:04:31' con lo que haya de la ración anterior.
  String _detallePrevio(Atencion a) {
    final hora = DateTime.tryParse(a.fechaHoraRegistro);
    return [
      if ((a.sedeNombre ?? '').isNotEmpty) a.sedeNombre!,
      fechaCorta(a.fechaAtencion),
      if (hora != null) horaActual(hora),
    ].join(' · ');
  }

  void _mostrarError(String t) {
    setState(() {
      _resultado = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.peligroSuave,
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.cancel, color: AppColors.peligro, size: 30),
          const SizedBox(width: 12),
          Expanded(
              child: Text(t, style: const TextStyle(color: AppColors.texto))),
        ]),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_sedes.isEmpty || _servicios.isEmpty) {
      return _aviso(
          'No hay datos locales. Pulsa "Actualizar datos" (arriba) con conexión para descargar estudiantes y configuración.');
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      children: [
        _tarjetaAtencion(),
        const SizedBox(height: 16),
        _tarjetaDocumento(),
      ],
    );
  }

  // ── Tarjeta superior: cabecera, reloj, estado, contador y selectores ─────
  Widget _tarjetaAtencion() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // El contador manda: si no entra todo, el chip se recorta antes.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: _chipCabecera()),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _badgeConexion(),
                  const SizedBox(height: 6),
                  _contador(),
                ]),
              ],
            ),
            if (_menu != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.restaurant_menu,
                    size: 16, color: AppColors.textoSuave),
                const SizedBox(width: 6),
                Expanded(
                    child: Text('Menú: $_menu',
                        style: const TextStyle(
                            color: AppColors.textoSuave, fontSize: 13))),
              ]),
            ],
            const Divider(height: 28),
            Row(children: [
              Expanded(child: _selectorFecha()),
              const SizedBox(width: 10),
              Expanded(child: _dropdownSede()),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _dropdownServicio()),
              const SizedBox(width: 10),
              Expanded(child: _dropdownTipo()),
            ]),
          ]),
        ),
      );

  Widget _chipCabecera() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: AppColors.cabecera,
          borderRadius: BorderRadius.circular(8),
          boxShadow: AppColors.sombraTarjeta,
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.local_cafe, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Flexible(
            child: Text('Atención del Comedor',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ),
        ]),
      );

  Widget _contador() {
    final otros = _otros[_claveConteo];
    // Lo anulado desde la web después de la consulta puede dejar el ajuste
    // por debajo de cero hasta la próxima; el total nunca se muestra negativo.
    final total = otros == null ? _total : (_total + otros.ajuste).clamp(0, 1 << 30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('$total / $_meta',
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                height: 1,
                color: AppColors.contador)),
        const SizedBox(height: 2),
        Text(
            otros == null
                ? 'raciones de este equipo (día)'
                : 'total sede · ${horaActual(otros.hora).substring(0, 5)}',
            style: const TextStyle(color: AppColors.textoSuave, fontSize: 11)),
        const SizedBox(height: 4),
        SizedBox(
          height: 28,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 11)),
            onPressed: _consultandoTotal ? null : _consultarTotal,
            icon: _consultandoTotal
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.groups, size: 14),
            label: const Text('Total de la sede'),
          ),
        ),
      ],
    );
  }

  Widget _badgeConexion() => ValueListenableBuilder<bool>(
        valueListenable: SyncService.instance.enLinea,
        builder: (_, online, _) => ValueListenableBuilder<int>(
          valueListenable: SyncService.instance.pendientes,
          builder: (_, pend, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: online ? AppColors.exito : AppColors.aviso,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(online ? Icons.wifi : Icons.wifi_off,
                      size: 13,
                      color: online ? Colors.white : AppColors.avisoTexto),
                  const SizedBox(width: 5),
                  Text(online ? 'En línea' : 'Sin conexión',
                      style: TextStyle(
                          color: online ? Colors.white : AppColors.avisoTexto,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
              if (pend > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$pend por enviar',
                      style: const TextStyle(
                          color: AppColors.textoSuave, fontSize: 11)),
                ),
            ],
          ),
        ),
      );

  // ── Tarjeta inferior: documento y resultado ─────────────────────────────
  Widget _tarjetaDocumento() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // El mensaje va ENCIMA del campo: con el teclado abierto, el
            // scroll automático que hace Flutter para mostrar el campo deja
            // esto a la vista, sin que el operador tenga que bajar a leerlo.
            if (_opciones.isNotEmpty) ..._opciones.map(_tileOpcion),
            if (_resultado != null && _opciones.isEmpty) ...[
              _resultado!,
              const SizedBox(height: 12),
            ],
            const Text('Documento del estudiante',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.texto)),
            const SizedBox(height: 10),
            TextField(
              controller: _doc,
              focusNode: _focus,
              autofocus: true,
              keyboardType: _tecladoNumerico
                  ? TextInputType.number
                  : TextInputType.text,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(auto: true),
              decoration: InputDecoration(
                hintText: 'Escanea o escribe DNI / código',
                // Alterna el teclado: numérico para DNI/código, letras para
                // buscar por nombre.
                prefixIcon: IconButton(
                  icon: Icon(
                      _tecladoNumerico ? Icons.abc : Icons.dialpad,
                      color: AppColors.primary),
                  tooltip: _tecladoNumerico
                      ? 'Teclado de letras'
                      : 'Teclado numérico',
                  onPressed: () {
                    setState(() => _tecladoNumerico = !_tecladoNumerico);
                    // El teclado abierto no cambia de tipo solo: se reabre.
                    _focus.unfocus();
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _focus.requestFocus());
                  },
                ),
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      icon: const Icon(Icons.qr_code_scanner,
                          color: AppColors.primary),
                      tooltip: 'Escanear',
                      onPressed: _escanear),
                  IconButton(
                      icon: const Icon(Icons.search, color: AppColors.exito),
                      onPressed: () => _buscar()),
                ]),
              ),
            ),
            if (_cargandoResultado)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator())),
          ]),
        ),
      );

  Widget _tileOpcion(Estudiante e) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(e.nombreCompleto,
            style: const TextStyle(color: AppColors.texto)),
        subtitle: Text(
            'Doc: ${e.numDocumento}'
            '${e.codigoUniversitario != null ? ' · Cód: ${e.codigoUniversitario}' : ''}'
            '${e.datos.isNotEmpty ? ' · ${e.datos}' : ''}',
            style: const TextStyle(color: AppColors.textoSuave)),
        onTap: () => _registrar(e),
      );

  Widget _selectorFecha() => InputDecorator(
        decoration: const InputDecoration(labelText: 'Fecha', isDense: true),
        child: InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _fecha,
              firstDate: DateTime(2024),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (d != null) {
              setState(() {
                _fecha = d;
                // Elegir un día distinto de hoy congela la fecha; volver a hoy
                // devuelve el seguimiento automático del reloj.
                _fechaManual = fechaHoy(d) != fechaHoy(DateTime.now());
              });
              _refrescarContador();
            }
          },
          // Al sacar el bloque del reloj se perdió el aviso de fecha fijada a
          // mano; queda acá, en ámbar, sin ocupar espacio cuando no aplica.
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fechaCorta(_fechaStr),
                    style: TextStyle(
                        color: _fechaManual
                            ? AppColors.avisoTexto
                            : AppColors.texto,
                        fontWeight: _fechaManual
                            ? FontWeight.bold
                            : FontWeight.normal)),
                Icon(Icons.calendar_today,
                    size: 18,
                    color: _fechaManual
                        ? AppColors.avisoTexto
                        : AppColors.textoSuave),
              ]),
        ),
      );

  Widget _dropdownSede() => DropdownButtonFormField<int>(
        initialValue: _idSede,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Sede', isDense: true),
        items: _sedes
            .map((s) => DropdownMenuItem(
                value: s.idSede,
                child: Text(s.nombre, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (v) {
          setState(() => _idSede = v);
          if (v != null) Session.instance.setLastSede(v);
          _refrescarContador();
        },
      );

  Widget _dropdownServicio() => DropdownButtonFormField<int>(
        initialValue: _idServicio,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Servicio', isDense: true),
        items: _servicios
            .map((s) => DropdownMenuItem(
                value: s.idServicio,
                child: Text(s.nombre, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: (v) {
          setState(() {
            _idServicio = v;
            // Igual que la fecha: elegir un servicio que no es el de la hora lo fija.
            final auto = servicioActual(_servicios, DateTime.now());
            _servicioManual = v != null && auto != null && v != auto.idServicio;
          });
          _refrescarContador();
        },
      );

  Widget _dropdownTipo() => DropdownButtonFormField<String>(
        initialValue: _tipo,
        isExpanded: true,
        decoration:
            const InputDecoration(labelText: 'Buscar por', isDense: true),
        items: const [
          DropdownMenuItem(value: 'ambos', child: Text('DNI / Código')),
          DropdownMenuItem(value: 'dni', child: Text('DNI')),
          DropdownMenuItem(value: 'codigo', child: Text('Código')),
        ],
        onChanged: (v) => setState(() => _tipo = v ?? 'ambos'),
      );

  Widget _aviso(String t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.textoSuave),
            const SizedBox(height: 12),
            Text(t,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textoSuave)),
          ]),
        ),
      );
}
