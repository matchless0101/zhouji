from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse
from sqlalchemy import Engine, text
from sqlalchemy.exc import SQLAlchemyError

from .database import make_engine
from .settings import Settings

logger = logging.getLogger("zhouji_api")


def create_app(settings: Settings | None = None, *, engine: Engine | None = None) -> FastAPI:
    database = engine if engine is not None else make_engine(settings or Settings.from_environment())

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield
        database.dispose()

    app = FastAPI(
        title="粥记 API", version="0.1.0", lifespan=lifespan,
        docs_url=None, redoc_url=None, openapi_url=None,
    )

    @app.get("/api/v1/health/live")
    def liveness(response: Response):
        response.headers["Cache-Control"] = "no-store"
        return {"status": "ok"}

    @app.get("/api/v1/health/ready")
    def readiness():
        try:
            with database.connect() as connection:
                connection.execute(text("SELECT 1"))
        except SQLAlchemyError:
            # Driver errors may include addresses, usernames or supplied values.
            logger.warning("database readiness check failed")
            return JSONResponse(
                status_code=503,
                content={"status": "unavailable"},
                headers={"Cache-Control": "no-store", "Retry-After": "5"},
            )
        return JSONResponse(content={"status": "ok"}, headers={"Cache-Control": "no-store"})

    return app
