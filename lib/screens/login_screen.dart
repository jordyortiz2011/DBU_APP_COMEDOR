import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import '../services/api.dart';
import '../services/session.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _url = TextEditingController(text: Session.instance.baseUrl);
  bool _cargando = false;
  bool _verUrl = false;
  bool _verPass = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = 'v${i.version}+${i.buildNumber}');
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.isEmpty) {
      _msg('Ingresa usuario y contraseña.');
      return;
    }
    setState(() => _cargando = true);
    await Session.instance.setBaseUrl(_url.text.trim());

    try {
      await Api.instance.login(email, pass);
      await Session.instance.guardarVerificador(email, pass);
      _irAHome();
    } catch (e) {
      // Sin conexión: permitir entrada offline si el usuario ya entró antes aquí.
      if (Session.instance.logueado && Session.instance.verificarOffline(email, pass)) {
        _msg('Sin conexión: ingresando en modo offline.');
        _irAHome();
      } else {
        _msg('$e');
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _irAHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/img/logo_unap.png', height: 72),
                      const SizedBox(width: 24),
                      Image.asset('assets/img/logo_dbu.png', height: 72),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Comedor Universitario',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark)),
                  const Text('Registro de atención · DBU UNAP',
                      style: TextStyle(color: AppColors.textoSuave)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'Usuario (correo)',
                        prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pass,
                    obscureText: !_verPass,
                    onSubmitted: (_) => _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_verPass ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _verPass = !_verPass),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _cargando ? null : _entrar,
                      icon: _cargando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.login),
                      label: Text(_cargando ? 'Ingresando...' : 'Ingresar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _verUrl = !_verUrl),
                    icon: const Icon(Icons.settings, size: 18),
                    label: const Text('Servidor'),
                  ),
                  if (_verUrl)
                    TextField(
                      controller: _url,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          labelText: 'URL del servidor',
                          helperText: 'Cámbiala solo si te lo indican. '
                              'Por defecto: ${AppConfig.defaultBaseUrl}'),
                    ),
                  const SizedBox(height: 24),
                  Text(_version, style: const TextStyle(color: AppColors.textoSuave)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
