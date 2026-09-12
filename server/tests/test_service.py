from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.exc import OperationalError

from zhouji_api.app import create_app
from zhouji_api.database import make_engine
from zhouji_api.settings import ConfigurationError, Settings


def configuration(**changes):
    return {
        "ZHOUJI_DB_HOST": "127.0.0.1", "ZHOUJI_DB_PORT": "3306",
        "ZHOUJI_DB_NAME": "zhouji", "ZHOUJI_DB_USER": "zhouji_app",
        "ZHOUJI_DB_PASSWORD": "test-only@:/%密码", **changes,
    }


def test_mysql_configuration_preserves_special_characters_without_exposing_password():
    settings = Settings.from_environment(configuration())
    engine = make_engine(settings)
    assert engine.dialect.name == "mysql"
    assert engine.dialect.driver == "pymysql"
    assert engine.url.query["charset"] == "utf8mb4"
    assert engine.url.password == configuration()["ZHOUJI_DB_PASSWORD"]
    assert settings.database_password not in repr(settings)
    assert settings.database_password not in str(engine.url)
    engine.dispose()


def test_missing_configuration_fails_before_service_start():
    with pytest.raises(ConfigurationError, match="ZHOUJI_DB_PASSWORD"):
        Settings.from_environment(configuration(ZHOUJI_DB_PASSWORD=""))


@pytest.mark.parametrize("port", ["0", "65536", "secret-invalid-port"])
def test_invalid_port_does_not_echo_configuration(port):
    with pytest.raises(ConfigurationError) as error:
        Settings.from_environment(configuration(ZHOUJI_DB_PORT=port))
    assert str(error.value) == "ZHOUJI_DB_PORT 必须为 1–65535 的整数"


def test_health_http_contract_with_working_sql_connection():
    # Only validates the HTTP/SQL connection contract; this is not a MySQL integration test.
    engine = create_engine("sqlite://")
    with TestClient(create_app(engine=engine)) as client:
        for endpoint in ["live", "ready"]:
            response = client.get(f"/api/v1/health/{endpoint}")
            assert response.status_code == 200
            assert response.json() == {"status": "ok"}
            assert response.headers["cache-control"] == "no-store"
        assert client.get("/docs").status_code == 404
        assert client.get("/openapi.json").status_code == 404
        assert client.post("/api/v1/auth/wechat/challenge").status_code == 503


def test_unavailable_database_is_not_reported_as_ready_and_secrets_are_not_logged(caplog):
    engine = Mock()
    engine.connect.side_effect = OperationalError("SELECT 1", {}, Exception("private-db-secret"))
    with TestClient(create_app(engine=engine)) as client:
        assert client.get("/api/v1/health/live").status_code == 200
        response = client.get("/api/v1/health/ready")
        assert response.status_code == 503
        assert response.json() == {"status": "unavailable"}
        assert response.headers["retry-after"] == "5"
        assert "private-db-secret" not in response.text + caplog.text
    engine.dispose.assert_called_once()
