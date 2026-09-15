import 'package:flutter/material.dart';

/// Configuración y constantes de la app del Comedor (DBU UNAP).
class AppConfig {
  /// URL base del servidor (editable desde el login). Debe terminar en '/'.
  /// En producción va sin '/public/': el docroot del servidor ya es esa carpeta.
  static const String defaultBaseUrl = 'https://sigdbu.unapiquitos.edu.pe/';

  /// Tiempo máximo de espera al enviar una atención en línea. Si se supera,
  /// la atención queda en cola para envío posterior (requisito: 3 segundos).
  static const Duration envioTimeout = Duration(seconds: 3);

  /// Tiempo de espera para login y descarga de datos (operaciones grandes).
  static const Duration syncTimeout = Duration(seconds: 30);

  /// Último recurso cuando el día no tiene meta ni la sede figura en la
  /// plantilla del período. Coincide con Model_metas::RACIONES_DEFECTO.
  static const int racionesDefecto = 919;
}

/// Paleta calcada de la web (alimentarios/registro): tema "white" del sistema,
/// con los acentos verdes que esa pantalla usa para el estado y el contador.
class AppColors {
  static const Color primary = Color(0xFF00897B);
  static const Color primaryDark = Color(0xFF00695C);
  static const Color primaryLight = Color(0xFF4DB6AC);

  /// Extremo claro del degradado de las cabeceras (.card-header-gradient).
  static const Color gradienteClaro = Color(0xFF26A69A);

  static const Color fondo = Color(0xFFF0F2F5); // --body-bg
  static const Color tarjeta = Color(0xFFFFFFFF); // --card-bg
  static const Color texto = Color(0xFF344767); // --text-primary
  static const Color textoSuave = Color(0xFF67748E); // --text-secondary
  static const Color borde = Color(0xFFE9ECEF); // --border-color

  static const Color exito = Color(0xFF198754); // btn-success / "En línea"
  static const Color exitoSuave = Color(0xFFD1E7DD);
  static const Color contador = Color(0xFF1E7A44); // .verde del "X / meta"
  static const Color aviso = Color(0xFFFFC107);
  static const Color avisoSuave = Color(0xFFFFF3CD);
  static const Color avisoTexto = Color(0xFF664D03);
  static const Color peligro = Color(0xFFDC3545);
  static const Color peligroSuave = Color(0xFFF8D7DA);
  static const Color infoSuave = Color(0xFFCFE2FF);

  /// linear-gradient(195deg, #26A69A 0%, #00695C 100%) de la web.
  static const LinearGradient cabecera = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [gradienteClaro, primaryDark],
  );

  static const List<BoxShadow> sombraTarjeta = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 2)),
  ];
}
