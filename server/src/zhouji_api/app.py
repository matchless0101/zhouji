from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI, Response
from fastapi.responses import JSONResponse
from sqlalchemy import Engine, text
from sqlalchemy.exc import SQLAlchemyError
from fastapi.exceptions import RequestValidationError

from .apple import AppleProvider, AppleSettings
from .auth import auth_router
from .models import metadata

from .database import make_engine
from .settings import Settings

logger = logging.getLogger("zhouji_api")


def create_app(settings: Settings | None = None, *, engine: Engine | None = None, apple_provider=None) -> FastAPI:
    database = engine if engine is not None else make_engine(settings or Settings.from_environment())
    if apple_provider is None:
        apple_settings = AppleSettings.from_environment()
        apple_provider = AppleProvider(apple_settings) if apple_settings else None

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        yield
        database.dispose()

    app = FastAPI(
        title="粥记 API", version="0.1.0", lifespan=lifespan,
        docs_url=None, redoc_url=None, openapi_url=None,
    )

    @app.middleware('http')
    async def private_response(request, call_next):
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        return response

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request, error):
        # FastAPI's default response echoes invalid inputs, which can contain tokens.
        return JSONResponse(status_code=422, content={'detail': '请求格式不正确'})

    @app.exception_handler(SQLAlchemyError)
    async def database_unavailable(request, error):
        return JSONResponse(status_code=503, content={'detail': '服务暂不可用，请稍后重试'})

    app.include_router(auth_router(database, apple_provider))

    @app.get("/api/v1/health/live")
    def liveness(response: Response):
        response.headers["Cache-Control"] = "no-store"
        return {"status": "ok"}

    @app.get("/api/v1/health/ready")
    def readiness():
        try:
            with database.connect() as connection:
                connection.execute(text("SELECT 1"))
                if apple_provider is not None:
                    for table in metadata.sorted_tables:
                        connection.execute(table.select().limit(0))
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
