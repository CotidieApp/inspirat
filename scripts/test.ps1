$ErrorActionPreference = "Stop"
Push-Location "$PSScriptRoot\..\backend"
try {
    if (-not (Test-Path ".venv")) { python -m venv .venv }
    & .\.venv\Scripts\python -m pip install -e ".[dev]"
    & .\.venv\Scripts\python -m ruff check .
    & .\.venv\Scripts\python -m pytest
} finally {
    Pop-Location
}

