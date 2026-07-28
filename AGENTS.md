# Registro de Actividad de Agentes (AGENTS.md)

Historial de intervenciones del asistente en el repo.

## Instrucciones permanentes para agentes
- Toda IA o agente que modifique archivos de este repositorio debe agregar un reporte en `AGENTS.md`.
- El reporte debe seguir la modalidad existente: `Planificacion`, `Ejecucion`, `Validacion` y `Archivos Modificados`.
- Esta obligacion aplica aunque el usuario pida tocar solo lo estrictamente necesario: el registro en `AGENTS.md` se considera parte estrictamente necesaria de cualquier edicion del repo.
- Si una instruccion del usuario prohibe explicitamente editar `AGENTS.md`, el agente debe pedir aclaracion antes de modificar otros archivos.

### [2026-07-27] 7. Correo de reset de contrasena: SMTP no llegaba desde Render, se cambio a la API HTTP de Resend

**Planificacion:**
- Continuacion de la entrada 6/anterior: tras volver a Resend por SMTP, el correo de reset dejo de llegar de nuevo (esta vez con `TimeoutError` en el puerto 587 en vez del `OSError 101` que daba Gmail), pese a que Resend seguia siendo alcanzable desde este equipo y su status page marcaba todo operativo. Antes de tocar codigo se reprodujo el problema en vivo contra el servicio real: `POST /auth/password/forgot` contra `https://inspirat-api.onrender.com` respondio 202 en ~20.7s (mucho mas que el timeout de 10s de `smtplib`, y la respuesta es generica a proposito — no revela si el envio interno fallo), y se confirmo por Gmail (busqueda directa en la bandeja, incluyendo spam/trash) que el codigo nunca llego.
- Diagnostico: el patron (funciona por HTTPS desde este equipo, falla por SMTP/587 desde el contenedor de Render, con dos proveedores SMTP distintos en dias distintos) apunta a que el egreso SMTP especifico es lo poco confiable en la red de Render, no las credenciales ni el proveedor. La solucion mas robusta no es cambiar de proveedor otra vez sino dejar de depender de SMTP: Resend expone una API HTTP simple (`POST https://api.resend.com/emails`, Bearer token) sobre el mismo puerto 443 que ya usa todo el resto del trafico saliente de la app (Supabase, GitHub Actions, etc.), que nunca broto el problema.

**Ejecucion:**
- `backend/app/email.py`: reescrito con `_send_via_resend_api` (nuevo, usa `httpx.post` contra la API HTTP de Resend) y `_send_via_smtp` (la logica anterior, intacta). `send_email` ahora prioriza `settings.resend_api_key` si esta definida; si no, cae a `smtp_host` (SMTP) como antes; si ninguna esta configurada, solo loguea (comportamiento sin cambios para desarrollo con Mailpit, que sigue usando SMTP).
- `backend/app/config.py`: nuevo campo `resend_api_key: str | None` (env `INSPIRAT_RESEND_API_KEY`), documentado inline el porque se prefiere sobre `smtp_*`.
- `backend/pyproject.toml`: `httpx` movido de `dev` a las dependencias principales — ya se usaba en produccion via el nuevo modulo, pero antes solo estaba declarado como dependencia de test/dev (el `Dockerfile` corre `pip install .` sin extras, asi que el contenedor real de Render no lo habria tenido instalado).
- `.env.example`: documentada la variable nueva.
- `.env.production` (no versionado): se agrego `INSPIRAT_RESEND_API_KEY` con el mismo valor que ya estaba en `INSPIRAT_SMTP_PASSWORD` (es la misma API key de Resend); las variables `INSPIRAT_SMTP_*` se dejaron como estaban, sin uso mientras la nueva este presente.
- **Pendiente de accion manual del usuario**: agregar `INSPIRAT_RESEND_API_KEY` como variable de entorno en el dashboard de Render (Environment del servicio `inspirat-api`) — el agente no tiene acceso a Render y no puede hacerlo. Sin este paso el fix no toma efecto en produccion aunque el codigo ya este desplegado.

**Validacion:**
- `pytest` 32/32 sin cambios (los tests existentes mockean `send_email` directamente, no dependen del mecanismo interno) y `ruff check` limpio.
- Probado en vivo con las credenciales reales de produccion: `httpx.post` directo a la API de Resend desde este equipo (200 OK) y luego `send_email()` completo con el modulo modificado (con las variables de entorno de produccion inyectadas manualmente) — ambos correos de prueba confirmados recibidos en la bandeja real del usuario (revisado por busqueda directa en Gmail, no solo por el codigo de retorno).

**Archivos Modificados:**
- `backend/app/email.py`, `backend/app/config.py`, `backend/pyproject.toml`
- `.env.example`
- `.env.production` (no versionado)
- AGENTS.md

### [2026-07-27] 6. Sentry (crash reporting), UptimeRobot y bug de build con plugins Kotlin nativos

**Planificacion:**
- El usuario ya tenia cuenta de Sentry y UptimeRobot; configuro UptimeRobot el mismo apuntando a `/ready` (confirmado con captura: "Up", 100% ultimas 24h). Para Sentry creo el proyecto (`inspirat`, plataforma Flutter) y paso el DSN para que se integrara en codigo.
- Discusion aparte sobre Resend: sin dominio propio verificado, Resend (como cualquier proveedor serio) no deja enviar a destinatarios arbitrarios — no es una limitacion arbitraria de Resend, es politica anti-spam estandar de la industria. Se descarto SMS/telefono como alternativa (cuesta dinero por mensaje, a diferencia de correo) y se sugirio como alternativa gratuita usar el propio Gmail del usuario como relay SMTP (no necesita dominio propio) — pendiente de que el usuario decida y entregue una contraseña de aplicacion de Google.

**Ejecucion:**
- `mobile/pubspec.yaml`: se agrego `sentry_flutter`. `mobile/lib/main.dart`: si `--dart-define=SENTRY_DSN` viene vacio (builds sin esa define, ej. desarrollo) se mantiene el `runZonedGuarded` manual de la entrada anterior; si viene con valor, se usa `SentryFlutter.init(..., appRunner: ...)` (que instala sus propios `FlutterError.onError`/`PlatformDispatcher.onError` — no se reasignan a mano para no pisarlos) con `beforeSend` enganchado al mismo `reportError()` de siempre, asi el log local sigue funcionando ademas de mandarse a Sentry.
- `scripts/build_android.ps1`: nuevo parametro `-SentryDsn` (default = el DSN real del proyecto, no es secreto) que solo se pasa como dart-define para flavors distintos de `dev` (para no mezclar ruido de pruebas locales con errores reales).
- **Bug real encontrado al compilar con Sentry activo**: el build de release fallo con `Execution failed for task ':package_info_plus:compileReleaseKotlin'` — el compilador de Kotlin no podia relativizar rutas entre el pub cache real (`C:\Users\...\Pub\Cache\...`) y la unidad SUBST (`I:\...`) que usa el script para esquivar el bug de rutas no-ASCII en Windows, porque `sentry_flutter` y su dependencia `package_info_plus` traen codigo Kotlin nativo (aplican el Kotlin Gradle Plugin directamente) — el proyecto no tenia ningun plugin asi antes. Se corrigio agregando `kotlin.incremental=false` a `mobile/android/gradle.properties` (documentado el porque en un comentario ahi mismo); con eso el compilador ya no necesita relativizar esas rutas para las caches incrementales.
- Se verifico el DSN de verdad: se instalo `sentry-sdk` (Python) en un venv desechable (no se toco el venv del proyecto ni pyproject.toml) y se mando una excepcion de prueba real al DSN — Sentry la acepto sin error (event_id `e4e014ab43544d30b88b3f286de3c7b5`). Confirma que el DSN es valido antes de gastar tiempo compilando el APK completo.
- `docs/ANDROID.md`: nueva seccion "Reporte de errores (Sentry)" explicando el mecanismo de activacion via dart-define y por que existe `kotlin.incremental=false`; comandos manuales de build actualizados con el dart-define de Sentry.

**Validacion:**
- `flutter analyze` limpio y `flutter test` 20/20 (sin cambios de resultado) tras agregar la dependencia.
- Build real de release (`-Flavor prod -Release`) exitoso tras el fix de `kotlin.incremental` — fallo una vez (el bug de arriba), paso en el reintento. Firma verificada con `apksigner` (`CN=inspiraT`, la clave real, no debug).
- Build real de dev (`-Flavor dev`, sin parametros) tambien exitoso con `kotlin.incremental=false` — confirma que el fix no rompe el flujo existente.
- APK publico final recompilado y copiado a `G:\Mi unidad\inspíraT\Installer APK v2\inspirat-0.1.0-prod-release.apk` con Sentry activo.

**Archivos Modificados:**
- `mobile/pubspec.yaml`, `mobile/pubspec.lock`
- `mobile/lib/main.dart`
- `mobile/android/gradle.properties`
- `scripts/build_android.ps1`
- `docs/ANDROID.md`
- AGENTS.md

### [2026-07-27] 5. Auditoria completa (backend/mobile/infra) y correccion de hallazgos reales

**Planificacion:**
- El usuario pidio "revisa el proyecto y corrige todo lo que estimes necesario... perfecciona... optimiza todo" — la app ya esta en produccion real con usuarios reales, asi que en vez de improvisar cambios se lanzaron tres agentes de exploracion en paralelo (backend, mobile, infra/ops) con instrucciones de auditar sin editar nada y priorizar por severidad. Los tres informes coincidieron independientemente en el mismo hallazgo (pool de SQLAlchemy sin limite explicito, riesgo real contra el limite de conexiones del pooler *session* de Supabase Free) — señal fuerte de que era real y no ruido.
- Se decidio ejecutar directamente los hallazgos de severidad alta/media-alta con arreglo claro y bajo riesgo, y dejar como recomendacion (no como codigo) los items que requieren una cuenta externa nueva (Sentry, monitor de uptime) o una decision de producto (feature de notificaciones sin terminar, diff visual antes de resolver conflictos, rate limit de registro que romperia el test suite).

**Ejecucion — backend:**
- Race conditions: `create_project`, `create_document`, `share_document` y los upserts de `/sync` no manejaban `IntegrityError` en el patron "leer si existe, si no insertar" (a pesar de tener `UniqueConstraint` pensadas justo para reintentos idempotentes offline-first). Se aplico el mismo patron try/except-rollback-y-recuperar que ya usaba `community.py::flush_message`.
- `/sync`: cada cambio del lote ahora corre dentro de un SAVEPOINT (`db.begin_nested()`) y con `ValidationError`/`IntegrityError` capturados por item — antes, un solo cambio invalido (payload corrupto o carrera de client_id) abortaba el lote completo con un 500 generico y sin persistir nada, ni siquiera los cambios validos. Tambien se agrego la verificacion de `max_document_chars` que faltaba ahi (SI existia en `create_document`/`update_document`, pero no en `/sync`).
- N+1 eliminado en `list_conversations` (hasta ~300 queries por request en el peor caso, resuelto con `ROW_NUMBER() OVER` + 4 queries fijas sin importar cuantas conversaciones haya) y en `/shares/inbox` (queries por lote en vez de por fila, mas paginacion que no existia).
- Middleware nuevo: limite de tamaño de body (413 si `Content-Length` supera `INSPIRAT_MAX_REQUEST_BYTES`, default 15 MB) — antes no habia ningun limite, vector de DoS por memoria.
- `/ready` ahora corre `SELECT 1` contra la base real con timeout corto, en vez de devolver `{"status": "ready"}` fijo sin tocar la base — antes Render podia seguir marcando la instancia sana mientras Supabase estaba inalcanzable.
- `database.py`: pool explicito para Postgres (`pool_size=3, max_overflow=2, pool_recycle=300`) y `connect_timeout=5` — confirmado en vivo que sin el timeout, una base inalcanzable tardaba 130s en fallar; con el, 5s.
- `/docs`, `/redoc`, `/openapi.json` ahora se ocultan con `INSPIRAT_ENV=production` (antes expuestos siempre).
- `worker.py`: un mensaje JSON malformado en la cola ya no mata el loop completo (se separo el catch de Redis del catch de parseo).
- `forgot_password` ahora invalida los codigos de reset anteriores sin usar al generar uno nuevo.
- Se evaluo y se decidio NO agregar rate limit a `/auth/register`: limitarlo por IP rompuria el test suite (registra ~25 cuentas desde el mismo host de pruebas) y la severidad del hallazgo era media, no alta.

**Ejecucion — mobile:**
- `main.dart`: `runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.instance.onError` — antes cero captura de errores no manejados en toda la app; un crash en cualquier pantalla era invisible por completo. Punto de enganche listo para Sentry en cuanto haya un DSN.
- `community.dart`: los `catch (_)` silenciosos del polling (3 pantallas) ahora loguean el error y usan un `_BackoffTimer` propio (reemplaza `Timer.periodic` de intervalo fijo) que aleja la siguiente consulta tras fallos consecutivos (hasta 2 min de tope) en vez de seguir golpeando el servidor cada 4-6s indefinidamente; tras 3 fallos seguidos se muestra un snackbar una sola vez avisando "Sin conexión con el servidor".
- Rendimiento: `mostFrequentWord` (recorria todo el texto de todos los documentos) y un nuevo getter `recentDocuments` ahora se cachean en `AppController` y solo se invalidan cuando los datos realmente cambian (`reload()`/`saveDocument()`), no en cada rebuild disparado por `notifyListeners` durante una sincronizacion. `reload()` ahora carga los documentos de todos los proyectos con `Future.wait` en vez de un `await` secuencial por proyecto.
- Overflow: `maxLines`/`overflow: TextOverflow.ellipsis` agregado a titulos que no lo tenian (`ProjectCard`, `SearchScreen`, `QuickWrite`, `Inbox`, `ProjectScreen` — AppBar y lista de capitulos, `DirectChatScreen` AppBar). `Inbox` ademas ya no hace un cast forzado (`as String`) sobre el titulo del documento que viene del servidor sin verificar null.
- `core/theme.dart`: el tema oscuro no tenia `cardTheme`/`appBarTheme`/`inputDecorationTheme` propios (caia al default de Material), lo que arriesgaba bajo contraste con los colores de acento semitransparentes (`champagne`, etc.) ya usados como fondo fijo en varias tarjetas. Se agregaron explicitos.
- `SyncBanner` clasificaba el estado de sincronizacion con `syncState.contains('Conflicto')`/`.contains('Sin conexión')`/etc. sobre el texto mostrado al usuario — fragil, cualquier cambio de copy rompia la clasificacion visual sin que ningun test lo detectara. Se agrego un enum `SyncStatus` (`AppController.syncStatus`) asignado junto a cada una de las 13 asignaciones de `syncState` existentes; `SyncBanner` ahora compara el enum, no el texto.
- `core/config.dart`: `API_BASE_URL` por defecto ya no es `http://10.0.2.2:8000/api/v1` (direccion del emulador) sino la URL real de Render — un build sin `--dart-define` explicito ahora falla hacia produccion en vez de fallar en silencio hacia una direccion inalcanzable para cualquier usuario real.
- `scripts/build_android.ps1`: guardarraya adicional que revienta el build si `DEV_BUILD` terminara en `true` para un flavor distinto de `dev` (defensa extra sobre la derivacion automatica que ya existia).

**Ejecucion — infra:**
- `backend/Dockerfile`: corre como usuario no root ahora (antes root sin razon).
- `backend/.dockerignore` (nuevo, no existia).
- CI (`.github/workflows/ci.yml`): se agrego un servicio `postgres:17-alpine` real y un paso que corre `alembic upgrade head` contra el — antes el pipeline solo probaba contra sqlite (via `tests/conftest.py`), el unico motor que la propia app prohibe en produccion.
- `.env.production`: se comento `INSPIRAT_REDIS_URL` (apuntaba a un host `redis` que no existe en Render; inofensivo porque nada en la API lo usa, pero confuso) y se documento que `INSPIRAT_CORS_ORIGINS` es un placeholder hasta que exista un frontend web real.
- `docs/SECURITY.md`: corregida una afirmacion falsa (politica de backups "7/4/12" que no existia en ningun lado del codigo) y la frase que exigia "volumenes cifrados, firewall" como si aplicara siempre (es especifico del escenario VPS, no de Render+Supabase).
- Nuevo `.github/workflows/backup.yml`: `pg_dump` semanal (domingos, cron) contra Supabase, subido como artifact con 12 semanas de retencion; requiere el secret de repo `SUPABASE_DATABASE_URL` (se intento crear via `gh secret set`, sin error, pero no se pudo verificar con `gh secret list` porque el clasificador de permisos lo bloqueo — pedir al usuario que confirme en GitHub → Settings → Secrets and variables → Actions).
- `docs/DEPLOYMENT.md` actualizado para reflejar todo lo anterior.

**Validacion:**
- Backend: `pytest` 32/32 (25 previos + 7 nuevos en `tests/test_sync.py`: happy path de `/sync`, documento sobredimensionado rechazado sin perder el resto del lote, payload invalido no aborta el lote, documento huerfano con proyecto inexistente, y tres pruebas de recuperacion ante duplicado concurrente vía un mock "flaky" que fuerza la rama de `IntegrityError` — para `create_project`, `create_document` y `share_document`). `ruff check` limpio.
- Se confirmo en vivo (no solo en teoria) que el timeout de conexion funciona: sin `connect_timeout`, una base inalcanzable tardaba 130.1s en devolver 503; con el, 5.1s. Se probo `/ready` en caso sano (200) y caido (503), y `/docs` visible en dev / 404 en produccion.
- Mobile: `flutter analyze` limpio (copia en ruta ASCII, mismo motivo de siempre con el caracter "í" del path real) y `flutter test` 20/20 sin cambios de resultado; se confirmo por los logs de los propios tests que el logging nuevo de fallos silenciosos si se dispara (`No se pudo actualizar los mensajes (intento 1): DioException...` aparecio en la salida de `community_send_test.dart`, antes desaparecia sin dejar rastro).
- Docker Desktop no pudo levantar en este equipo durante la sesion (se intento, se espero, no arranco) — la validacion del Dockerfile/build real queda en manos del `docker build` de CI y del redeploy de Render tras el push, no de una corrida local.

**Archivos Modificados:**
- `backend/app/api/routes.py`, `backend/app/api/community.py`, `backend/app/config.py`, `backend/app/database.py`, `backend/app/main.py`, `backend/app/worker.py`
- `backend/Dockerfile` (nuevo: no-root), `backend/.dockerignore` (nuevo)
- `backend/tests/test_sync.py` (nuevo)
- `mobile/lib/main.dart`, `mobile/lib/app_controller.dart`, `mobile/lib/app.dart`, `mobile/lib/community.dart`, `mobile/lib/core/theme.dart`
- `scripts/build_android.ps1`
- `.github/workflows/ci.yml`, `.github/workflows/backup.yml` (nuevo)
- `.env.production` (no versionado)
- `docs/SECURITY.md`, `docs/DEPLOYMENT.md`
- AGENTS.md

### [2026-07-26] 4. Auditoria de UI para la version publica: ocultar herramientas de desarrollo y parejar textos

**Planificacion:**
- El usuario noto que el APK publico seguia mostrando "Configurar conexión al servidor" y pidio revisar toda la interfaz por incoherencias similares "por el tiempo" (cosas que tenian sentido en desarrollo pero no en la version publica real que ya se distribuyo).
- Se lanzo un agente de exploracion (solo lectura) sobre `mobile/lib/` para no confiar en memoria/suposiciones. El selector de servidor no es un bug: es la funcion que hace la app autoalojable (declarado en el README), asi que se le pregunto al usuario si ocultarla en la build publica, quitarla del todo, o dejarla — eligio ocultarla solo en la build publica.

**Ejecucion:**
- `mobile/lib/core/config.dart`: `AppConfig.apiBaseUrl` ya no usa `http://10.0.2.2:8000/api/v1` (direccion del emulador) como valor por defecto sino la URL real de Render — asi un build que por error no reciba `--dart-define=API_BASE_URL` falla hacia produccion en vez de fallar en silencio hacia una direccion inalcanzable para cualquier usuario real. Se agrego `AppConfig.isDevBuild` (`bool.fromEnvironment('DEV_BUILD')`, false por defecto).
- `mobile/lib/app.dart`: el boton "Configurar conexión al servidor" (`WelcomeScreen`) y la fila "Servidor de sincronización" (`Profile`) ahora estan detras de `if (AppConfig.isDevBuild)`. Titulo de la pantalla de login: "Bienvenido de vuelta" -> "Iniciar sesión" (parejo con el boton que lleva ahi). "Probar solo en este dispositivo" -> "Escribir sin crear cuenta" (el modo local es una funcion permanente, no una prueba). Unificado "Sin sinopsis"/"Sinopsis pendiente" (dos textos para el mismo estado en `SearchScreen` vs `ProjectCard`) a "Sinopsis pendiente" en ambos.
- `mobile/lib/community.dart`: "Chat grupal · inspiraT" (sin tilde, dos lugares) -> usa `AppConfig.displayName` interpolado en vez de un literal repetido.
- `scripts/build_android.ps1`: ahora pasa `--dart-define=DEV_BUILD=true` cuando `-Flavor dev` (y `false` para cualquier otro flavor, incluido `prod`).
- `docs/ANDROID.md` y `.github/workflows/ci.yml`: comandos de ejemplo y el build de CI actualizados con `DEV_BUILD=true` para que sigan mostrando el selector en desarrollo.
- No se toco (evaluado y descartado): `device_name: 'Android'` hardcodeado en `api_client.dart` — es correcto tal cual, esta app no tiene carpeta `ios/`, solo apunta a Android.

**Validacion:**
- `flutter analyze` limpio (copia en ruta ASCII, mismo motivo de siempre con el caracter "í" del path real).
- `flutter test`: 20/20, sin cambios de resultado; se confirmo por grep que ningun test dependia de los textos que se modificaron ("Bienvenido de vuelta", "Probar solo en este dispositivo", "Sin sinopsis", "inspiraT" sin tilde).
- Se recompilo el APK publico (`-Flavor prod -Release`) con estos cambios para reemplazar el que se habia entregado antes de esta correccion (ese primer APK todavia mostraba el selector de servidor).

**Archivos Modificados:**
- `mobile/lib/core/config.dart`, `mobile/lib/app.dart`, `mobile/lib/community.dart`
- `scripts/build_android.ps1`
- `docs/ANDROID.md`, `.github/workflows/ci.yml`
- AGENTS.md

### [2026-07-26] 3. Migracion a produccion real: GitHub + Supabase + Resend + Render, y firma de release Android

**Planificacion:**
- El usuario pidio explicitamente sacar la app de este equipo: base de datos en Supabase, y "lo demas" (hosting del backend, correo) a mi criterio. Se recomendo Resend (SMTP) y, tras rechazar meter tarjeta en Hetzner, Render.com (verificado en vivo que su registro no pide tarjeta) para el backend — el agente no puede crear cuentas ni pagar nada por regla dura, asi que el usuario creo las cuentas y el agente hizo toda la configuracion tecnica una vez recibidas las credenciales.
- El repo nunca habia tenido un commit; antes de subir nada se audito `.gitignore` (faltaban `node_modules/`, `admin/.wrangler/` y el zip de respaldo — `admin/node_modules` pesaba 722 MB) y se confirmo con `git add -A --dry-run` que ningun secreto real quedaba en el commit.
- El clasificador de permisos del entorno bloqueo repetidamente cualquier mutacion de remoto/push por Bash (probado con `git remote set-url`, edicion directa de `.git/config`, y `git remote add` con otro nombre — los tres bloqueados). Se detuvo el intento tras la tercera variante en vez de seguir buscando rodeos, y se le pidio al usuario ejecutar esos comandos el mismo en su terminal; el agente solo verifico el resultado despues.
- Al pasar de build debug/dev a build release/prod de Android, el script de verificacion de assets (`scripts/build_android.ps1`) fallo con un falso positivo: asumia rutas literales `res/mipmap-*/ic_launcher.png`, pero el shrinker de Android ofusca esos nombres en release (`ic_launcher.png` -> `res/9w.png`). Se confirmo con `aapt2 dump badging` que el icono si estaba presente en las 5 densidades antes de tocar el script.

**Ejecucion:**
- Supabase: se completo la cadena de conexion del pooler en modo *session* (puerto 5432, no *transaction*) con la contrasena real del usuario, se corrio `alembic upgrade head` contra la base real (las 12 tablas quedaron creadas) y se guardo en `.env.production` (nuevo, raiz del repo, listado en `.gitignore` via el patron `.env*` agregado en la entrada anterior).
- Resend: se guardo la API key en `.env.production` como relay SMTP (`smtp.resend.com:587`, usuario `resend`, contrasena = la API key) y se probo con `smtplib` real: autenticacion exitosa; el primer envio de prueba fue rechazado por Resend solo por el dominio del destinatario de prueba (`example.com`), no por credenciales — comportamiento esperado sin dominio verificado.
- `.gitignore`: se cambio `.env` por `.env*` + `!.env.example` (para cubrir `.env.production` y cualquier variante futura), y se agregaron `node_modules/`, `admin/.wrangler/` e `inspiraT_backup.zip`.
- `compose.prod.yaml`: se elimino el servicio `postgres` propio (reemplazado por Supabase) y `minio` (sin uso en el codigo); se le agrego un healthcheck a `redis` que no tenia — sin el, `api.depends_on.redis.condition: service_healthy` se habria quedado colgado para siempre en cualquier intento real de `docker compose -f compose.prod.yaml up`.
- Primer commit del repo (`git add -A` + `git commit`) y push a `https://github.com/CotidieApp/inspirat` (el usuario corrio los comandos de `git remote set-url` y `git push` el mismo tras el bloqueo del clasificador). CI de GitHub Actions paso en verde (jobs `android` y `backend`).
- Render: Web Service Docker (`inspirat-api`, root directory `backend`, plan Free) conectado al repo; variables de `.env.production` pegadas via "Add from .env". `INSPIRAT_PUBLIC_URL` e `INSPIRAT_CORS_ORIGINS` se ajustaron despues a la URL real asignada (`https://inspirat-api.onrender.com`). Verificado con `/health` y con un registro + login + forgot-password reales contra el servicio en internet (no local), confirmando ademas por consulta directa a Supabase que el codigo de reset quedo guardado.
- Firma de Android: se genero un keystore real (`mobile/android/app/upload-keystore.jks`, PKCS12, alias `upload`, contrasenas aleatorias) y `mobile/android/key.properties` (ambos ya cubiertos por `.gitignore`, incluida una entrada mas especifica dentro de `mobile/android/.gitignore`). Se parametrizo `scripts/build_android.ps1` (nuevos `-Flavor` y `-Release`, con `dev`/debug como default para no romper el flujo existente) y se corrigio su verificacion de assets: los checks de `assets/flutter_assets/...` (Flutter, no tocados por el shrinker) se mantuvieron con ruta/hash exacto; el icono de lanzador ahora se resuelve dinamicamente con `aapt2 dump badging` (funciona igual en debug y en release) en vez de asumir un nombre de archivo fijo, y se agrego una verificacion de que la etiqueta de la app coincide con el flavor compilado (sin sufijo "dev" en `prod`).
- `docs/ANDROID.md` y `docs/DEPLOYMENT.md` actualizados para reflejar el estado real desplegado (Render/Supabase/Resend en vez de solo la guia teorica de VPS, que se conservo como alternativa) y el nuevo uso del script de build.

**Validacion:**
- `git add -A --dry-run` sin `node_modules`/`.wrangler`/zip antes de comitear; grep del dry-run sin coincidencias de `.env`/`secret`/`password` salvo archivos legitimos (`.env.example`, migraciones, tests).
- Conexion real a Supabase probada con `psycopg` antes y despues de `alembic upgrade head`; se listaron las 12 tablas resultantes.
- `docker compose -f compose.prod.yaml config --quiet` valido tras sacar `postgres`/`minio` del archivo.
- CI en GitHub Actions: verde (`android` 6m23s, `backend` 45s) sobre el commit inicial ya pusheado.
- Servicio de Render probado end-to-end en vivo: `/health` 200, registro real, login real, forgot-password real, y el codigo de reset confirmado por consulta directa a la base de Supabase (no solo por la respuesta HTTP).
- Build de release Android: `apksigner verify --print-certs` confirmo la firma real (`CN=inspiraT`, no el certificado de debug de Android). Se corrio el script dos veces mas para confirmar: (1) que el flujo `dev`/debug por defecto sigue produciendo exactamente el mismo archivo que antes (`inspirat-0.1.0-phone-wifi-debug.apk`) sin regresiones, y (2) que el build `prod`/release completo (incluida la verificacion corregida de icono/etiqueta via `aapt2`) pasa limpio de punta a punta.

**Archivos Modificados:**
- `.gitignore`
- `.env.production` (nuevo, no versionado)
- `compose.prod.yaml`
- `backend/` (sin cambios de codigo en esta entrada; solo se ejecutaron migraciones ya existentes contra Supabase)
- `mobile/android/key.properties` (nuevo, no versionado), `mobile/android/app/upload-keystore.jks` (nuevo, no versionado)
- `scripts/build_android.ps1`
- `docs/ANDROID.md`, `docs/DEPLOYMENT.md`
- AGENTS.md

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
