"""Explicit, secret-safe configuration for the dedicated ZhouJi database."""

import os
from dataclasses import dataclass, field
from typing import Mapping

from sqlalchemy import URL


class ConfigurationError(ValueError):
    pass


@dataclass(frozen=True)
class Settings:
    database_host: str
    database_port: int
    database_name: str
    database_user: str
    database_password: str = field(repr=False)

    @classmethod
    def from_environment(cls, environment: Mapping[str, str] | None = None) -> "Settings":
        values = os.environ if environment is None else environment
        required = (
            "ZHOUJI_DB_HOST", "ZHOUJI_DB_NAME", "ZHOUJI_DB_USER", "ZHOUJI_DB_PASSWORD",
        )
        missing = [key for key in required if not values.get(key, "").strip()]
        if missing:
            # Report keys only: configuration values may contain credentials.
            raise ConfigurationError("缺少服务端配置：" + ", ".join(missing))
        try:
            port = int(values.get("ZHOUJI_DB_PORT", "3306"))
            if not 1 <= port <= 65535:
                raise ValueError
        except ValueError:
            raise ConfigurationError("ZHOUJI_DB_PORT 必须为 1–65535 的整数") from None
        return cls(
            database_host=values["ZHOUJI_DB_HOST"].strip(),
            database_port=port,
            database_name=values["ZHOUJI_DB_NAME"].strip(),
            database_user=values["ZHOUJI_DB_USER"].strip(),
            database_password=values["ZHOUJI_DB_PASSWORD"],
        )

    @property
    def database_url(self) -> URL:
        # URL.create preserves passwords containing @, /, :, % and Unicode.
        return URL.create(
            "mysql+pymysql",
            username=self.database_user,
            password=self.database_password,
            host=self.database_host,
            port=self.database_port,
            database=self.database_name,
            query={"charset": "utf8mb4"},
        )
