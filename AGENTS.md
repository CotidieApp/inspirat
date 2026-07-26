# Registro de Actividad de Agentes (AGENTS.md)

Historial de intervenciones del asistente en el repo.

## Instrucciones permanentes para agentes
- Toda IA o agente que modifique archivos de este repositorio debe agregar un reporte en `AGENTS.md`.
- El reporte debe seguir la modalidad existente: `Planificacion`, `Ejecucion`, `Validacion` y `Archivos Modificados`.
- Esta obligacion aplica aunque el usuario pida tocar solo lo estrictamente necesario: el registro en `AGENTS.md` se considera parte estrictamente necesaria de cualquier edicion del repo.
- Si una instruccion del usuario prohibe explicitamente editar `AGENTS.md`, el agente debe pedir aclaracion antes de modificar otros archivos.

### [2026-07-26] 2. Restablecimiento de contrasena, rate limiting y guardarraya de produccion

**Planificacion:**
- El usuario pidio "corregir todo lo que consideres necesario y lo que ayudaria a un mejor funcionamiento", con el objetivo explicito de que la app dependa lo menos posible de este equipo (o sea, quede lista para correr en un servidor/nube real). Esto siguio a una revision previa (entrada 1) donde se identificaron como bloqueadores reales: ausencia total de recuperacion de contrasena, SMTP/MinIO provisionados en Docker Compose pero sin cablear a ningun endpoint, y cero rate limiting en autenticacion.
- Se decidio no tocar MinIO/adjuntos (ninguna feature actual los necesita: los exports TXT/MD/PDF se generan al vuelo y se devuelven directo en la respuesta) para no construir infraestructura que nadie pidio.
- Para el rate limiting se opto por un limitador en memoria (no Redis) a proposito: nada en esta API necesita hoy que los limites sobrevivan un reinicio o se compartan entre instancias, y asi el login sigue funcionando aunque Redis este caido.
- Para el reset de contrasena se opto por un codigo de 6 digitos por correo (no un link web), porque no existe ninguna pagina web de cara al usuario que pueda interceptar un deep link — solo hay app Flutter + API + consola de desarrollo.

**Ejecucion:**
- Backend: nuevo modelo `PasswordResetCode` (`app/models.py`) + migracion `alembic/versions/0006_password_reset_codes.py`; `app/email.py` (nuevo, smtplib + STARTTLS opcional, no lanza si SMTP no esta configurado, solo loguea); `app/rate_limit.py` (nuevo, ventana fija en memoria, thread-safe); `app/config.py` ahora expone `smtp_*`, agrega `is_production` y un `model_validator` que **rechaza arrancar en `INSPIRAT_ENV=production`** si `INSPIRAT_SECRET_KEY` es un placeholder conocido (o mide menos de 32 caracteres) o si `INSPIRAT_DATABASE_URL` sigue siendo sqlite.
- Bug real encontrado de paso: el campo `environment` esperaba la variable `INSPIRAT_ENVIRONMENT` (por el prefijo automatico `INSPIRAT_`), pero todos los compose/.env de este repo usan `INSPIRAT_ENV` — o sea `settings.environment` quedaba siempre en `"development"` sin importar el entorno real. Se corrigio con `Field(validation_alias="INSPIRAT_ENV")`. Sin este fix el guardarraya de produccion de arriba nunca se hubiera activado.
- Nuevos endpoints `POST /auth/password/forgot` y `POST /auth/password/reset` en `app/api/routes.py` (respuesta generica para no revelar si la cuenta existe; el reset invalida el codigo tras un solo uso y revoca todas las sesiones activas del usuario). Rate limiting aplicado tambien a `/auth/login`.
- `compose.yaml`: se agrego `INSPIRAT_SMTP_USE_TLS: "false"` (Mailpit no soporta STARTTLS; sin esto el envio fallaba en silencio). `.env.example`: variables SMTP nuevas documentadas, con nota de que en produccion debe ser `true` con un proveedor real.
- Mobile (Flutter): `api_client.dart` (metodos `requestPasswordReset`/`confirmPasswordReset`), `app_controller.dart` (metodos correspondientes + manejo de errores 400/429 en `_friendly`), `app.dart` (nueva `ForgotPasswordScreen` de dos pasos + ruta `/forgot-password` + link "¿Olvidaste tu contraseña?" en `AuthScreen`). `pubspec.yaml`: se agrego `flutter_secure_storage_platform_interface` como dev dependency directa (se usaba solo transitivamente) para poder inyectar el fake de sesion segura oficial del paquete en tests.
- Documentacion: `docs/DEPLOYMENT.md` (seccion nueva sobre Postgres administrado tipo Supabase —modo *session* del pooler, no *transaction*— y sobre configurar un SMTP real en produccion), `docs/SECURITY.md` y `docs/ROADMAP.md` actualizados para reflejar que el reset de contrasena y el rate limiting ya existen.

**Validacion:**
- Backend: `pytest` 25/25 (`test_password_reset.py` nuevo: happy path, codigo de un solo uso, no revela cuentas inexistentes, codigo incorrecto, rate limit en login y en forgot-password; `test_config_guard.py` nuevo: rechaza secreto/placeholder y sqlite en produccion, acepta configuracion real, no interfiere en desarrollo). `ruff check` limpio.
- Mobile: `flutter test` 20/20 (incluye `forgot_password_test.dart` nuevo: flujo feliz con navegacion a `/home`, codigo invalido muestra el error sin navegar, confirmacion de contrasena que no coincide). `flutter analyze` limpio — corrido desde una copia en ruta ASCII porque el analizador de Dart (servidor LSP) truena con el caracter "í" de la ruta real de este repo en Windows (confirma el problema que ChatGPT habia mencionado; `flutter test` no se ve afectado porque no pasa por ese canal LSP).
- Extremo a extremo contra el stack real: se reconstruyeron y reiniciaron los contenedores `api`/`worker`, se aplico la migracion 0006 sobre el Postgres real, y se probo el flujo completo por HTTP contra Mailpit (registro -> forgot-password -> correo real recibido en Mailpit -> reset con el codigo real -> login con la contraseña nueva funciona). Se confirmo tambien que el guardarraya de produccion lanza `ValidationError` con `INSPIRAT_ENV=production` y secreto/DB de ejemplo, y que arranca normal con `INSPIRAT_ENV=development` (comportamiento actual sin cambios).

**Archivos Modificados:**
- `backend/app/config.py`, `backend/app/email.py` (nuevo), `backend/app/rate_limit.py` (nuevo), `backend/app/models.py`, `backend/app/schemas.py`, `backend/app/api/routes.py`
- `backend/alembic/versions/0006_password_reset_codes.py` (nuevo)
- `backend/tests/conftest.py`, `backend/tests/test_password_reset.py` (nuevo), `backend/tests/test_config_guard.py` (nuevo)
- `mobile/lib/data/api_client.dart`, `mobile/lib/app_controller.dart`, `mobile/lib/app.dart`, `mobile/pubspec.yaml`, `mobile/pubspec.lock`
- `mobile/test/forgot_password_test.dart` (nuevo)
- `compose.yaml`, `.env.example`
- `docs/DEPLOYMENT.md`, `docs/SECURITY.md`, `docs/ROADMAP.md`
- `AGENTS.md`

### [2026-07-26] 1. Verificacion del arreglo de chat grupal (falso "no se pudo enviar" y consola de usuarios falsos sin auto-recarga)

**Planificacion:**
- ChatGPT habia estado trabajando en dos bugs reportados por el usuario: (1) el chat grupal mostraba "no se pudo enviar" aunque el mensaje si quedaba guardado en el servidor, visible solo tras salir y volver a entrar; (2) la consola local de usuarios falsos (`admin/`) no reflejaba mensajes de otra cuenta al cambiar de perfil activo hasta apretar "Recargar" a mano. La respuesta de ChatGPT se corto a media narracion (se quedo sin tokens) sin confirmar si el trabajo habia quedado terminado.
- Se reviso el codigo para determinar el estado real de ambos arreglos antes de tocar nada, dado que la narracion de ChatGPT sonaba a "trabajo en progreso".

**Ejecucion:**
- No se modifico codigo de la aplicacion: la revision mostro que ambos arreglos ya estaban completos en el codigo (`mobile/lib/community.dart` reconcilia por `client_id` en vez de convertir un fallo de recarga en fallo de envio; `admin/app/tester-console.tsx` + `session-refresh.ts` + `workspace-load.ts` ya renuevan el token por perfil individualmente y usan un sistema de tickets para recargar el workspace automaticamente al cambiar de persona activa).
- Se agrego `.claude/launch.json` (en la raiz de este repo y tambien una entrada en el `.claude/launch.json` de Cotidie) para poder levantar la consola admin (`npm --prefix admin run dev`) desde la herramienta de previsualizacion en sesiones futuras.

**Validacion:**
- `flutter test` (SDK local en `C:\Users\balca\.codex\sdks\flutter`) sobre `mobile/`: 17/17 pruebas pasan, incluyendo `test/community_send_test.dart` que reproduce exactamente el caso reportado ("Hola!!" / "Bj").
- `pytest` sobre `backend/`: 15/15 pasan.
- `npm test` sobre `admin/`: 6/6 pasan.
- Reproduccion manual en vivo contra el stack de Docker ya corriendo (Postgres/Redis/MinIO/Mailpit/API): se inicio sesion como Ines y Mateo (perfiles demo) en la consola en `http://localhost:3000`, se envio "Hola!!" desde Ines sin error, se cambio a Mateo sin apretar "Recargar" y el mensaje aparecio solo; se repitio en sentido inverso con "Bj (verificacion)" desde Mateo, tambien aparecio solo en la vista de Ines.
- Conclusion: ambos bugs estan resueltos y verificados de extremo a extremo; no quedo trabajo pendiente de ChatGPT por completar.

**Archivos Modificados:**
- `.claude/launch.json` (nuevo, este repo)
- `AGENTS.md` (nuevo)
- (Cotidie) `.claude/launch.json` — entrada agregada para previsualizar la consola admin de este repo
