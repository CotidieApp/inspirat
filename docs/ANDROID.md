# Android: ejecución, firma y compilación

La configuración central usa nombre visible `inspíraT`, nombre técnico
`inspirat` e identificador de producción `com.inspirat.app`. El flavor `dev`
añade `.dev`; `prod` conserva el identificador final.

## Emulador

```powershell
cd mobile
flutter pub get
flutter devices
flutter run --flavor dev --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 --dart-define=DEV_BUILD=true
```

`10.0.2.2` es el host desde el emulador Android. El flavor de desarrollo admite
HTTP local; producción no habilita tráfico sin cifrar. `DEV_BUILD=true` es lo
que muestra el selector "Configurar conexión al servidor" en la app — sin
esa define queda oculto (así se compila la versión pública real).

## Teléfono físico

Activa depuración USB, acepta la clave del equipo, confirma `flutter devices` y
usa la IP LAN del servidor:

```powershell
flutter run --flavor dev --dart-define=API_BASE_URL=http://192.168.1.50:8000/api/v1 --dart-define=DEV_BUILD=true
```

## APK de depuración

```powershell
flutter build apk --debug --flavor dev `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1 `
  --dart-define=DEV_BUILD=true
```

Salida: `mobile/build/app/outputs/flutter-apk/app-dev-debug.apk`.

En este workspace, usa preferentemente el script integrado: compila para
teléfono y copia obligatoriamente el resultado a
`G:\Mi unidad\inspíraT\Installer APK v2`, verificando su SHA-256:

```powershell
.\scripts\build_android.ps1 `
  -ApiBaseUrl "http://192.168.4.200:8000/api/v1"
```

El script acepta `-Flavor` (`dev` por defecto) y el switch `-Release` para
compilar la version publica firmada; ver la seccion siguiente. Verifica el
icono y la etiqueta de la app con `aapt2 dump badging` (no con nombres de
archivo literales), porque el shrinker de Android ofusca los nombres de los
recursos `res/` en builds de release — los assets de Flutter
(`assets/flutter_assets/...`) no se ven afectados por esto.

## Clave y version firmada

**Ya existe un keystore real para este workspace** en
`mobile/android/app/upload-keystore.jks` (creado 2026-07-26, alias `upload`),
con `mobile/android/key.properties` apuntando a el. Ambos estan en
`.gitignore` — respaldalos tu mismo en dos copias cifradas fuera del repo
(ej. gestor de contraseñas + otra copia offline). Si se pierden, no vas a
poder publicar una actualizacion firmada igual que las versiones ya
distribuidas; NO generes un keystore nuevo salvo que confirmes que el actual
se perdio de verdad.

Compila la version publica contra la API real con el script integrado:

```powershell
.\scripts\build_android.ps1 `
  -ApiBaseUrl "https://inspirat-api.onrender.com/api/v1" `
  -Flavor prod -Release
```

O manualmente:

```powershell
flutter build apk --release --flavor prod `
  --dart-define=API_BASE_URL=https://inspirat-api.onrender.com/api/v1
flutter build appbundle --release --flavor prod `
  --dart-define=API_BASE_URL=https://inspirat-api.onrender.com/api/v1
```

Salidas esperadas:

- `build/app/outputs/flutter-apk/app-prod-release.apk`
- `build/app/outputs/bundle/prodRelease/app-prod-release.aab`

Verifica la firma con `apksigner verify --print-certs <apk>`: debe mostrar
`CN=inspiraT`, no el certificado de depuracion de Android. Incrementa
`version` en `pubspec.yaml` (`versionName+versionCode`) en cada publicacion.

Si en el futuro se quiere publicar en Google Play, el `.aab` (no el `.apk`) es
lo que pide la Play Console, y falta ademas: cuenta de desarrollador (pago
unico), ficha de la tienda, cuestionario de clasificacion de contenido y
politica de privacidad publica. No se hizo en esta sesion.
