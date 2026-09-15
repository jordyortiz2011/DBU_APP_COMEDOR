import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../services/sync_service.dart';
import 'config_screen.dart';
import 'listado_screen.dart';
import 'login_screen.dart';
import 'registro_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _idx = 0;
  final _registroKey = GlobalKey<RegistroScreenState>();
  final _listadoKey = GlobalKey<ListadoScreenState>();
  final _configKey = GlobalKey<ConfigScreenState>();

  late final List<Widget> _paginas = [
    RegistroScreen(key: _registroKey),
    ListadoScreen(key: _listadoKey),
    ConfigScreen(key: _configKey),
  ];

  Future<void> _actualizarDatos() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Descargando datos...')),
        ]),
      ),
    );
    try {
      final n = await SyncService.instance.descargarDatos();
      // Las tres pantallas están vivas dentro del IndexedStack y no se
      // reconstruyen solas: hay que decirles que vuelvan a leer la base.
      await _registroKey.currentState?.recargar();
      await _configKey.currentState?.recargar();
      await _listadoKey.currentState?.recargar();
      if (mounted) Navigator.pop(context);
      _msg('Datos actualizados: $n estudiantes.');
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _msg('No se pudo actualizar: $e');
    }
  }

  Future<void> _cerrarSesion() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Deseas salir de tu cuenta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
        ],
      ),
    );
    if (ok != true) return;
    await Api.instance.logout();
    await Session.instance.cerrarSesion();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    const titulos = ['Registro de Atención', 'Mis Atenciones', 'Configuración'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titulos[_idx]),
        actions: [
          // Estado de conexión + pendientes.
          ValueListenableBuilder<bool>(
            valueListenable: SyncService.instance.enLinea,
            builder: (_, online, _) => ValueListenableBuilder<int>(
              valueListenable: SyncService.instance.pendientes,
              builder: (_, pend, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  Icon(online ? Icons.wifi : Icons.wifi_off,
                      color: online ? AppColors.exito : AppColors.avisoTexto),
                  if (pend > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text('$pend',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.avisoTexto)),
                    ),
                ]),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar datos',
            icon: const Icon(Icons.cloud_download),
            onPressed: _actualizarDatos,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'sync') SyncService.instance.flush();
              if (v == 'salir') _cerrarSesion();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'sync', child: Text('Enviar pendientes')),
              PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _idx, children: _paginas),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) {
          setState(() => _idx = i);
          if (i == 1) _listadoKey.currentState?.recargar();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Registro'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Listado'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Config'),
        ],
      ),
    );
  }
}
