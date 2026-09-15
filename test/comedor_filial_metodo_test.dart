// Base local del comedor con filial del alumno y método de registro.
// Corre contra SQLite real (sqflite_common_ffi), no contra un doble.
import 'package:dbu_comedor/models.dart';
import 'package:dbu_comedor/services/db.dart';
import 'package:dbu_comedor/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Base nueva: este archivo cubre la instalación desde cero (onCreate).
    await deleteDatabase(p.join(await getDatabasesPath(), 'comedor.db'));
  });

  test('el padrón local guarda y devuelve la filial', () async {
    await AppDb.instance.reemplazarEstudiantes([
      Estudiante(
          idEstudiante: 1,
          numDocumento: '70000001',
          codigoUniversitario: '20201234',
          nombreCompleto: 'GARCIA LOPEZ, JUAN',
          facultad: 'INGENIERIA',
          escuela: 'SISTEMAS',
          filial: 'CONTAMANA'),
      Estudiante(
          idEstudiante: 2,
          numDocumento: '70000002',
          nombreCompleto: 'PEREZ DIAZ, MARIA',
          filial: 'IQUITOS'),
    ]);

    final r = await AppDb.instance.buscarEstudiantes('70000001', 'dni');
    expect(r.single.filial, 'CONTAMANA');
    // La filial entra en la línea de datos que se muestra al registrar.
    expect(r.single.datos, contains('CONTAMANA'));
  });

  test('la atención guarda el método y lo manda en el payload', () async {
    final a = Atencion(
      uuid: 'uuid-test-1',
      idSede: 1,
      idServicio: 2,
      idEstudiante: 1,
      numDocumento: '70000001',
      fechaAtencion: '2026-09-11',
      fechaHoraRegistro: '2026-09-11T12:00:00.000',
      origen: 'MOVIL_OFFLINE',
      metodo: 'CODIGO',
      nombreEstudiante: 'GARCIA LOPEZ, JUAN',
    );
    await AppDb.instance.insertarAtencion(a);

    final pend = await AppDb.instance.pendientes();
    expect(pend.single.metodo, 'CODIGO');
    expect(pend.single.toApi()['metodo'], 'CODIGO');

    final hist = await AppDb.instance.historial();
    expect(hist.single.metodo, 'CODIGO');
  });

  test('una atención sin método no rompe nada', () async {
    await AppDb.instance.insertarAtencion(Atencion(
      uuid: 'uuid-test-2',
      idSede: 1,
      idServicio: 3,
      numDocumento: '70000002',
      fechaAtencion: '2026-09-11',
      fechaHoraRegistro: '2026-09-11T12:05:00.000',
      origen: 'MOVIL',
    ));
    final sinMetodo = (await AppDb.instance.historial())
        .firstWhere((x) => x.uuid == 'uuid-test-2');
    expect(sinMetodo.metodo, isNull);
    expect(sinMetodo.toApi()['metodo'], isNull);
  });

  test('la comparación de filial ignora mayúsculas y tildes', () {
    // Es la regla del registro: se pregunta cuando la filial no es Iquitos.
    bool esOtra(String f) => norm(f).isNotEmpty && norm(f) != norm('IQUITOS');

    expect(esOtra('IQUITOS'), isFalse);
    expect(esOtra('Iquitos'), isFalse);
    expect(esOtra(''), isFalse); // sin dato no se molesta al operador
    expect(esOtra('CONTAMANA'), isTrue);
    expect(esOtra('DATEM DEL MARAÑON'), isTrue);
    expect(esOtra('YURIMAGUAS'), isTrue);
  });
}
