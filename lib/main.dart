import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/session.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.instance.init();
  SyncService.instance.iniciar();
  runApp(const ComedorApp());
}

class ComedorApp extends StatelessWidget {
  const ComedorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Mismo reparto que la web: barra y tarjetas blancas sobre fondo gris,
    // texto azulado y el turquesa institucional solo en acentos y cabeceras.
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.tarjeta,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Comedor DBU',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: AppColors.fondo,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.tarjeta,
          foregroundColor: AppColors.texto,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shadowColor: Color(0x14000000),
          titleTextStyle: TextStyle(
            color: AppColors.texto,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.tarjeta,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.borde),
        textTheme: Typography.blackMountainView.apply(
          bodyColor: AppColors.texto,
          displayColor: AppColors.texto,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.tarjeta,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.borde),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.borde),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.textoSuave),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.tarjeta,
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          surfaceTintColor: Colors.transparent,
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: AppColors.primary),
      ),
      home: Session.instance.logueado ? const HomeScreen() : const LoginScreen(),
    );
  }
}
