import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../models.dart';
import '../services/db.dart';
import '../services/sync_service.dart';
import '../util.dart';

class ListadoScreen extends StatefulWidget {
  const ListadoScreen({super.key});

  @override
  State<ListadoScreen> createState() => ListadoScreenState();
}

class ListadoScreenState extends State<ListadoScreen> {
  final _buscar = TextEditingController();

  /// Día que se está mirando ('yyyy-MM-dd'). Arranca en hoy: en la puerta lo
  /// que importa es lo del servicio en curso.
  String _dia = fechaHoy();
  List<Atencion> _items = [];
  int _total = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    recargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> recargar() async {
    setState(() => _cargando = true);
    final items =
        await AppDb.instance.historial(buscar: _buscar.text, fecha: _dia);
    final total = await AppDb.instance.contarHistorial(fecha: _dia);
    if (mounted) {
      setState(() {
        _items = items;
        _total = total;
        _cargando = false;
      });
    }
  }

  bool get _esHoy => _dia == fechaHoy();

  Future<void> _elegirDia() async {
    final ahora = DateTime.now();
    final elegido = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dia) ?? ahora,
      firstDate: DateTime(2024),
      // Hasta hoy nomás: no hay raciones registradas en el futuro.
      lastDate: DateTime(ahora.year, ahora.month, ahora.day),
    );
    if (elegido == null) return;
    setState(() => _dia = fechaHoy(elegido));
    await recargar();
  }

  Future<void> _volverAHoy() async {
    setState(() => _dia = fechaHoy());
    await recargar();
  }

  String _fecha(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final filtrando = _buscar.text.trim().isNotEmpty;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _buscar,
          textInputAction: TextInputAction.search,
          // La búsqueda es contra SQLite, así que puede correr en cada tecla.
          onChanged: (_) => recargar(),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar por nombre o documento',
            prefixIcon: const Icon(Icons.search, color: AppColors.primary),
            suffixIcon: filtrando
                ? IconButton(
                    icon: const Icon(Icons.clear, color: AppColors.textoSuave),
                    tooltip: 'Limpiar',
                    onPressed: () {
                      _buscar.clear();
                      recargar();
                    },
                  )
                : null,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                filtrando
                    ? '${_items.length} de $_total registradas'
                    : '$_total registradas',
                style:
                    const TextStyle(color: AppColors.textoSuave, fontSize: 12),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (!_esHoy)
                IconButton(
                  icon: const Icon(Icons.today, size: 20),
                  tooltip: 'Volver a hoy',
                  color: AppColors.primary,
                  onPressed: _volverAHoy,
                ),
              TextButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_esHoy ? 'Hoy' : fechaCorta(_dia)),
                onPressed: _elegirDia,
              ),
            ]),
          ],
        ),
      ),
      Expanded(child: _lista(filtrando)),
    ]);
  }

  Widget _lista(bool filtrando) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            filtrando
                ? 'Ningún comensal coincide con la búsqueda en este día.'
                : _esHoy
                    ? 'Todavía no registraste atenciones hoy en este dispositivo.'
                    : 'No hay atenciones del ${fechaCorta(_dia)} en este dispositivo.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textoSuave),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await SyncService.instance.flush();
        await recargar();
      },
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final a = _items[i];
          // Rechazada por duplicada va en rojo: no fue una ración servida.
          final rechazada = a.rechazada == 1;
          final enviado = a.enviado == 1;
          final color = rechazada
              ? AppColors.peligro
              : (enviado ? AppColors.exito : AppColors.avisoTexto);
          final fondo = rechazada
              ? AppColors.peligroSuave
              : (enviado ? AppColors.exitoSuave : AppColors.avisoSuave);
          final icono = rechazada
              ? Icons.warning_rounded
              : (enviado ? Icons.cloud_done : Icons.cloud_upload);

          return ListTile(
            leading: CircleAvatar(
                backgroundColor: fondo, child: Icon(icono, color: color)),
            title: Text(a.nombreEstudiante ?? a.numDocumento),
            subtitle: Text('${a.servicioNombre ?? ''} · ${a.sedeNombre ?? ''}'
                '\nDoc: ${a.numDocumento} · ${_fecha(a.fechaHoraRegistro)}'
                '${rechazada && a.motivo != null ? '\n${a.motivo}' : ''}'),
            isThreeLine: true,
            trailing: Text(
              rechazada ? 'Duplicada' : (enviado ? 'Enviado' : 'Pendiente'),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }
}
