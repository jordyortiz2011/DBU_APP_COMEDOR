import 'dart:math';

import 'models.dart';

/// Genera un uuid v4 sencillo para identificar cada atención (idempotencia).
String generarUuid() {
  final r = Random();
  String hex(int n) => r.nextInt(16 * n).toRadixString(16).padLeft(n, '0');
  return '${hex(8)}-${hex(4)}-4${hex(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(8)}${hex(4)}';
}

/// hora actual como 'HH:mm:ss'.
String horaActual([DateTime? t]) {
  final d = t ?? DateTime.now();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.hour)}:${dos(d.minute)}:${dos(d.second)}';
}

/// fecha 'yyyy-MM-dd'.
String fechaHoy([DateTime? t]) {
  final d = t ?? DateTime.now();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${dos(d.month)}-${dos(d.day)}';
}

const _dias = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Fecha en palabras: 'jueves 20 de agosto de 2026'. Se arma a mano para no
/// depender de los datos de locale de intl, que la app no inicializa.
String fechaLarga([DateTime? t]) {
  final d = t ?? DateTime.now();
  return '${_dias[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]} de ${d.year}';
}

const _conTilde = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _sinTilde = 'aaaaaeeeeiiiiooooouuuunc';

/// Minúsculas y sin tildes, para poder buscar como se escribe a las apuradas:
/// 'garcia' tiene que encontrar a 'GARCÍA'. SQLite no sabe hacerlo —su LOWER()
/// solo toca ASCII—, así que el filtro por nombre se resuelve en Dart.
String norm(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _conTilde.indexOf(ch);
    b.write(i >= 0 ? _sinTilde[i] : ch);
  }
  return b.toString().trim();
}

/// Fecha corta 'dd/MM/yyyy' a partir de un 'yyyy-MM-dd'.
String fechaCorta(String iso) {
  final p = iso.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
}

/// Servicio que corresponde a la hora actual según su rango; si ninguno,
/// el primero (antes del desayuno) o el último.
Servicio? servicioActual(List<Servicio> servicios, [DateTime? ahora]) {
  if (servicios.isEmpty) return null;
  final h = horaActual(ahora);
  for (final s in servicios) {
    if (h.compareTo(s.horaInicio) >= 0 && h.compareTo(s.horaFin) <= 0) return s;
  }
  return h.compareTo(servicios.first.horaInicio) < 0
      ? servicios.first
      : servicios.last;
}
