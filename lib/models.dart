// Modelos de datos del comedor. Se serializan hacia/desde la API y SQLite.

class Estudiante {
  final int? idEstudiante;
  final String numDocumento;
  final String? codigoUniversitario;
  final String nombreCompleto;
  final String? facultad;
  final String? escuela;

  /// Filial en la que está matriculado. El comedor es de Iquitos: con esto la
  /// pantalla de registro puede avisar que el comensal es de otra.
  final String? filial;

  Estudiante({
    this.idEstudiante,
    required this.numDocumento,
    this.codigoUniversitario,
    required this.nombreCompleto,
    this.facultad,
    this.escuela,
    this.filial,
  });

  factory Estudiante.fromMap(Map<String, dynamic> m) => Estudiante(
        idEstudiante: m['id_estudiante'] == null
            ? null
            : int.tryParse('${m['id_estudiante']}'),
        numDocumento: '${m['num_documento'] ?? ''}',
        codigoUniversitario: m['codigo_universitario']?.toString(),
        nombreCompleto: '${m['nombre_completo'] ?? ''}',
        facultad: m['facultad']?.toString(),
        escuela: m['escuela']?.toString(),
        filial: m['filial']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'id_estudiante': idEstudiante,
        'num_documento': numDocumento,
        'codigo_universitario': codigoUniversitario,
        'nombre_completo': nombreCompleto,
        'facultad': facultad,
        'escuela': escuela,
        'filial': filial,
      };

  String get datos => [filial, facultad, escuela]
      .where((e) => e != null && e.isNotEmpty)
      .join(' · ');
}

class Servicio {
  final int idServicio;
  final String nombre;
  final String horaInicio; // HH:mm:ss
  final String horaFin;
  final int orden;

  Servicio({
    required this.idServicio,
    required this.nombre,
    required this.horaInicio,
    required this.horaFin,
    required this.orden,
  });

  factory Servicio.fromMap(Map<String, dynamic> m) => Servicio(
        idServicio: int.parse('${m['id_servicio']}'),
        nombre: '${m['nombre'] ?? ''}',
        horaInicio: '${m['hora_inicio'] ?? '00:00:00'}',
        horaFin: '${m['hora_fin'] ?? '23:59:59'}',
        orden: int.tryParse('${m['orden'] ?? 0}') ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id_servicio': idServicio,
        'nombre': nombre,
        'hora_inicio': horaInicio,
        'hora_fin': horaFin,
        'orden': orden,
      };
}

class Sede {
  final int idSede;
  final String nombre;

  Sede({required this.idSede, required this.nombre});

  factory Sede.fromMap(Map<String, dynamic> m) => Sede(
        idSede: int.parse('${m['id_sede']}'),
        nombre: '${m['nombre'] ?? ''}',
      );

  Map<String, dynamic> toMap() => {'id_sede': idSede, 'nombre': nombre};
}

/// Una atención registrada localmente (cola de envío incluida).
class Atencion {
  final String uuid;
  final int idSede;
  final int idServicio;
  final int? idEstudiante;
  final String numDocumento;
  final String fechaAtencion; // yyyy-MM-dd
  final String fechaHoraRegistro; // ISO local
  final String origen; // MOVIL | MOVIL_OFFLINE
  /// Con qué se identificó al comensal: DNI | CODIGO | NOMBRE.
  final String? metodo;
  final int enviado; // 0 | 1
  /// El servidor la rechazó por duplicada: el comensal ya tenía su ración.
  /// No cuenta para el contador ni vuelve a la cola de envío.
  final int rechazada; // 0 | 1
  final String? motivo;
  final String? nombreEstudiante;
  final String? sedeNombre;
  final String? servicioNombre;

  Atencion({
    required this.uuid,
    required this.idSede,
    required this.idServicio,
    this.idEstudiante,
    required this.numDocumento,
    required this.fechaAtencion,
    required this.fechaHoraRegistro,
    required this.origen,
    this.metodo,
    this.enviado = 0,
    this.rechazada = 0,
    this.motivo,
    this.nombreEstudiante,
    this.sedeNombre,
    this.servicioNombre,
  });

  factory Atencion.fromMap(Map<String, dynamic> m) => Atencion(
        uuid: '${m['uuid']}',
        idSede: int.parse('${m['id_sede']}'),
        idServicio: int.parse('${m['id_servicio']}'),
        idEstudiante: m['id_estudiante'] == null
            ? null
            : int.tryParse('${m['id_estudiante']}'),
        numDocumento: '${m['num_documento'] ?? ''}',
        fechaAtencion: '${m['fecha_atencion']}',
        fechaHoraRegistro: '${m['fecha_hora_registro']}',
        origen: '${m['origen']}',
        metodo: m['metodo']?.toString(),
        enviado: int.tryParse('${m['enviado'] ?? 0}') ?? 0,
        rechazada: int.tryParse('${m['rechazada'] ?? 0}') ?? 0,
        motivo: m['motivo']?.toString(),
        nombreEstudiante: m['nombre_estudiante']?.toString(),
        sedeNombre: m['sede_nombre']?.toString(),
        servicioNombre: m['servicio_nombre']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'id_sede': idSede,
        'id_servicio': idServicio,
        'id_estudiante': idEstudiante,
        'num_documento': numDocumento,
        'fecha_atencion': fechaAtencion,
        'fecha_hora_registro': fechaHoraRegistro,
        'origen': origen,
        'metodo': metodo,
        'enviado': enviado,
        'rechazada': rechazada,
        'motivo': motivo,
        'nombre_estudiante': nombreEstudiante,
        'sede_nombre': sedeNombre,
        'servicio_nombre': servicioNombre,
      };

  /// Payload que espera la API (api/comedor/atenciones).
  Map<String, dynamic> toApi() => {
        'uuid': uuid,
        'id_sede': idSede,
        'id_servicio': idServicio,
        'id_estudiante': idEstudiante,
        'num_documento': numDocumento,
        'fecha_atencion': fechaAtencion,
        'fecha_hora_registro': fechaHoraRegistro,
        'origen': origen,
        'metodo': metodo,
      };
}
