import threading
import time

from fastapi import HTTPException, status


class RateLimiter:
    """Fixed-window limiter, in-process only.

    Deliberately not Redis-backed: nothing in this API currently needs
    limits to survive a restart or be shared across instances, and keeping
    it in-process means auth endpoints keep working even if Redis is down.
    """

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._hits: dict[str, list[float]] = {}

    def hit(self, key: str, limit: int, window_seconds: float) -> None:
        now = time.monotonic()
        with self._lock:
            timestamps = [t for t in self._hits.get(key, []) if now - t < window_seconds]
            if len(timestamps) >= limit:
                raise HTTPException(
                    status.HTTP_429_TOO_MANY_REQUESTS,
                    "Demasiados intentos. Espera unos minutos antes de volver a intentarlo.",
                )
            timestamps.append(now)
            self._hits[key] = timestamps

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


limiter = RateLimiter()


def enforce(bucket: str, identifier: str, limit: int, window_seconds: float) -> None:
    limiter.hit(f"{bucket}:{identifier}", limit, window_seconds)
