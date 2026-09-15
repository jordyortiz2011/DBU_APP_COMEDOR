import 'dart:io';

import 'package:dbu_comedor/config.dart';
import 'package:dbu_comedor/models.dart';
import 'package:dbu_comedor/screens/registro_screen.dart';
import 'package:dbu_comedor/services/db.dart';
import 'package:dbu_comedor/services/session.dart';
import 'package:dbu_comedor/services/sync_service.dart';
import 'package:dbu_comedor/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Metas por sede y su cascada (fila diaria → plantilla del período → defecto),
/// que es lo que decide el "X / meta" del registro cuando no hay conexión.
void main() {
  late String ruta;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ruta = '${await databaseFactory.getDatabasesPath()}/comedor.db';
    final f = File(ruta);
    if (f.existsSync()) f.deleteSync();

    // Instalación vieja (esquema v1 completo): metas con clave (fecha,
    // servicio), sin sede y sin plantilla del período.
    final vieja = await databaseFactory.openDatabase(ruta,
        options: OpenDatabaseOptions(version: 1));
    await vieja.execute('''
      CREATE TABLE estudiantes (
        num_documento TEXT PRIMARY KEY, id_estudiante INTEGER,
        codigo_universitario TEXT, nombre_completo TEXT,
        facultad TEXT, escuela TEXT
      )''');
    await vieja.execute('''
      CREATE TABLE servicios (
        id_servicio INTEGER PRIMARY KEY, nombre TEXT,
        hora_inicio TEXT, hora_fin TEXT, orden INTEGER
      )''');
    await vieja
        .execute('CREATE TABLE sedes (id_sede INTEGER PRIMARY KEY, nombre TEXT)');
    await vieja.execute('''
      CREATE TABLE metas (
        fecha TEXT, id_servicio INTEGER, raciones INTEGER, menu TEXT,
        PRIMARY KEY (fecha, id_servicio)
      )''');
    await vieja.execute('''
      CREATE TABLE atenciones (
        uuid TEXT PRIMARY KEY,
        id_sede INTEGER, id_servicio INTEGER, id_estudiante INTEGER,
        num_documento TEXT, fecha_atencion TEXT, fecha_hora_registro TEXT,
        origen TEXT, enviado INTEGER DEFAULT 0,
        nombre_estudiante TEXT, sede_nombre TEXT, servicio_nombre TEXT
      )''');
    await vieja.execute(
        'CREATE INDEX idx_atn_dia ON atenciones(id_sede,id_servicio,fecha_atencion)');

    await vieja.insert('metas',
        {'fecha': '2026-08-20', 'id_servicio': 2, 'raciones': 919});
    // Una atención ya registrada y sin enviar: la migración no debe perderla.
    await vieja.insert('atenciones', {
      'uuid': 'previa-1',
      'id_sede': 1,
      'id_servicio': 2,
      'num_documento': '12345678',
      'fecha_atencion': '2026-08-20',
      'fecha_hora_registro': '2026-08-20T12:00:00',
      'origen': 'MOVIL_OFFLINE',
      'enviado': 0,
    });
    await vieja.close();
  });

  test('la migración deja las metas por sede, la plantilla y el rechazo',
      () async {
    final d = await AppDb.instance.db; // dispara onUpgrade
    expect(await d.getVersion(), 4);

    final cols = await d.rawQuery('PRAGMA table_info(metas)');
    expect(cols.map((c) => c['name']).toList(), contains('id_sede'));

    final colsAtn = await d.rawQuery('PRAGMA table_info(atenciones)');
    final nombres = colsAtn.map((c) => c['name']).toList();
    // 'metodo' llegó en la v4: con qué se identificó al comensal.
    expect(nombres, containsAll(['rechazada', 'motivo', 'metodo']));

    // Y la filial del alumno, que es la que dispara el aviso de otra sede.
    final colsEst = await d.rawQuery('PRAGMA table_info(estudiantes)');
    expect(colsEst.map((c) => c['name']).toList(), contains('filial'));

    final tablas = await d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='metas_config'");
    expect(tablas, isNotEmpty);

    // Lo que el operador ya había registrado sigue en la cola de envío.
    expect(await AppDb.instance.contarPendientes(), 1);
  });

  test('cada sede conserva su propia meta del mismo día y servicio', () async {
    await AppDb.instance.reemplazarSedes([
      Sede(idSede: 1, nombre: 'Iquitos'),
      Sede(idSede: 2, nombre: 'Zungarococha'),
    ]);
    await AppDb.instance.reemplazarServicios([
      Servicio(
          idServicio: 1,
          nombre: 'Desayuno',
          horaInicio: '05:00:00',
          horaFin: '10:29:59',
          orden: 1),
      Servicio(
          idServicio: 2,
          nombre: 'Almuerzo',
          horaInicio: '10:30:00',
          horaFin: '15:59:59',
          orden: 2),
      Servicio(
          idServicio: 3,
          nombre: 'Cena',
          horaInicio: '16:00:00',
          horaFin: '21:00:00',
          orden: 3),
    ]);
    // Tal cual llegan de api/comedor/sync: los valores vienen como texto.
    await AppDb.instance.reemplazarMetas([
      {
        'fecha': '2026-08-20',
        'id_sede': '1',
        'id_servicio': '2',
        'raciones': '777',
        'menu': 'arroz con pollo',
      },
      {
        'fecha': '2026-08-20',
        'id_sede': '2',
        'id_servicio': '2',
        'raciones': '553',
        'menu': null,
      },
    ]);

    expect(await AppDb.instance.metaDe('2026-08-20', 1, 2), 777);
    expect(await AppDb.instance.metaDe('2026-08-20', 2, 2), 553);
  });

  test('sin fila diaria manda la plantilla del período', () async {
    await AppDb.instance.reemplazarMetasConfig([
      {'id_sede': 1, 'id_servicio': 2, 'raciones': 800},
      {'id_sede': 2, 'id_servicio': 2, 'raciones': 553},
    ]);

    // Día futuro sin meta generada todavía: cae en la plantilla de cada sede.
    expect(await AppDb.instance.metaDe('2026-09-15', 1, 2), 800);
    expect(await AppDb.instance.metaDe('2026-09-15', 2, 2), 553);
    // La fila diaria sigue mandando sobre la plantilla.
    expect(await AppDb.instance.metaDe('2026-08-20', 1, 2), 777);
    // Servicio que la plantilla no cubre: valor por defecto.
    expect(await AppDb.instance.metaDe('2026-08-20', 1, 3),
        AppConfig.racionesDefecto);
  });

  test('el menú del día sale solo de la fila diaria de esa sede', () async {
    expect(await AppDb.instance.menuDe('2026-08-20', 1, 2), 'arroz con pollo');
    expect(await AppDb.instance.menuDe('2026-08-20', 2, 2), isNull);
    expect(await AppDb.instance.menuDe('2026-09-15', 1, 2), isNull);
  });

  test('la plantilla se lista con los nombres de sede y servicio', () async {
    final filas = await AppDb.instance.plantillaMetas();
    expect(filas.length, 2);
    expect(filas.first['sede'], 'Iquitos');
    expect(filas.first['servicio'], 'Almuerzo');
    expect(filas.first['raciones'], 800);
  });

  test('descargar de nuevo reemplaza la plantilla, no la acumula', () async {
    await AppDb.instance.reemplazarMetasConfig([
      {'id_sede': 1, 'id_servicio': 2, 'raciones': 900},
    ]);
    final filas = await AppDb.instance.plantillaMetas();
    expect(filas.length, 1);
    expect(await AppDb.instance.metaDe('2026-09-15', 1, 2), 900);
    // La sede que ya no está en la plantilla vuelve al defecto.
    expect(await AppDb.instance.metaDe('2026-09-15', 2, 2),
        AppConfig.racionesDefecto);
  });

  group('comensal que ya pasó', () {
    test('encuentra la ración previa aunque haya sido en OTRA sede', () async {
      // La sembrada en la base v1: sede 1, servicio 2, 2026-08-20, doc 12345678.
      final previo =
          await AppDb.instance.registroPrevio(2, '2026-08-20', '12345678');
      expect(previo, isNotNull);
      expect(previo!.idSede, 1);
      // El operador está atendiendo en Zungarococha y aun así lo detecta: si se
      // filtrara por sede, el comensal repetiría yendo al otro comedor.
      expect(previo.numDocumento, '12345678');
    });

    test('no confunde otro servicio, otra fecha ni otro documento', () async {
      expect(await AppDb.instance.registroPrevio(1, '2026-08-20', '12345678'),
          isNull);
      expect(await AppDb.instance.registroPrevio(2, '2026-08-21', '12345678'),
          isNull);
      expect(await AppDb.instance.registroPrevio(2, '2026-08-20', '99999999'),
          isNull);
    });

    test('trae sede, fecha y hora para poder explicárselo al comensal',
        () async {
      await AppDb.instance.insertarAtencion(Atencion(
        uuid: 'con-datos',
        idSede: 2,
        idServicio: 3,
        numDocumento: '44556677',
        fechaAtencion: '2026-08-20',
        fechaHoraRegistro: '2026-08-20T12:04:31',
        origen: 'MOVIL',
        nombreEstudiante: 'PÉREZ LÓPEZ, Ana',
        sedeNombre: 'Zungarococha',
        servicioNombre: 'Cena',
      ));

      final previo =
          await AppDb.instance.registroPrevio(3, '2026-08-20', '44556677');
      expect(previo!.sedeNombre, 'Zungarococha');
      expect(previo.fechaAtencion, '2026-08-20');
      expect(horaActual(DateTime.parse(previo.fechaHoraRegistro)), '12:04:31');
      expect(fechaCorta(previo.fechaAtencion), '20/08/2026');
    });
  });

  group('buscador del listado', () {
    test('filtra por nombre sin importar mayúsculas ni tildes', () async {
      for (final termino in ['pérez', 'perez', 'PEREZ', 'lópez', 'lopez']) {
        final r = await AppDb.instance.historial(buscar: termino);
        expect(r.length, 1, reason: 'buscando "$termino"');
        expect(r.first.numDocumento, '44556677');
      }
      expect((await AppDb.instance.historial(buscar: 'ANA')).length, 1);
    });

    test('filtra por documento', () async {
      final r = await AppDb.instance.historial(buscar: '4455');
      expect(r.length, 1);
      expect(r.first.nombreEstudiante, 'PÉREZ LÓPEZ, Ana');
    });

    test('sin coincidencias devuelve vacío, y sin filtro devuelve todo',
        () async {
      expect(await AppDb.instance.historial(buscar: 'nadie'), isEmpty);
      expect((await AppDb.instance.historial()).length,
          await AppDb.instance.contarHistorial());
    });
  });

  group('ración que el servidor rechaza por duplicada', () {
    test('previoDe separa el duplicado real de la idempotencia por uuid', () {
      expect(previoDe({'estado': 'ok'}), isNull);
      // 'duplicado' sin 'previo' es el mismo envío repetido: la ración vale.
      expect(previoDe({'estado': 'duplicado'}), isNull);
      expect(previoDe({'estado': 'duplicado', 'previo': null}), isNull);

      final p = previoDe({
        'estado': 'duplicado',
        'previo': {'sede': 'Iquitos', 'fecha': '2026-08-20', 'hora': '12:04:31'}
      });
      expect(p, isNotNull);
      expect(p!['sede'], 'Iquitos');
    });

    test('el motivo dice dónde y cuándo fue la ración anterior', () {
      expect(
          motivoDuplicado(
              {'sede': 'Iquitos', 'fecha': '2026-08-20', 'hora': '12:04:31'}),
          'Ya registrada: Iquitos · 20/08/2026 · 12:04:31');
      expect(motivoDuplicado({}), 'Ya tenía su ración de este servicio.');
    });

    test('deja de contar, sale de la cola y queda en el historial', () async {
      await AppDb.instance.insertarAtencion(Atencion(
        uuid: 'rechazable',
        idSede: 1,
        idServicio: 1,
        numDocumento: '11112222',
        fechaAtencion: '2026-08-25',
        fechaHoraRegistro: '2026-08-25T08:00:00',
        origen: 'MOVIL',
        nombreEstudiante: 'RAMOS DÍAZ, Luis',
      ));
      expect(await AppDb.instance.conteoDia(1, 1, '2026-08-25'), 1);
      final pendientesAntes = await AppDb.instance.contarPendientes();

      await AppDb.instance.marcarRechazada(
          'rechazable', 'Ya registrada: Iquitos · 25/08/2026 · 07:10:00');

      // Lo que el usuario reportó: el contador NO debe sumarla.
      expect(await AppDb.instance.conteoDia(1, 1, '2026-08-25'), 0);
      expect(await AppDb.instance.contarPendientes(), pendientesAntes - 1);
      expect((await AppDb.instance.pendientes()).any((a) => a.uuid == 'rechazable'),
          isFalse);
      // No fue una ración: no puede bloquear un intento posterior legítimo.
      expect(await AppDb.instance.registroPrevio(1, '2026-08-25', '11112222'),
          isNull);
      // Pero queda a la vista, con el motivo.
      final enHistorial = (await AppDb.instance.historial())
          .firstWhere((a) => a.uuid == 'rechazable');
      expect(enHistorial.rechazada, 1);
      expect(enHistorial.motivo, contains('Iquitos'));
    });

    test('borrarAtencion la saca del todo', () async {
      await AppDb.instance.borrarAtencion('rechazable');
      expect(
          (await AppDb.instance.historial()).any((a) => a.uuid == 'rechazable'),
          isFalse);
    });
  });

  group('listado por día', () {
    test('solo trae las atenciones del día pedido', () async {
      await AppDb.instance.insertarAtencion(Atencion(
        uuid: 'ayer-1',
        idSede: 1,
        idServicio: 2,
        numDocumento: '10101010',
        fechaAtencion: '2026-08-19',
        fechaHoraRegistro: '2026-08-19T12:30:00',
        origen: 'MOVIL',
        nombreEstudiante: 'AYER PÉREZ, Juan',
      ));
      await AppDb.instance.insertarAtencion(Atencion(
        uuid: 'hoy-1',
        idSede: 1,
        idServicio: 2,
        numDocumento: '20202020',
        fechaAtencion: '2026-08-20',
        fechaHoraRegistro: '2026-08-20T12:30:00',
        origen: 'MOVIL',
        nombreEstudiante: 'HOY GARCÍA, Ana',
      ));

      final ayer = await AppDb.instance.historial(fecha: '2026-08-19');
      expect(ayer.map((a) => a.uuid), contains('ayer-1'));
      expect(ayer.map((a) => a.uuid), isNot(contains('hoy-1')));

      expect(await AppDb.instance.contarHistorial(fecha: '2026-08-19'), 1);
      // Un día sin nada no rompe: devuelve vacío.
      expect(await AppDb.instance.historial(fecha: '2020-01-01'), isEmpty);
      expect(await AppDb.instance.contarHistorial(fecha: '2020-01-01'), 0);
    });

    test('el buscador trabaja dentro del día elegido', () async {
      // 'garcia' existe, pero el 19 no.
      expect(
          await AppDb.instance.historial(fecha: '2026-08-19', buscar: 'garcia'),
          isEmpty);
      final enSuDia =
          await AppDb.instance.historial(fecha: '2026-08-20', buscar: 'garcia');
      expect(enSuDia.length, 1);
      expect(enSuDia.first.uuid, 'hoy-1');
    });

    test('sin día sigue trayendo todo', () async {
      final todo = await AppDb.instance.historial();
      expect(todo.map((a) => a.uuid), containsAll(['ayer-1', 'hoy-1']));
      expect(await AppDb.instance.contarHistorial(), todo.length);
    });
  });

  group('fecha y hora que ve el operador', () {
    test('la fecha larga va en español', () {
      expect(fechaLarga(DateTime(2026, 8, 20)), 'jueves 20 de agosto de 2026');
      expect(fechaLarga(DateTime(2026, 1, 4)), 'domingo 4 de enero de 2026');
    });

    test('fechaCorta convierte el formato de la base al de pantalla', () {
      expect(fechaCorta('2026-08-20'), '20/08/2026');
    });

    test('la hora se muestra con dos dígitos', () {
      expect(horaActual(DateTime(2026, 8, 20, 9, 5, 3)), '09:05:03');
    });

    test('el servicio se deduce de la hora del dispositivo', () {
      final servicios = [
        Servicio(
            idServicio: 1,
            nombre: 'Desayuno',
            horaInicio: '05:00:00',
            horaFin: '10:29:59',
            orden: 1),
        Servicio(
            idServicio: 2,
            nombre: 'Almuerzo',
            horaInicio: '10:30:00',
            horaFin: '15:59:59',
            orden: 2),
        Servicio(
            idServicio: 3,
            nombre: 'Cena',
            horaInicio: '16:00:00',
            horaFin: '21:00:00',
            orden: 3),
      ];
      int idA(int h, int m) =>
          servicioActual(servicios, DateTime(2026, 8, 20, h, m))!.idServicio;

      expect(idA(7, 0), 1);
      expect(idA(10, 29), 1);
      expect(idA(10, 30), 2); // cruce desayuno → almuerzo
      expect(idA(15, 59), 2);
      expect(idA(16, 0), 3);
      expect(idA(23, 30), 3); // fuera de todo rango: el último
      expect(idA(3, 0), 1); // antes del primero: el primero
    });
  });

  // Va último: deja la base sin sedes ni servicios y las repone.
  //
  // El trabajo contra SQLite va dentro de tester.runAsync porque testWidgets
  // corre en una zona de async simulado, donde las futures de E/S reales nunca
  // completan (el test se cuelga).
  testWidgets('la descarga refresca la pantalla sin reiniciar la app',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final key = GlobalKey<RegistroScreenState>();

    await tester.runAsync(() async {
      await Session.instance.init();
      // Dispositivo recién instalado: todavía no se descargó nada.
      await AppDb.instance.reemplazarSedes([]);
      await AppDb.instance.reemplazarServicios([]);
      // El pumpWidget también va acá: initState dispara la carga desde SQLite,
      // y fuera de runAsync sus timers internos quedan colgados.
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: RegistroScreen(key: key))));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.textContaining('No hay datos locales'), findsOneWidget);
    expect(find.text('Atención del Comedor'), findsNothing);

    await tester.runAsync(() async {
      // Llega la descarga a la base local...
      await AppDb.instance.reemplazarSedes([Sede(idSede: 1, nombre: 'Iquitos')]);
      await AppDb.instance.reemplazarServicios([
        Servicio(
            idServicio: 2,
            nombre: 'Almuerzo',
            horaInicio: '00:00:00',
            horaFin: '23:59:59',
            orden: 2),
      ]);
      // ...y Home avisa a la pantalla. Esto es lo que faltaba y obligaba a
      // cerrar y volver a abrir la app.
      await key.currentState!.recargar();
    });
    await tester.pump();

    expect(find.text('Atención del Comedor'), findsOneWidget);
    expect(find.textContaining('No hay datos locales'), findsNothing);
    expect(find.textContaining('Iquitos'), findsWidgets);

    // Desmonta la pantalla para que su reloj de 1 s no quede pendiente.
    await tester.pumpWidget(const SizedBox());
  });

  // Con el teclado abierto el alto útil se parte al medio y el mensaje del
  // resultado, que va debajo del campo, quedaba tapado.
  testWidgets('con el teclado abierto el resultado queda a la vista',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    SyncService.instance.enLinea.value = false; // registra offline, sin red

    await tester.runAsync(() async {
      await Session.instance.init();
      await AppDb.instance.reemplazarSedes([Sede(idSede: 1, nombre: 'Iquitos')]);
      await AppDb.instance.reemplazarServicios([
        Servicio(
            idServicio: 2,
            nombre: 'Almuerzo',
            horaInicio: '00:00:00',
            horaFin: '23:59:59',
            orden: 2),
      ]);
      await AppDb.instance.reemplazarEstudiantes([
        Estudiante(numDocumento: '55667788', nombreCompleto: 'SOTO VEGA, Rosa'),
      ]);

      // 320 px de teclado sobre la pantalla de prueba de 600: quedan 280.
      // Se copia el MediaQuery real y solo se pisa viewInsets; construir uno
      // vacío deja la pantalla de tamaño cero y no se arma nada.
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: const EdgeInsets.only(bottom: 320)),
          child: child!,
        ),
        home: const Scaffold(body: RegistroScreen()),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // Los pump van FUERA de runAsync (adentro no está permitido).
    await tester.pump();

    // El operador baja hasta el campo y escribe, como en la puerta del comedor.
    // Sin '.first': el finder se evalúa con la lista vacía y '.first' revienta.
    await tester.scrollUntilVisible(find.byType(TextField), 120);
    await tester.enterText(find.byType(TextField).first, '55667788');
    await tester.runAsync(() async {
      // El submit dispara la búsqueda y el registro contra SQLite.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });

    // Deja correr el scroll animado de _verBloqueDocumento.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final mensaje = find.textContaining('Registrado sin conexión');
    expect(mensaje, findsOneWidget);
    expect(tester.getRect(mensaje).bottom, lessThanOrEqualTo(280.0),
        reason: 'el mensaje tiene que quedar por encima del teclado');
    // Y el campo sigue visible para el siguiente comensal, sin scrollear a mano.
    expect(tester.getRect(find.byType(TextField).first).top,
        lessThanOrEqualTo(280.0));

    await tester.pumpWidget(const SizedBox());
    SyncService.instance.enLinea.value = true;
  });
}
