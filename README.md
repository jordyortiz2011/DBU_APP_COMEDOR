# Comedor Universitario — DBU UNAP (app Flutter)

App Android para el **registro de atención** (raciones servidas) del comedor
universitario. Funciona **sin conexión** (SQLite local + cola de envío) y
sincroniza con el sistema web `bienestar_universitario` vía la API móvil
(`api/comedor/*`, token Bearer).

## Requisitos
- Flutter 3.44+ (Dart 3.12+)
- Android 12+ (minSdk 31)

## Configuración del servidor
La app apunta por defecto a:
```
http://192.168.135.222/bienestar_universitario/public/
```
Se puede cambiar desde el **login** (botón "Servidor") o en **Configuración → Servidor**.
La URL debe terminar en `/public/`. Se permite tráfico HTTP en claro
(`usesCleartextTraffic=true`) porque el servidor es HTTP en la red local.

## Ejecutar / compilar
```bash
flutter pub get
flutter run                 # en un dispositivo/emulador conectado
flutter build apk --release # APK de producción → build/app/outputs/flutter-apk/
```

## Flujo de uso
1. **Login** con un usuario del sistema (correo + contraseña). Requiere internet
   la primera vez; luego el mismo usuario puede entrar **offline** en ese equipo.
2. **Actualizar datos** (icono de nube en la barra superior): descarga estudiantes
   matriculados, servicios (horario), sedes asignadas y metas.
3. **Registro**: elige sede/servicio (el servicio se auto-selecciona por la hora),
   escanea el DNI/código con la cámara o el lector, y se registra la ración.
   - Sin conexión, la atención se guarda localmente y se envía sola al reconectar.
   - Envío inmediato con **timeout de 3 s**: si tarda más, queda en cola.
4. **Listado**: atenciones registradas en el equipo con su estado (Enviado / Pendiente).
5. **Configuración**: servidor, horario descargado, última sincronización, versión.

## Arquitectura (`lib/`)
- `config.dart` — constantes, colores (blanco/verde), timeouts.
- `models.dart` — Estudiante, Servicio, Sede, Atencion.
- `util.dart` — uuid, fecha/hora, auto-selección de servicio por hora.
- `services/db.dart` — SQLite (padrón, servicios, sedes, metas, atenciones).
- `services/session.dart` — token, usuario, sedes, URL, verificador de login offline.
- `services/api.dart` — cliente HTTP de `api/comedor/*`.
- `services/sync_service.dart` — envío en segundo plano de la cola + descarga de datos.
- `screens/` — login, home, registro, listado, config, escáner.

## Correspondencia con el backend
| App | Endpoint |
|-----|----------|
| Login | `POST api/comedor/login` |
| Actualizar datos | `GET api/comedor/sync` |
| Enviar atenciones | `POST api/comedor/atenciones` |
| Cerrar sesión | `POST api/comedor/logout` |

Cada atención guarda **usuario**, **fecha/hora de registro** (dispositivo) y el
servidor añade la **fecha/hora de envío**. El origen es `MOVIL` o `MOVIL_OFFLINE`.
