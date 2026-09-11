from sqlalchemy import Engine, create_engine

from .settings import Settings


def make_engine(settings: Settings) -> Engine:
    return create_engine(
        settings.database_url,
        pool_pre_ping=True,
        pool_recycle=1800,
        pool_size=3,
        max_overflow=2,
        pool_timeout=5,
        connect_args={"connect_timeout": 5, "read_timeout": 5, "write_timeout": 5},
        hide_parameters=True,
        echo=False,
    )
