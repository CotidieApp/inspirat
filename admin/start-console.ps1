$ErrorActionPreference = "Stop"

Set-Location -LiteralPath $PSScriptRoot

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "Node.js y npm no están disponibles en este computador."
}

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "node_modules"))) {
    Write-Host "Preparando la consola por primera vez..." -ForegroundColor Cyan
    npm install
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudieron instalar las dependencias."
    }
}

Write-Host ""
Write-Host "Consola local de pruebas de inspíraT" -ForegroundColor Green
Write-Host "Abre en el navegador la dirección que aparecerá a continuación." -ForegroundColor DarkGray
Write-Host "Para detenerla, presiona Ctrl+C." -ForegroundColor DarkGray
Write-Host ""

npm run dev
