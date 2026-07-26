# Seguridad, privacidad y propiedad

- Las contraseñas usan Argon2id mediante `pwdlib`; nunca se registran.
- El access token dura 15 minutos. El refresh token es aleatorio, se almacena
  solo como SHA-256, rota en cada uso y puede revocarse por completo.
- Todos los accesos a documentos se autorizan en la API. Ocultar un botón no es
  una barrera de seguridad.
- Los proyectos nacen privados. Compartir exige una acción explícita y los
  permisos pueden revocarse.
- Restablecer contraseña usa un código de 6 dígitos enviado por correo, de un
  solo uso y vence en 15 minutos; al usarse revoca todas las sesiones activas.
  La respuesta no revela si la cuenta existe.
- Login y restablecimiento de contraseña tienen límite de intentos por
  identidad (proceso, no distribuido) para dificultar fuerza bruta.
- Producción requiere HTTPS, CORS restringido, secreto aleatorio, volúmenes
  cifrados, firewall y copias cifradas.
- Los logs contienen metadatos técnicos y UUID, nunca el texto completo.
- El autor conserva todos los derechos sobre su obra. El servicio no usa textos
  para entrenar IA y las futuras funciones de IA estarán apagadas por defecto.

## Retención

La papelera lógica se conserva 30 días por defecto (tarea programada pendiente).
Las sesiones revocadas y auditorías técnicas pueden conservarse 90 días. Las
copias diarias siguen una política 7/4/12: siete diarias, cuatro semanales y
doce mensuales. Ajustar según legislación y contrato.

## Ruta a cifrado de extremo a extremo

Una versión futura puede generar una clave por proyecto en el dispositivo,
cifrar contenido con AEAD y envolver esa clave para cada dispositivo/miembro.
Antes de implementarlo deben resolverse recuperación, rotación, búsqueda,
exportación, múltiples dispositivos y pérdida de claves. Mientras el servidor
pueda leer el contenido, **inspíraT no afirma ofrecer E2EE**.

## Textos legales iniciales

La política de privacidad debe explicar finalidad, datos almacenados,
destinatarios, retención, portabilidad, rectificación y eliminación. Las
condiciones deben declarar propiedad del autor, licencia limitada necesaria
para alojar/sincronizar, conducta prohibida y mecanismo de baja. El chat grupal
de desarrollo requiere normas contra acoso, publicación sin derechos, denuncia
y moderación antes de abrir el registro al público.

Estos borradores técnicos requieren revisión jurídica antes de un lanzamiento
comercial, especialmente en Chile y en cualquier otro país objetivo.
