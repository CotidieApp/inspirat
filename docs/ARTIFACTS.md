# Artefactos verificados

## APK de desarrollo

- Archivo: `dist/inspirat-0.1.0-phone-wifi-debug.apk`
- Flavor: `dev`
- Versión: `0.1.0+1`
- Paquete: `com.inspirat.app.dev`
- API compilada: `http://192.168.4.200:8000/api/v1`
- Tamaño: 158.142.710 bytes
- SHA-256:
  `8F4A831228E193022F31823E44F8C826FB4CCD428BA812657A28260F930441BC`

Esta compilación para teléfono físico apunta inicialmente a
`http://192.168.4.200:8000/api/v1` e incorpora el icono oficial del respaldo,
paleta verde petróleo/champaña, búsqueda local, resumen real de biblioteca y
estadísticas de sesión. La dirección puede cambiarse dentro de la aplicación
desde la bienvenida o el perfil.

Incluye la corrección de ciclo de vida del diálogo de servidor y una prueba de
regresión que cubre apertura, notificación, guardado y cierre. El registro
valida localmente las mismas reglas de la API y muestra errores específicos.
El manifiesto Android usa directamente el PNG oficial; el recurso dentro del
APK coincide byte por byte con `mobile/assets/branding/icon-512x512.png`.
El script compila mediante una ruta ASCII en Windows y bloquea la copia si
faltan `MaterialIcons`, el manifiesto de fuentes o los recursos de marca.
El editor actualiza SQLite y su copia en memoria, autoguarda, ofrece guardado
manual y termina de guardar antes de salir. La ruta inicial respeta la sesión
restaurada y conserva el acceso local aunque la red falle temporalmente.

Es un APK de depuración para emulador/desarrollo. No debe publicarse. La guía
`ANDROID.md` explica cómo generar `com.inspirat.app` firmado contra HTTPS.
