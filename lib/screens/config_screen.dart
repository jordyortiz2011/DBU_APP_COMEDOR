import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import '../models.dart';
import '../services/db.dart';
import '../services/session.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => ConfigScreenState();
}

class ConfigScreenState extends State<ConfigScreen> {
  final _url = TextEditingController(text: Session.instance.baseUrl);
  List<Servicio> _servicios = [];
  List<Map<String, Object?>> _metas = [];
  int _estudiantes = 0;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _cargar();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = '${i.version}+${i.buildNumber}');
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// La llama Home después de "Actualizar datos": la pantalla vive dentro de un
  /// IndexedStack y no se reconstruye sola.
  Future<void> recargar() => _cargar();

  Future<void> _cargar() async {
    final s = await AppDb.instance.getServicios();
    final n = await AppDb.instance.contarEstudiantes();
    final m = await AppDb.instance.plantillaMetas();
    if (mounted) {
      setState(() {
        _servicios = s;
        _estudiantes = n;
        _metas = m;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ultima = Session.instance.ultimaSync;
    final ultimaStr = ultima == null
        ? 'Nunca'
        : DateFormat('dd/MM/yyyy HH:mm').format(ultima);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _seccion('Usuario'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person, color: AppColors.primary),
            title: Text(Session.instance.userNombre.isEmpty ? '—' : Session.instance.userNombre),
            subtitle: Text('Sedes asignadas: ${Session.instance.sedes.length}'),
          ),
        ),
        const SizedBox(height: 12),
        _seccion('Servidor'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'URL del servidor', isDense: true),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar URL'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Session.instance.setBaseUrl(_url.text.trim());
                    messenger.showSnackBar(
                        const SnackBar(content: Text('URL guardada.')));
                  },
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _seccion('Datos descargados'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.people, color: AppColors.primary),
              title: const Text('Estudiantes en el dispositivo'),
              trailing: Text('$_estudiantes', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.schedule, color: AppColors.primary),
              title: const Text('Última actualización'),
              trailing: Text(ultimaStr),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _seccion('Horario de servicios (se descarga automáticamente)'),
        Card(
          child: _servicios.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('Sin datos. Pulsa "Actualizar datos" arriba.'))
              : Column(
                  children: _servicios
                      .map((s) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.restaurant, color: AppColors.primary),
                            title: Text(s.nombre),
                            trailing: Text('${s.horaInicio.substring(0, 5)} – ${s.horaFin.substring(0, 5)}'),
                          ))
                      .toList(),
                ),
        ),
        const SizedBox(height: 12),
        _seccion('Metas de raciones por sede (plantilla del período)'),
        Card(
          child: _metas.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Sin plantilla descargada. Con la meta del día ya generada en el servidor '
                      'el contador funciona igual; la plantilla solo cubre los días que aún no la tienen.'))
              : Column(
                  children: [
                    for (final m in _metas)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.flag,
                            color: AppColors.primary),
                        title: Text('${m['sede'] ?? 'Sede ${m['id_sede']}'}'),
                        subtitle: Text(
                            '${m['servicio'] ?? 'Servicio ${m['id_servicio']}'}'),
                        trailing: Text('${m['raciones']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.contador)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 24),
        Center(child: Text('Comedor DBU · v$_version', style: const TextStyle(color: AppColors.textoSuave))),
      ],
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4, left: 4),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
      );
}
