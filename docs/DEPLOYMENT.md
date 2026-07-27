# Despliegue y copias

## Estado actual (producción real, desde 2026-07-26)

- **API**: Render (Web Service, plan Free, Docker) — `https://inspirat-api.onrender.com`.
  Repo conectado: `CotidieApp/inspirat`, rama `main`, root directory `backend`.
  El plan Free "duerme" tras inactividad (la primera petición después puede
  tardar ~50s).
- **Base de datos**: Supabase Postgres, pooler en modo *session* (puerto 5432).
- **Correo saliente**: Gmail (`inspiratapp@gmail.com`) vía relay SMTP, con una
  contraseña de aplicación de Google (no la contraseña normal de la cuenta).
  Cambiado desde Resend el 2026-07-27: Resend exige dominio propio verificado
  para enviar a destinatarios que no sean el dueño de la cuenta, y no hay
  presupuesto para comprar uno; Gmail no tiene esa restricción. Límite
  informal de Gmail: ~500 envíos/día, de sobra para el volumen actual.
- **Worker**: no desplegado. Hoy no hace nada real (revisa `app/worker.py`);
  desplegarlo cuando exista una tarea real que procesar.
- **Redis**: no desplegado. Nada en el código de la API lo usa todavía; solo
  lo tocaría el worker.
- Variables reales en `.env.production` (raíz del repo, ignorado por git,
  **no está respaldado en ningún otro lugar** — trátalo como si fuera un
  gestor de contraseñas).

Para agregar el `worker` a Render más adelante: **New + → Background Worker**,
mismo repo/root directory, comando `python -m app.worker`, y ahí sí agregar un
`Key Value` (Redis administrado de Render) o Upstash.

## VPS (alternativa si se abandona Render)

1. Instala Docker Engine y el complemento Compose en un VPS actualizado.
2. Apunta el dominio al VPS y abre solo 22, 80 y 443.
3. Copia `.env.example` a `.env`; reemplaza todos los secretos por valores
   aleatorios de al menos 32 bytes y configura `INSPIRAT_DOMAIN`.
4. Ejecuta `docker compose -f compose.prod.yaml up -d --build`.
5. Verifica `https://dominio/health` y ejecuta migraciones en una ventana de
   mantenimiento: `docker compose -f compose.prod.yaml exec api alembic upgrade head`.

Caddy obtiene y renueva TLS automáticamente. Restringe CORS al dominio real,
rota secretos tras incidentes y actualiza imágenes con revisión y copia previa.
`compose.prod.yaml` ya no incluye Postgres ni MinIO propios (ver más abajo);
solo `api`, `worker`, `redis` y `caddy`.

Con `INSPIRAT_ENV=production` la API se niega a arrancar si `INSPIRAT_SECRET_KEY`
es un valor de ejemplo (o de menos de 32 caracteres) o si `INSPIRAT_DATABASE_URL`
sigue apuntando a sqlite. Es un candado, no un sustituto de revisar el `.env`.

## Postgres administrado (Supabase u otro)

Ya no se corre un contenedor `postgres` propio (se sacó de
`compose.prod.yaml`): cualquier Postgres alcanzable sirve. Para Supabase,
`INSPIRAT_DATABASE_URL` va a la cadena de conexión del **pooler en modo
*session*** (no *transaction*: SQLAlchemy mantiene sesiones largas y ese modo
rompe con prepared statements), con `sslmode=require`, por ejemplo:

```text
INSPIRAT_DATABASE_URL=postgresql+psycopg://postgres.xxxx:CONTRASENA@aws-0-region.pooler.supabase.com:5432/postgres?sslmode=require
```

`alembic upgrade head` corre solo al arrancar el contenedor (ver `Dockerfile`).
Para correrlo a mano contra Supabase desde cualquier máquina con el repo:

```powershell
cd backend
$env:INSPIRAT_DATABASE_URL = "postgresql+psycopg://postgres.xxxx:CONTRASENA@aws-0-region.pooler.supabase.com:5432/postgres?sslmode=require"
.\.venv\Scripts\alembic upgrade head
```

Supabase gestiona backups y point-in-time recovery automáticamente; sigues
siendo responsable de rotar la contraseña y de no exponer la cadena de
conexión (nunca en logs, nunca commiteada).

## Correo saliente real

Mailpit es solo para desarrollo. En producción se usa un proveedor SMTP real
(hoy Gmail, cuenta `inspiratapp@gmail.com`) en el `.env`:

```text
INSPIRAT_SMTP_HOST=smtp.gmail.com
INSPIRAT_SMTP_PORT=587
INSPIRAT_SMTP_USE_TLS=true
INSPIRAT_SMTP_USERNAME=inspiratapp@gmail.com
INSPIRAT_SMTP_PASSWORD=...  # contraseña de aplicacion, no la contraseña normal
INSPIRAT_SMTP_FROM_EMAIL=inspiratapp@gmail.com
```

`INSPIRAT_SMTP_PASSWORD` es una "contraseña de aplicación" generada en
`myaccount.google.com/apppasswords` (requiere verificación en 2 pasos
activada en la cuenta de Google) — no funciona con la contraseña normal de
la cuenta. Si Resend consigue en el futuro un dominio propio verificado,
puede volver a usarse siguiendo el mismo patrón (host/usuario/password
distintos, resto del código sin cambios).

Sin esto, `POST /auth/password/forgot` sigue respondiendo con éxito (para no
revelar si la cuenta existe) pero el correo con el código nunca sale; queda
registrado como `smtp_send_failed` o `smtp_not_configured` en los logs.

## Copia y restauración

**Automatizado**: `.github/workflows/backup.yml` corre un `pg_dump` todos los
domingos (también se puede disparar a mano desde la pestaña Actions →
"Backup semanal de la base de datos" → Run workflow) y sube el resultado como
artifact con 12 semanas de retención. Requiere el secret de repo
`SUPABASE_DATABASE_URL` (Settings → Secrets and variables → Actions) con la
misma cadena de conexión del pooler en modo session. Sin ese secret el
workflow falla explícitamente en vez de fallar en silencio.

Manual, si se vuelve a autoalojar Postgres en un VPS:

```sh
docker compose -f compose.prod.yaml exec -T postgres \
  pg_dump -U inspirat -Fc inspirat > inspirat-$(date +%F).dump
```

Con Supabase (estado actual), además de su PITR gestionado, una copia manual
adicional se saca apuntando `pg_dump` directo a la cadena de conexión:

```sh
pg_dump "postgresql://postgres.xxxx:CONTRASENA@aws-0-region.pooler.supabase.com:5432/postgres?sslmode=require" \
  -Fc > inspirat-$(date +%F).dump
```

Prueba cada trimestre la restauración en un entorno aislado:

```sh
createdb inspirat_restore
pg_restore --clean --if-exists -d inspirat_restore copia.dump
```

Una copia no probada no se considera recuperable.
