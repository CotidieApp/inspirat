param(
    [string]$ApiBaseUrl = "http://192.168.4.200:8000/api/v1",
    [string]$Destination = (
        "G:\Mi unidad\insp{0}raT\Installer APK v2" -f [char]0x00ED
    )
)

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
    & $flutter build apk --debug --flavor dev "--dart-define=API_BASE_URL=$ApiBaseUrl"
    if ($LASTEXITCODE -ne 0) {
        throw "La compilación Android falló con código $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

$source = Join-Path $mobile "build\app\outputs\flutter-apk\app-dev-debug.apk"
if (-not (Test-Path -LiteralPath $source)) {
    throw "Flutter terminó sin generar el APK esperado: $source"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$requiredEntries = @(
    "assets/flutter_assets/FontManifest.json",
    "assets/flutter_assets/fonts/MaterialIcons-Regular.otf",
    "assets/flutter_assets/assets/branding/icon-512x512.png",
    "res/mipmap-mdpi-v4/ic_launcher.png",
    "res/mipmap-xxxhdpi-v4/ic_launcher.png"
)
$exactEntries = @{
    "assets/flutter_assets/assets/branding/icon-512x512.png" = (
        Join-Path $mobile "assets\branding\icon-512x512.png"
    )
    "res/mipmap-xxxhdpi-v4/ic_launcher.png" = (
        Join-Path $mobile (
            "android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png"
        )
    )
}
$archive = [System.IO.Compression.ZipFile]::OpenRead($source)
try {
    foreach ($entryName in $requiredEntries) {
        $entry = $archive.GetEntry($entryName)
        if ($null -eq $entry -or $entry.Length -eq 0) {
            throw "El APK está incompleto; falta el recurso obligatorio: $entryName"
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
$target = Join-Path $Destination "inspirat-0.1.0-phone-wifi-debug.apk"
Copy-Item -LiteralPath $source -Destination $target -Force

$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
$targetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
if ($sourceHash -ne $targetHash) {
    throw "La copia se creó, pero su SHA-256 no coincide con el APK compilado."
}

Write-Output "APK compilado y copiado: $target"
Write-Output "SHA256=$targetHash"
