import time
import uuid

import structlog
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.routes import router
from app.config import settings

logger = structlog.get_logger()
app = FastAPI(
    title="inspíraT API",
    version="0.1.0",
    description="API privada y autoalojable para escritura, sincronización y revisión.",
    docs_url="/docs",
    redoc_url="/redoc",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
)


@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    started = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        logger.exception("unhandled_request", request_id=request_id, path=request.url.path)
        return JSONResponse(
            status_code=500,
            content={
                "error": {
                    "code": "internal_error",
                    "message": "Ocurrió un error inesperado. Tus cambios locales siguen seguros.",
                    "request_id": request_id,
                }
            },
        )
    response.headers["X-Request-ID"] = request_id
    logger.info(
        "request",
        request_id=request_id,
        method=request.method,
        path=request.url.path,
        status=response.status_code,
        duration_ms=round((time.perf_counter() - started) * 1000, 2),
    )
    return response


@app.get("/health", tags=["system"])
def health() -> dict:
    return {"status": "ok", "service": "inspirat_backend"}


@app.get("/ready", tags=["system"])
def ready() -> dict:
    return {"status": "ready"}


app.include_router(router, prefix=settings.api_prefix)
