# Consola local de pruebas de inspíraT

Interfaz web para simular distintas personas de la comunidad desde un solo
computador. Permite guardar perfiles locales, iniciar una sesión independiente
para cada uno, crear proyectos y capítulos, consultar usuarios, usar el chat
grupal y enviar mensajes directos o cuentos.

> Esta herramienta es únicamente para desarrollo. Guarda identidades,
> contraseñas y tokens en `localStorage` del navegador. No debe publicarse ni
> exponerse en Internet.

## Requisitos

- Node.js 22.13 o posterior.
- La API de inspíraT ejecutándose, por ejemplo mediante Docker Compose.
- Usuarios de prueba ya registrados en la API.

## Ejecutar

Desde `C:\Users\balca\Documents\inspíraT\admin`:

```powershell
npm install
npm run dev
```

También puede iniciarse con el lanzador incluido:

```powershell
.\start-console.ps1
```

Abre la dirección local que muestre la terminal. La consola utiliza por defecto:

```text
http://localhost:8000/api/v1
```

La dirección puede cambiarse en el encabezado y queda guardada en el navegador.
Si la API usa otro equipo o puerto, asegúrate de que CORS permita el origen local
de la consola.

La mensajería utiliza el contrato comunitario de la API:

- `GET /community/users`
- `GET` y `POST /community/general/messages`
- `POST /community/publish` para envíos múltiples transaccionales
- `GET /community/conversations`
- `GET` y `POST /community/direct/{peer_id}/messages`
- `POST /community/direct/{peer_id}/read`

Cada mensaje enviado lleva un `client_id` UUID para que un reintento no duplique
la publicación.

## Uso recomendado

1. Guarda una persona con un nombre descriptivo, su correo o usuario y su
   contraseña. Para comenzar de inmediato, pulsa **Cargar perfiles demo de Inés
   y Mateo**; ambos usan `InspiraT-demo-2026!`.
2. Pulsa **Iniciar sesión** en su tarjeta.
3. Repite el proceso con todas las identidades de prueba.
4. Alterna la persona activa desde el selector superior.
5. Usa **Taller rápido** para crear contenido y **Compartidos y mensajes** para
   comprobar el chat grupal, mensajes directos y adjuntos.

## Comprobaciones

```powershell
npm run lint
npm test
npm run build
```

## Datos locales

Los perfiles se aíslan mediante claves propias de esta consola en
`localStorage`. Para eliminar todos los datos de prueba guardados en el
navegador, borra los datos del sitio local desde las herramientas del navegador.

Cuando un access token vence, la consola renueva automáticamente la sesión con
el refresh token del perfil correspondiente, guarda los tokens rotados y
reintenta la solicitud una sola vez. Si la renovación falla, limpia únicamente
la sesión afectada y solicita volver a iniciarla.
