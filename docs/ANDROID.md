# Android: ejecución, firma y compilación

La configuración central usa nombre visible `inspíraT`, nombre técnico
`inspirat` e identificador de producción `com.inspirat.app`. El flavor `dev`
añade `.dev`; `prod` conserva el identificador final.

## Emulador

```powershell
cd mobile
flutter pub get
flutter devices
flutter run --flavor dev --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

`10.0.2.2` es el host desde el emulador Android. El flavor de desarrollo admite
HTTP local; producción no habilita tráfico sin cifrar.

## Teléfono físico

Activa depuración USB, acepta la clave del equipo, confirma `flutter devices` y
usa la IP LAN del servidor:

```powershell
flutter run --flavor dev --dart-define=API_BASE_URL=http://192.168.1.50:8000/api/v1
```

## APK de depuración

```powershell
flutter build apk --debug --flavor dev `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Salida: `mobile/build/app/outputs/flutter-apk/app-dev-debug.apk`.

En este workspace, usa preferentemente el script integrado: compila para
teléfono y copia obligatoriamente el resultado a
`G:\Mi unidad\inspíraT\Installer APK v2`, verificando su SHA-256:

```powershell
.\scripts\build_android.ps1 `
  -ApiBaseUrl "http://192.168.4.200:8000/api/v1"
```

## Clave y versión firmada

```powershell
keytool -genkeypair -v -keystore "$env:USERPROFILE\inspirat-upload.jks" `
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Crea `mobile/android/key.properties` (está ignorado por Git):

```properties
storePassword=CAMBIAR
keyPassword=CAMBIAR
keyAlias=upload
storeFile=C:\\Users\\TU_USUARIO\\inspirat-upload.jks
```

Compila contra una API HTTPS:

```powershell
flutter build apk --release --flavor prod `
  --dart-define=API_BASE_URL=https://api.tudominio.cl/api/v1
flutter build appbundle --release --flavor prod `
  --dart-define=API_BASE_URL=https://api.tudominio.cl/api/v1
```

Salidas esperadas:

- `build/app/outputs/flutter-apk/app-prod-release.apk`
- `build/app/outputs/bundle/prodRelease/app-prod-release.aab`

Conserva el keystore y sus contraseñas en dos copias cifradas. Perderlo puede
impedir actualizar la aplicación publicada. Incrementa `version` en
`pubspec.yaml` (`versionName+versionCode`) en cada publicación.
