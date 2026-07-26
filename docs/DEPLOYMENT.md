# Despliegue y copias

## VPS

1. Instala Docker Engine y el complemento Compose en un VPS actualizado.
2. Apunta el dominio al VPS y abre solo 22, 80 y 443.
3. Copia `.env.example` a `.env`; reemplaza todos los secretos por valores
   aleatorios de al menos 32 bytes y configura `INSPIRAT_DOMAIN`.
4. Ejecuta `docker compose -f compose.prod.yaml up -d --build`.
5. Verifica `https://dominio/health` y ejecuta migraciones en una ventana de
   mantenimiento: `docker compose -f compose.prod.yaml exec api alembic upgrade head`.
6. No publiques puertos de PostgreSQL, Redis ni MinIO.

Caddy obtiene y renueva TLS automáticamente. Restringe CORS al dominio real,
rota secretos tras incidentes y actualiza imágenes con revisión y copia previa.

Con `INSPIRAT_ENV=production` la API se niega a arrancar si `INSPIRAT_SECRET_KEY`
es un valor de ejemplo (o de menos de 32 caracteres) o si `INSPIRAT_DATABASE_URL`
sigue apuntando a sqlite. Es un candado, no un sustituto de revisar el `.env`.

## Postgres administrado (Supabase u otro)

No hace falta el contenedor `postgres` de este repo: cualquier Postgres
alcanzable sirve. Para Supabase, apunta `INSPIRAT_DATABASE_URL` a la cadena de
conexión del **pooler en modo *session*** (no *transaction*: SQLAlchemy
mantiene sesiones largas y ese modo rompe con prepared statements), con
`sslmode=require`, por ejemplo:

```text
INSPIRAT_DATABASE_URL=postgresql+psycopg://postgres.xxxx:CONTRASENA@aws-0-region.pooler.supabase.com:5432/postgres?sslmode=require
```

Corre `alembic upgrade head` igual que en el VPS. Ganas backups automáticos y
point-in-time recovery gestionados; sigues siendo responsable de rotar la
contraseña y de no exponer la cadena de conexión.

## Correo saliente real

Mailpit es solo para desarrollo. En producción configura un proveedor SMTP real
(Resend, Postmark, tu propio servidor) en el `.env`:

```text
INSPIRAT_SMTP_HOST=smtp.tu-proveedor.com
INSPIRAT_SMTP_PORT=587
INSPIRAT_SMTP_USE_TLS=true
INSPIRAT_SMTP_USERNAME=...
INSPIRAT_SMTP_PASSWORD=...
INSPIRAT_SMTP_FROM_EMAIL=no-reply@tu-dominio.com
```

Sin esto, `POST /auth/password/forgot` sigue respondiendo con éxito (para no
revelar si la cuenta existe) pero el correo con el código nunca sale; queda
registrado como `smtp_send_failed` o `smtp_not_configured` en los logs.

## Copia y restauración

Ejemplo de copia consistente:

```sh
docker compose -f compose.prod.yaml exec -T postgres \
  pg_dump -U inspirat -Fc inspirat > inspirat-$(date +%F).dump
```

Copia también el volumen/objetos de MinIO. Cifra los archivos antes de enviarlos
fuera del VPS. Prueba cada trimestre la restauración en un entorno aislado:

```sh
createdb inspirat_restore
pg_restore --clean --if-exists -d inspirat_restore copia.dump
```

Una copia no probada no se considera recuperable.

