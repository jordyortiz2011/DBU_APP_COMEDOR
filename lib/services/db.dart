import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../config.dart';
import '../models.dart';
import '../util.dart';

/// Las metas van por sede: la misma fecha y servicio tienen un número distinto
/// en Iquitos y en Zungarococha, igual que en tbl_alimentarios_metas.
const String _sqlMetas = '''
  CREATE TABLE metas (
    fecha TEXT, id_sede INTEGER, id_servicio INTEGER,
    raciones INTEGER, menu TEXT,
    PRIMARY KEY (fecha, id_sede, id_servicio)
  )''';

/// Plantilla del período (tbl_alimentarios_metas_config): es la que rige los
/// días que todavía no tienen fila diaria generada.
const String _sqlMetasConfig = '''
  CREATE TABLE metas_config (
    id_sede INTEGER, id_servicio INTEGER, raciones INTEGER,
    PRIMARY KEY (id_sede, id_servicio)
  )''';

/// Base de datos local (SQLite): padrón de estudiantes, servicios, sedes,
/// metas y la cola/registro de atenciones.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'comedor.db'),
      version: 4,
      onUpgrade: (d, desde, _) async {
        // Las metas se rehacen enteras en cada descarga, así que la migración
        // puede tirarlas: la siguiente sincronización las repone.
        if (desde < 2) {
          await d.execute('DROP TABLE IF EXISTS metas');
          await d.execute(_sqlMetas);
          await d.execute(_sqlMetasConfig);
        }
        // Las atenciones sí hay que conservarlas: se agregan las columnas.
        if (desde < 3) {
          await d.execute(
              'ALTER TABLE atenciones ADD COLUMN rechazada INTEGER DEFAULT 0');
          await d.execute('ALTER TABLE atenciones ADD COLUMN motivo TEXT');
        }
        // La filial del comensal y con qué se lo identificó llegaron después.
        if (desde < 4) {
          await d.execute('ALTER TABLE estudiantes ADD COLUMN filial TEXT');
          await d.execute('ALTER TABLE atenciones ADD COLUMN metodo TEXT');
        }
      },
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE estudiantes (
            num_documento TEXT PRIMARY KEY,
            id_estudiante INTEGER,
            codigo_universitario TEXT,
            nombre_completo TEXT,
            facultad TEXT,
            escuela TEXT,
            filial TEXT
          )''');
        await d.execute('''
          CREATE TABLE servicios (
            id_servicio INTEGER PRIMARY KEY, nombre TEXT,
            hora_inicio TEXT, hora_fin TEXT, orden INTEGER
          )''');
        await d.execute('''
          CREATE TABLE sedes (id_sede INTEGER PRIMARY KEY, nombre TEXT)''');
        await d.execute(_sqlMetas);
        await d.execute(_sqlMetasConfig);
        await d.execute('''
          CREATE TABLE atenciones (
            uuid TEXT PRIMARY KEY,
            id_sede INTEGER, id_servicio INTEGER, id_estudiante INTEGER,
            num_documento TEXT, fecha_atencion TEXT, fecha_hora_registro TEXT,
            origen TEXT, metodo TEXT, enviado INTEGER DEFAULT 0,
            rechazada INTEGER DEFAULT 0, motivo TEXT,
            nombre_estudiante TEXT, sede_nombre TEXT, servicio_nombre TEXT
          )''');
        await d.execute(
            'CREATE INDEX idx_atn_dia ON atenciones(id_sede,id_servicio,fecha_atencion)');
      },
    );
  }

  // ── Padrón de estudiantes ───────────────────────────────────────────────
  Future<void> reemplazarEstudiantes(List<Estudiante> lista) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('estudiantes');
    for (final e in lista) {
      if (e.numDocumento.isEmpty) continue;
      batch.insert('estudiantes', e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<int> contarEstudiantes() async {
    final d = await db;
    final r = await d.rawQuery('SELECT COUNT(*) c FROM estudiantes');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Busca por DNI/código (prefijo) o nombre (subcadena). tipo: ambos|dni|codigo.
  Future<List<Estudiante>> buscarEstudiantes(String q, String tipo) async {
    final d = await db;
    final s = q.toLowerCase();
    final like = '$s%';
    String where;
    List<Object?> args;
    if (tipo == 'dni') {
      where = 'LOWER(num_documento) LIKE ? OR LOWER(nombre_completo) LIKE ?';
      args = [like, '%$s%'];
    } else if (tipo == 'codigo') {
      where =
          'LOWER(codigo_universitario) LIKE ? OR LOWER(nombre_completo) LIKE ?';
      args = [like, '%$s%'];
    } else {
      where =
          'LOWER(num_documento) LIKE ? OR LOWER(codigo_universitario) LIKE ? OR LOWER(nombre_completo) LIKE ?';
      args = [like, like, '%$s%'];
    }
    final rows = await d.query('estudiantes',
        where: where, whereArgs: args, orderBy: 'nombre_completo', limit: 15);
    return rows.map((m) => Estudiante.fromMap(m)).toList();
  }

  // ── Config ──────────────────────────────────────────────────────────────
  Future<void> reemplazarServicios(List<Servicio> lista) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('servicios');
    for (final s in lista) {
      batch.insert('servicios', s.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<Servicio>> getServicios() async {
    final d = await db;
    final rows = await d.query('servicios', orderBy: 'orden');
    return rows.map((m) => Servicio.fromMap(m)).toList();
  }

  Future<void> reemplazarSedes(List<Sede> lista) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('sedes');
    for (final s in lista) {
      batch.insert('sedes', s.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<Sede>> getSedes() async {
    final d = await db;
    final rows = await d.query('sedes', orderBy: 'nombre');
    return rows.map((m) => Sede.fromMap(m)).toList();
  }

  Future<void> reemplazarMetas(List<Map<String, dynamic>> lista) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('metas');
    for (final m in lista) {
      batch.insert(
          'metas',
          {
            'fecha': '${m['fecha']}',
            'id_sede': int.tryParse('${m['id_sede']}') ?? 0,
            'id_servicio': int.parse('${m['id_servicio']}'),
            'raciones':
                int.tryParse('${m['raciones']}') ?? AppConfig.racionesDefecto,
            'menu': m['menu']?.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> reemplazarMetasConfig(List<Map<String, dynamic>> lista) async {
    final d = await db;
    final batch = d.batch();
    batch.delete('metas_config');
    for (final m in lista) {
      batch.insert(
          'metas_config',
          {
            'id_sede': int.tryParse('${m['id_sede']}') ?? 0,
            'id_servicio': int.tryParse('${m['id_servicio']}') ?? 0,
            'raciones':
                int.tryParse('${m['raciones']}') ?? AppConfig.racionesDefecto,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Meta que rige un día en una sede, con la misma cascada que la web:
  /// fila diaria → plantilla del período → valor por defecto.
  Future<int> metaDe(String fecha, int idSede, int idServicio) async {
    final d = await db;
    final diaria = await d.query('metas',
        columns: ['raciones'],
        where: 'fecha = ? AND id_sede = ? AND id_servicio = ?',
        whereArgs: [fecha, idSede, idServicio]);
    if (diaria.isNotEmpty) {
      return int.tryParse('${diaria.first['raciones']}') ??
          AppConfig.racionesDefecto;
    }
    final plantilla = await d.query('metas_config',
        columns: ['raciones'],
        where: 'id_sede = ? AND id_servicio = ?',
        whereArgs: [idSede, idServicio]);
    if (plantilla.isNotEmpty) {
      return int.tryParse('${plantilla.first['raciones']}') ??
          AppConfig.racionesDefecto;
    }
    return AppConfig.racionesDefecto;
  }

  /// Menú del día en una sede, si la meta diaria lo trae.
  Future<String?> menuDe(String fecha, int idSede, int idServicio) async {
    final d = await db;
    final r = await d.query('metas',
        columns: ['menu'],
        where: 'fecha = ? AND id_sede = ? AND id_servicio = ?',
        whereArgs: [fecha, idSede, idServicio]);
    final menu = r.isEmpty ? null : r.first['menu']?.toString();
    return (menu == null || menu.isEmpty) ? null : menu;
  }

  /// Plantilla de metas descargada, con los nombres de sede y servicio,
  /// para mostrarla en Configuración.
  Future<List<Map<String, Object?>>> plantillaMetas() async {
    final d = await db;
    return d.rawQuery('''
      SELECT mc.id_sede, mc.id_servicio, mc.raciones,
             sd.nombre AS sede, sv.nombre AS servicio
      FROM metas_config mc
      LEFT JOIN sedes sd ON sd.id_sede = mc.id_sede
      LEFT JOIN servicios sv ON sv.id_servicio = mc.id_servicio
      ORDER BY sd.nombre, sv.orden''');
  }

  // ── Atenciones ──────────────────────────────────────────────────────────
  Future<void> insertarAtencion(Atencion a) async {
    final d = await db;
    await d.insert('atenciones', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// La ración que este comensal ya tiene hoy en ese servicio, o null.
  ///
  /// No filtra por sede, igual que Model_atenciones::guardar en el servidor:
  /// si se filtrara, el comensal repetiría servicio yendo al otro comedor.
  /// Solo ve lo registrado en ESTE dispositivo.
  Future<Atencion?> registroPrevio(
      int idServicio, String fecha, String numDoc) async {
    final d = await db;
    final r = await d.query('atenciones',
        where: 'id_servicio = ? AND fecha_atencion = ? AND num_documento = ? '
            'AND rechazada = 0',
        whereArgs: [idServicio, fecha, numDoc],
        orderBy: 'fecha_hora_registro',
        limit: 1);
    return r.isEmpty ? null : Atencion.fromMap(r.first);
  }

  Future<int> conteoDia(int idSede, int idServicio, String fecha) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM atenciones '
        'WHERE id_sede=? AND id_servicio=? AND fecha_atencion=? AND rechazada=0',
        [idSede, idServicio, fecha]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  /// Las del día que este equipo ya subió: el total del servidor las incluye,
  /// así que se restan para no contarlas dos veces al sumar lo local.
  Future<int> enviadasDia(int idSede, int idServicio, String fecha) async {
    final d = await db;
    final r = await d.rawQuery(
        'SELECT COUNT(*) c FROM atenciones '
        'WHERE id_sede=? AND id_servicio=? AND fecha_atencion=? '
        'AND enviado=1 AND rechazada=0',
        [idSede, idServicio, fecha]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<Atencion>> pendientes() async {
    final d = await db;
    final rows = await d.query('atenciones',
        where: 'enviado = 0 AND rechazada = 0',
        orderBy: 'fecha_hora_registro');
    return rows.map((m) => Atencion.fromMap(m)).toList();
  }

  /// El servidor rechazó la ración por duplicada: deja de contar y sale de la
  /// cola, pero la fila se conserva para que el operador vea qué pasó.
  Future<void> marcarRechazada(String uuid, String motivo) async {
    final d = await db;
    await d.update('atenciones', {'rechazada': 1, 'enviado': 0, 'motivo': motivo},
        where: 'uuid = ?', whereArgs: [uuid]);
  }

  /// Borra una atención de la base local (la que se rechaza en el acto: nunca
  /// llegó a ser una ración, no tiene sentido dejarla en el historial).
  Future<void> borrarAtencion(String uuid) async {
    final d = await db;
    await d.delete('atenciones', where: 'uuid = ?', whereArgs: [uuid]);
  }

  Future<void> marcarEnviada(String uuid) async {
    final d = await db;
    await d.update('atenciones', {'enviado': 1},
        where: 'uuid = ?', whereArgs: [uuid]);
  }

  /// Atenciones registradas en el dispositivo, de la más reciente hacia atrás.
  /// [fecha] ('yyyy-MM-dd') acota a un día; null trae todos.
  /// [buscar] filtra por nombre o documento del comensal.
  ///
  /// El tope de 1000 es holgado para un día: una sede sirve del orden de 900
  /// raciones por servicio.
  Future<List<Atencion>> historial({
    int limit = 1000,
    String buscar = '',
    String? fecha,
  }) async {
    final d = await db;
    final q = norm(buscar);
    final where = fecha == null ? null : 'fecha_atencion = ?';
    final args = fecha == null ? null : [fecha];

    if (q.isEmpty) {
      final rows = await d.query('atenciones',
          where: where,
          whereArgs: args,
          orderBy: 'fecha_hora_registro DESC',
          limit: limit);
      return rows.map((m) => Atencion.fromMap(m)).toList();
    }
    // Los nombres vienen en mayúsculas y con tildes; SQLite no sabe compararlos
    // sin acentos, así que se filtra acá sobre las filas ya ordenadas.
    final rows = await d.query('atenciones',
        where: where, whereArgs: args, orderBy: 'fecha_hora_registro DESC');
    return rows
        .map((m) => Atencion.fromMap(m))
        .where((a) =>
            norm('${a.nombreEstudiante ?? ''} ${a.numDocumento}').contains(q))
        .take(limit)
        .toList();
  }

  /// Cuántas atenciones hay guardadas, en un día o en total.
  Future<int> contarHistorial({String? fecha}) async {
    final d = await db;
    final r = fecha == null
        ? await d.rawQuery('SELECT COUNT(*) c FROM atenciones')
        : await d.rawQuery(
            'SELECT COUNT(*) c FROM atenciones WHERE fecha_atencion = ?',
            [fecha]);
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<int> contarPendientes() async {
    final d = await db;
    final r =
        await d.rawQuery(
            'SELECT COUNT(*) c FROM atenciones WHERE enviado=0 AND rechazada=0');
    return Sqflite.firstIntValue(r) ?? 0;
  }
}
