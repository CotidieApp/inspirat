# Limitaciones conocidas y hoja de ruta

## MVP actual

- Editor de texto fiable, conteo y modo concentración; formato enriquecido
  avanzado pendiente.
- Conflictos conservan la copia local, permiten reenviarla con la revisión
  correcta y guardan la rama anterior del capítulo en el historial; falta
  comparación y combinación visual.
- Exporta TXT, Markdown y PDF; DOCX y EPUB irán al worker.
- El correo saliente (API HTTP de Resend, con SMTP como respaldo en
  desarrollo) ya se usa para restablecer contraseña; adjuntos y MinIO siguen
  sin interfaz (infraestructura provisionada, sin funcionalidad).
- Hay chat grupal para cuentas autenticadas, mensajes directos y una consola
  local de pruebas. Antes de abrir registros públicos faltan bloqueo, denuncia,
  moderación y auditoría; la consola local no es un panel de moderación.
- La cola móvil sincroniza el recorrido principal; falta sincronización
  incremental de comentarios/notificaciones en segundo plano.

## Próximos hitos

1. Carpetas y árbol reordenable; personajes, lugares, glosario y cronología.
2. Editor enriquecido accesible, búsqueda/reemplazo y comentarios de selección.
3. Resolución de conflictos con diff de tres vías y compactación de versiones.
4. Share links con contraseña, caducidad, máximo de accesos y descargas.
5. DOCX/EPUB, importaciones y copia completa portable.
6. FCM opcional, correos traducibles, métricas Prometheus y auditoría.
7. Bloqueo/denuncia, reglas comunitarias y panel de moderación sin acceso
   rutinario a mensajes privados.
8. Investigación E2EE y colaboración CRDT, sin prometer compatibilidad previa.
