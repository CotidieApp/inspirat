param(
    [string]$ApiBaseUrl = "http://192.168.4.200:8000/api/v1",
    [string]$Flavor = "dev",
    [switch]$Release,
    # El DSN de Sentry no es un secreto (esta pensado para vivir en el
    # cliente); solo se activa fuera del flavor dev para no mezclar ruido de
    # pruebas locales con errores reales de usuarios.
    [string]$SentryDsn = "https://23f9a153afdf214bac91f8c1dd17471e@o4511808810450944.ingest.us.sentry.io/4511808828145664",
    [string]$Destination = (
        "G:\Mi unidad\insp{0}raT\Installer APK v2" -f [char]0x00ED
    )
)

$buildMode = if ($Release) { "release" } else { "debug" }

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$mobile = Join-Path $workspace "mobile"
$buildMobile = $mobile
$bundledFlutter = "C:\Users\balca\.codex\sdks\flutter\bin\flutter.bat"
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue

if ($flutterCommand) {
    $flutter = $flutterCommand.Source
} elseif (Test-Path -LiteralPath $bundledFlutter) {
    $flutter = $bundledFlutter
} else {
    throw "No se encontró Flutter en PATH ni en $bundledFlutter"
}

# Flutter/Gradle pierde assets silenciosamente en Windows cuando la ruta del
# proyecto contiene caracteres no ASCII. Se compila mediante una unidad SUBST
# estable y se comprueba que apunte exactamente a este workspace.
if ($workspace -match "[^\x00-\x7F]") {
    $asciiDrive = "I:"
    $mappingPrefix = "{0}\: =>" -f $asciiDrive
    $mapping = @(& subst.exe) |
        Where-Object { $_.StartsWith(
            $mappingPrefix,
            [System.StringComparison]::OrdinalIgnoreCase
        ) } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($mapping)) {
        & subst.exe $asciiDrive $workspace
        if ($LASTEXITCODE -ne 0) {
            throw "No se pudo crear la ruta ASCII temporal $asciiDrive"
        }
        $mapping = @(& subst.exe) |
            Where-Object { $_.StartsWith(
                $mappingPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            ) } |
            Select-Object -First 1
    }
    $workspaceProbe = Join-Path $workspace "mobile\pubspec.yaml"
    $mappedProbe = Join-Path "$asciiDrive\" "mobile\pubspec.yaml"
    if (
        -not (Test-Path -LiteralPath $mappedProbe) -or
        (Get-FileHash -Algorithm SHA256 -LiteralPath $workspaceProbe).Hash -ne
        (Get-FileHash -Algorithm SHA256 -LiteralPath $mappedProbe).Hash
    ) {
        throw "$asciiDrive ya está asignada a otra ruta."
    }
    $buildMobile = Join-Path "$asciiDrive\" "mobile"
}

Push-Location $buildMobile
try {
    & $flutter clean
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo limpiar la compilación Android anterior."
    }
    $devBuildFlag = if ($Flavor -eq "dev") { "true" } else { "false" }
    if ($Flavor -ne "dev" -and $devBuildFlag -eq "true") {
        # No debiera poder pasar nunca (devBuildFlag se deriva de Flavor arriba
        # mismo), pero si alguien lo cambia a futuro para aceptar un override
        # manual, esto evita que un build "prod" termine exponiendo el
        # selector de servidor http:// sin cifrar a usuarios reales.
        throw "DEV_BUILD no puede ser true para el flavor '$Flavor'."
    }
    $sentryDsnDefine = if ($Flavor -eq "dev") { "" } else { $SentryDsn }
    & $flutter build apk "--$buildMode" --flavor $Flavor "--dart-define=API_BASE_URL=$ApiBaseUrl" "--dart-define=DEV_BUILD=$devBuildFlag" "--dart-define=SENTRY_DSN=$sentryDsnDefine"
    if ($LASTEXITCODE -ne 0) {
        throw "La compilación Android falló con código $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$source = Join-Path $mobile "build\app\outputs\flutter-apk\app-$Flavor-$buildMode.apk"
if (-not (Test-Path -LiteralPath $source)) {
    throw "Flutter terminó sin generar el APK esperado: $source"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

# Recursos empacados por Flutter (assets/flutter_assets/...): el shrinker de
# Android no los toca, sus rutas son estables en debug y en release.
$requiredEntries = @(
    "assets/flutter_assets/FontManifest.json",
    "assets/flutter_assets/fonts/MaterialIcons-Regular.otf",
    "assets/flutter_assets/assets/branding/icon-512x512.png"
)
$exactEntries = @{
    "assets/flutter_assets/assets/branding/icon-512x512.png" = (
        Join-Path $mobile "assets\branding\icon-512x512.png"
    )
}

# El icono de lanzador SI es un recurso Android (res/mipmap-*): en release,
# shrinkResources ofusca esos nombres de archivo (ic_launcher.png -> 9w.png),
# así que se resuelve la ruta real vía aapt2 en vez de asumir un nombre fijo.
$sdkRoot = $env:ANDROID_HOME
if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
if (-not $sdkRoot) { $sdkRoot = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$aapt2 = Get-ChildItem -Path (Join-Path $sdkRoot "build-tools") -Filter "aapt2.exe" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $aapt2) {
    throw "No se encontró aapt2 en $sdkRoot\build-tools; no se puede verificar el icono del APK."
}
$badging = & $aapt2 dump badging $source 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "aapt2 no pudo leer el APK generado:`n$badging"
}
$iconEntries = $badging | Select-String -Pattern "^application-icon-(160|640):'(.+)'$"
if ($iconEntries.Count -lt 2) {
    throw "El APK no declara icono de lanzador para mdpi y xxxhdpi."
}
$appLabel = "insp{0}raT" -f [char]0x00ED
$expectedLabel = if ($Flavor -eq "dev") { "$appLabel dev" } else { $appLabel }
$labelMatch = $badging | Select-String -Pattern "^application-label:'(.+)'$" | Select-Object -First 1
if (-not $labelMatch -or $labelMatch.Matches[0].Groups[1].Value -ne $expectedLabel) {
    $actual = if ($labelMatch) { $labelMatch.Matches[0].Groups[1].Value } else { "(ninguna)" }
    throw "Etiqueta de app inesperada para el flavor '$Flavor': se esperaba '$expectedLabel', se obtuvo '$actual'."
}
$iconPaths = $iconEntries | ForEach-Object { $_.Matches[0].Groups[2].Value }

$archive = [System.IO.Compression.ZipFile]::OpenRead($source)
try {
    foreach ($entryName in $requiredEntries) {
        $entry = $archive.GetEntry($entryName)
        if ($null -eq $entry -or $entry.Length -eq 0) {
            throw "El APK está incompleto; falta el recurso obligatorio: $entryName"
        }
    }
    foreach ($iconPath in $iconPaths) {
        $entry = $archive.GetEntry($iconPath)
        if ($null -eq $entry -or $entry.Length -eq 0) {
            throw "El icono que aapt2 declara ($iconPath) no existe en el APK."
        }
    }
    foreach ($entryName in $exactEntries.Keys) {
        $entry = $archive.GetEntry($entryName)
        $algorithm = [System.Security.Cryptography.SHA256]::Create()
        $stream = $entry.Open()
        try {
            $entryHash = (
                [BitConverter]::ToString($algorithm.ComputeHash($stream))
            ).Replace("-", "")
        } finally {
            $stream.Dispose()
            $algorithm.Dispose()
        }
        $expectedHash = (
            Get-FileHash -Algorithm SHA256 -LiteralPath $exactEntries[$entryName]
        ).Hash
        if ($entryHash -ne $expectedHash) {
            throw "El APK no contiene la versión actual del recurso: $entryName"
        }
    }
} finally {
    $archive.Dispose()
}

if (-not (Test-Path -LiteralPath "G:\")) {
    throw "La unidad G: no está disponible; no se puede completar la copia obligatoria."
}

New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$targetName = if ($Flavor -eq "dev" -and -not $Release) {
    "inspirat-0.1.0-phone-wifi-debug.apk"
} else {
    "inspirat-0.1.0-$Flavor-$buildMode.apk"
}
$target = Join-Path $Destination $targetName
Copy-Item -LiteralPath $source -Destination $target -Force

$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
$targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
if ($sourceHash -ne $targetHash) {
    throw "La copia se creó, pero su SHA-256 no coincide con el APK compilado."
}

Write-Output "APK compilado y copiado: $target"
Write-Output "SHA256=$targetHash"
