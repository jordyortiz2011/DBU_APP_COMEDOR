// Equipos que ya tienen la app: la base local pasa de v3 a v4 sin perder las
// atenciones guardadas. Va en su propio archivo porque AppDb es un singleton y
// cada archivo de test corre en su propio proceso (base nueva desde cero).
import 'package:dbu_comedor/models.dart';
import 'package:dbu_comedor/services/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Esquema tal como lo dejaba la versión 3 (sin filial ni método).
const _v3Estudiantes = '''
  CREATE TABLE estudiantes (
    num_documento TEXT PRIMARY KEY, id_estudiante INTEGER,
    codigo_universitario TEXT, nombre_completo TEXT, facultad TEXT, escuela TEXT
  )''';
const _v3Atenciones = '''
  CREATE TABLE atenciones (
    uuid TEXT PRIMARY KEY,
    id_sede INTEGER, id_servicio INTEGER, id_estudiante INTEGER,
    num_documento TEXT, fecha_atencion TEXT, fecha_hora_registro TEXT,
    origen TEXT, enviado INTEGER DEFAULT 0,
    rechazada INTEGER DEFAULT 0, motivo TEXT,
    nombre_estudiante TEXT, sede_nombre TEXT, servicio_nombre TEXT
  )''';

void main() {
  late String ruta;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ruta = p.join(await getDatabasesPath(), 'comedor.db');
    await deleteDatabase(ruta);

    // Base vieja con una ración ya registrada y pendiente de enviar.
    final vieja = await openDatabase(ruta, version: 3, onCreate: (d, _) async {
      await d.execute(_v3Estudiantes);
      await d.execute(_v3Atenciones);
      await d.execute('''
        CREATE TABLE servicios (id_servicio INTEGER PRIMARY KEY, nombre TEXT,
          hora_inicio TEXT, hora_fin TEXT, orden INTEGER)''');
      await d.execute(
          'CREATE TABLE sedes (id_sede INTEGER PRIMARY KEY, nombre TEXT)');
      await d.execute('''
        CREATE TABLE metas (fecha TEXT, id_sede INTEGER, id_servicio INTEGER,
          raciones INTEGER, menu TEXT, PRIMARY KEY (fecha, id_sede, id_servicio))''');
      await d.execute('''
        CREATE TABLE metas_config (id_sede INTEGER, id_servicio INTEGER,
          raciones INTEGER, PRIMARY KEY (id_sede, id_servicio))''');
    });
    await vieja.insert('estudiantes', {
      'num_documento': '70000009',
      'id_estudiante': 9,
      'nombre_completo': 'VIEJO REGISTRO, PEDRO',
    });
    await vieja.insert('atenciones', {
      'uuid': 'uuid-v3',
      'id_sede': 1,
      'id_servicio': 2,
      'num_documento': '70000009',
      'fecha_atencion': '2026-09-10',
      'fecha_hora_registro': '2026-09-10T12:00:00.000',
      'origen': 'MOVIL_OFFLINE',
      'enviado': 0,
    });
    await vieja.close();
  });

  test('la atención de la v3 sobrevive y queda en cola', () async {
    final pend = await AppDb.instance.pendientes();
    expect(pend.single.uuid, 'uuid-v3');
    expect(pend.single.metodo, isNull); // no se puede deducir lo viejo
  });

  test('después del upgrade se puede guardar filial y método', () async {
    await AppDb.instance.insertarAtencion(Atencion(
      uuid: 'uuid-v4',
      idSede: 1,
      idServicio: 3,
      numDocumento: '70000001',
      fechaAtencion: '2026-09-11',
      fechaHoraRegistro: '2026-09-11T12:00:00.000',
      origen: 'MOVIL',
      metodo: 'DNI',
    ));
    final hist = await AppDb.instance.historial();
    expect(hist.firstWhere((x) => x.uuid == 'uuid-v4').metodo, 'DNI');

    await AppDb.instance.reemplazarEstudiantes([
      Estudiante(
          numDocumento: '70000001',
          nombreCompleto: 'GARCIA LOPEZ, JUAN',
          filial: 'REQUENA'),
    ]);
    final r = await AppDb.instance.buscarEstudiantes('70000001', 'dni');
    expect(r.single.filial, 'REQUENA');
  });
}
