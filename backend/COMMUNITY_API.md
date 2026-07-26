# API de comunidad y mensajería

Todas las rutas requieren `Authorization: Bearer <access_token>` y están bajo
`/api/v1/community`.

## Perfiles

`GET /users?q=&limit=50&offset=0`

Devuelve usuarios activos distintos del usuario actual como:

```json
{"id": "uuid", "username": "autora", "display_name": "Autora"}
```

El correo y los datos de autenticación nunca forman parte de esta respuesta.

## Chat general

- `GET /general/messages?limit=50&offset=0`
- `POST /general/messages`

El cuerpo de creación es:

```json
{
  "client_id": "uuid local recomendado",
  "body": "Texto opcional si se adjunta una obra",
  "document_id": "uuid opcional"
}
```

Debe existir texto o `document_id`. El documento debe pertenecer al remitente.
Adjuntarlo aquí es la acción explícita que lo publica: cualquier usuario
autenticado podrá leerlo y comentarlo, pero no editarlo.

`client_id` es opcional por compatibilidad, pero los clientes móviles deben
enviarlo. Repetir exactamente una petición con el mismo `client_id` devuelve el
mismo mensaje sin duplicarlo; reutilizarlo con otro contenido devuelve `409`.

## Publicación múltiple transaccional

`POST /publish` permite publicar una sola operación en el chat general, enviarla
a varios usuarios, o ambas cosas:

```json
{
  "client_id": "uuid estable y obligatorio para toda la operación",
  "body": "Texto opcional si existe document_id",
  "document_id": "uuid opcional",
  "publish_general": true,
  "recipient_ids": ["uuid de usuario", "otro uuid"]
}
```

Antes de escribir se comprueba que el documento pertenezca al remitente y que
todos los destinatarios existan, estén activos y no sean el propio remitente.
Si falla uno, no se crea ningún mensaje, permiso ni notificación.

La respuesta contiene todos los mensajes generales y directos:

```json
{
  "client_id": "uuid estable de la operación",
  "created": true,
  "messages": []
}
```

Reintentar el mismo contenido y destinos —aunque cambie su orden— devuelve los
mismos mensajes con `created: false`. Reutilizar `client_id` con otro contenido,
documento o conjunto de destinos devuelve `409`. Los mensajes directos crean
sus permisos y notificaciones dentro de la misma transacción.

## Mensajes directos

- `GET /direct/{peer_id}/messages?limit=50&offset=0`
- `POST /direct/{peer_id}/messages`
- `POST /direct/{peer_id}/read`

La creación usa el mismo cuerpo del chat general. Un documento adjunto debe
pertenecer al remitente y crea o reactiva para el destinatario un `Share` con
permiso mínimo de comentario. Nunca reduce permisos superiores ya existentes.

`POST /direct/{peer_id}/read` marca como leídos solamente los mensajes entrantes
de ese usuario y devuelve:

```json
{"updated": 3, "read_at": "2026-07-26T12:00:00Z"}
```

## Bandeja de conversaciones

`GET /conversations?limit=50&offset=0`

Cada elemento contiene:

```json
{
  "user": {"id": "uuid", "username": "lectora", "display_name": "Lectora"},
  "last_message": {},
  "unread_count": 2
}
```

El chat general no se incluye porque el cliente debe fijarlo como primera
entrada de la interfaz.

## Forma de los mensajes

`GET /messages/{message_id}` permite obtener un mensaje concreto. Los mensajes
directos solo son visibles para sus dos participantes; los generales, para
cualquier usuario autenticado.

```json
{
  "id": "uuid",
  "client_id": "uuid local o null",
  "sender": {"id": "uuid", "username": "autora", "display_name": "Autora"},
  "recipient": null,
  "body": "Comparto mi cuento.",
  "document": null,
  "created_at": "2026-07-26T12:00:00Z",
  "read_at": null
}
```

Cuando existe, `document` tiene la forma completa de `DocumentOut`. Todas las
listas de mensajes y conversaciones se ordenan del elemento más reciente al
más antiguo. `limit` admite de 1 a 100 y `offset` debe ser no negativo.

Los adjuntos son referencias al documento colaborativo actual, no copias
inmutables: las ediciones posteriores se reflejan al volver a consultarlo. Si
el propietario elimina el proyecto o documento, el texto del mensaje permanece
pero el adjunto deja de exponerse.
