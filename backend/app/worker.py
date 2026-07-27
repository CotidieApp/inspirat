import json
import time

import redis
import structlog

from app.config import settings

logger = structlog.get_logger()


def run() -> None:
    connection = redis.from_url(settings.redis_url, decode_responses=True)
    logger.info("worker_started", queue="inspirat:jobs")
    while True:
        try:
            item = connection.blpop("inspirat:jobs", timeout=10)
        except redis.RedisError:
            logger.warning("worker_redis_unavailable")
            time.sleep(5)
            continue
        if not item:
            continue
        _, raw = item
        try:
            job = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("worker_job_malformed", raw=raw[:200])
            continue
        # La exportación síncrona cubre el MVP. Esta cola ya proporciona
        # el punto de ampliación para EPUB, copias y correos pesados.
        logger.info("job_received", job_id=job.get("id"), kind=job.get("kind"))


if __name__ == "__main__":
    run()
