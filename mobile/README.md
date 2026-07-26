# Cliente Android de inspíraT

Flutter 3.44.8 / Dart 3.12.2. El cliente confirma cada edición en SQLite antes
de intentar la red, aísla los escritos por cuenta/servidor y conserva una cola
idempotente por `client_id`. Incluye chat grupal, mensajes directos y publicación
transaccional a uno o varios destinos.

```powershell
flutter pub get
flutter run --flavor dev `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Consulta `../docs/ANDROID.md` para firma, APK, AAB y teléfono físico.
