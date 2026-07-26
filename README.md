# inspíraT

**inspíraT** es una base real, privada y autoalojable para escribir en Android,
trabajar sin conexión, sincronizar, enviar capítulos y recibir comentarios. El
nombre visible siempre se escribe `inspíraT`; los identificadores técnicos usan
`inspirat`.

## Estado del MVP

Este repositorio implementa el recorrido vertical prioritario:

- cuentas con Argon2id, access tokens breves y refresh tokens rotativos;
- proyectos y capítulos privados, guardado local y papelera lógica;
- cliente Android offline-first con cola persistente y sincronización manual/automática;
- detección de revisión conflictiva que conserva el texto alternativo como versión;
- envío a usuarios con permisos `read`, `comment`, `suggest` o `edit`;
- chat grupal fijado, mensajería directa y publicación transaccional a varios usuarios;
- comentarios anclables, notificaciones y reintentos idempotentes sin duplicados;
- hitos manuales, restauración con copia previa y exportación TXT, Markdown y PDF;
- consola web local para probar varias cuentas desde un solo computador;
- PostgreSQL, Redis, worker, MinIO y Mailpit mediante Docker Compose;
- OpenAPI en `/docs`, logs estructurados, health checks y pruebas de autorización.

La colaboración simultánea, DOCX/EPUB, fichas literarias avanzadas y cifrado
de extremo a extremo están en la hoja de ruta; no se
presentan como funciones terminadas.

## Inicio rápido

Requisitos: Docker Desktop y, para Android, Flutter estable con Android SDK.

```powershell
Copy-Item .env.example .env
docker compose up --build
docker compose exec api python -m app.seed
```

Servicios:

- API: <http://localhost:8000>
- OpenAPI: <http://localhost:8000/docs>
- Mailpit: <http://localhost:8025>
- Consola MinIO: <http://localhost:9001>
- Consola multiusuario de pruebas: ejecutar `.\admin\start-console.ps1` y abrir
  <http://localhost:3000>

Credenciales exclusivamente de desarrollo:

| Usuario | Correo | Contraseña |
|---|---|---|
| `ines` | `ines@example.com` | `InspiraT-demo-2026!` |
| `mateo` | `mateo@example.com` | `InspiraT-demo-2026!` |

### Backend sin Docker

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python -m pip install -e ".[dev]"
$env:INSPIRAT_DATABASE_URL="sqlite:///./inspirat.db"
.\.venv\Scripts\alembic upgrade head
.\.venv\Scripts\uvicorn app.main:app --reload
```

### Android

```powershell
.\scripts\build_android.ps1 `
  -ApiBaseUrl "http://IP_LAN_DEL_PC:8000/api/v1"
```

En teléfono físico, sustituye `10.0.2.2` por la IP LAN del equipo, permite el
puerto 8000 en el firewall y usa la misma red Wi-Fi. Para producción usa
únicamente una URL HTTPS.

El script compila el flavor actual de desarrollo, verifica que el APK contenga
los iconos y fuentes y copia el resultado a
`G:\Mi unidad\inspíraT\Installer APK v2`.

## Comprobaciones

```powershell
.\scripts\test.ps1
cd mobile
flutter analyze
flutter test
```

## Estructura

```text
inspirat/
├── backend/        FastAPI, SQLAlchemy, Alembic y pytest
├── mobile/         Flutter, Riverpod, go_router, Dio y SQLite
├── admin/          consola web local para múltiples usuarios de prueba
├── infra/          Caddy y despliegue
├── docs/           arquitectura, seguridad, compilación y operaciones
├── scripts/        desarrollo, pruebas y datos demo
├── .github/        integración continua
├── compose.yaml
└── compose.prod.yaml
```

Documentación: [arquitectura](docs/ARCHITECTURE.md),
[compilación Android](docs/ANDROID.md), [seguridad y privacidad](docs/SECURITY.md),
[despliegue y copias](docs/DEPLOYMENT.md) y [limitaciones](docs/ROADMAP.md).

## Licencia

Código bajo AGPL-3.0-or-later para preservar las mejoras de despliegues en red.
Los escritos almacenados pertenecen siempre a sus autores y no quedan cubiertos
por la licencia del software.
