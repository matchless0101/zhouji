import configparser
import gzip
import io
import os
from pathlib import Path
import stat
import subprocess
import tarfile


ROOT = Path(__file__).resolve().parents[1]
BACKUP_SCRIPT = ROOT / "deploy" / "backup-zhouji-db.sh"
OPS_CHECK_SCRIPT = ROOT / "deploy" / "check-zhouji-ops.sh"
REQUIRED_BUNDLE_MEMBERS = {
    "database/zhouji.sql.gz": gzip.compress(b"CREATE TABLE tasks (id bigint);\n"),
    "configuration/api.env": b"ZHOUJI_DB_NAME=zhouji\n",
    "secrets/token-encryption-key": b"token-key\n",
    "secrets/apple-login.p8": b"apple-private-key\n",
    "secrets/wechat-app-secret": b"wechat-secret\n",
}


def write_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def backup_environment(tmp_path: Path, dump_body: str) -> tuple[dict[str, str], Path]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    write_executable(fake_bin / "mysqldump", dump_body)

    configuration = tmp_path / "configuration"
    configuration.mkdir()
    required_files = {
        "ZHOUJI_API_ENV_FILE": ("api.env", "ZHOUJI_DB_NAME=zhouji\n"),
        "ZHOUJI_TOKEN_ENCRYPTION_KEY_FILE": ("token-encryption-key", "token-key\n"),
        "ZHOUJI_APPLE_PRIVATE_KEY_FILE": ("apple-login.p8", "apple-private-key\n"),
        "ZHOUJI_WECHAT_APP_SECRET_FILE": ("wechat-app-secret", "wechat-secret\n"),
    }
    environment = os.environ.copy()
    password_file = configuration / "database-password"
    password_file.write_text("password-never-log\n", encoding="utf-8")
    environment.update(
        {
            "PATH": f"{fake_bin}:{environment['PATH']}",
            "ZHOUJI_DB_HOST": "db.internal",
            "ZHOUJI_DB_PORT": "3306",
            "ZHOUJI_DB_NAME": "zhouji",
            "ZHOUJI_DB_USER": "backup-user",
            "ZHOUJI_DB_PASSWORD": "password-never-log",
            "ZHOUJI_MYSQL_DEFAULTS_FILE": str(tmp_path / "missing-defaults.cnf"),
            "ZHOUJI_DB_PASSWORD_FILE": str(password_file),
        }
    )
    for variable, (name, content) in required_files.items():
        path = configuration / name
        path.write_text(content, encoding="utf-8")
        environment[variable] = str(path)
    return environment, configuration


def run_backup(tmp_path: Path, environment: dict[str, str]) -> tuple[subprocess.CompletedProcess[str], Path]:
    output = tmp_path / "backups"
    result = subprocess.run(
        ["/bin/sh", str(BACKUP_SCRIPT), str(output)],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    return result, output


def test_dump_failure_is_nonzero_and_publishes_no_backup_or_password(tmp_path: Path):
    environment, _ = backup_environment(
        tmp_path,
        """#!/bin/sh
printf 'partial database output\\n'
printf 'dump failed with password %s\\n' "${MYSQL_PWD:-missing}" >&2
exit 23
""",
    )

    result, output = run_backup(tmp_path, environment)

    assert result.returncode != 0
    assert list(output.glob("zhouji-*")) == []
    assert "password-never-log" not in result.stdout + result.stderr


def test_missing_required_secret_fails_before_dump_and_publishes_nothing(tmp_path: Path):
    marker = tmp_path / "dump-was-called"
    environment, configuration = backup_environment(
        tmp_path,
        f"""#!/bin/sh
touch {marker}
printf 'database output\\n'
""",
    )
    (configuration / "wechat-app-secret").unlink()

    result, output = run_backup(tmp_path, environment)

    assert result.returncode != 0
    assert not marker.exists()
    assert list(output.glob("zhouji-*")) == []


def test_success_atomically_publishes_private_sql_and_complete_restore_bundle(tmp_path: Path):
    environment, _ = backup_environment(
        tmp_path,
        """#!/bin/sh
[ "${MYSQL_PWD:-}" = 'password-never-log' ] || exit 41
printf '%s\\n' "$*" > "${DUMP_ARGS_FILE:?}"
printf '%s\\n' 'CREATE TABLE `tasks` (`id` bigint);'
""",
    )
    dump_args_file = tmp_path / "dump-args"
    environment["DUMP_ARGS_FILE"] = str(dump_args_file)

    result, output = run_backup(tmp_path, environment)

    assert result.returncode == 0, result.stderr
    sql_backups = list(output.glob("zhouji-*.sql.gz"))
    bundles = list(output.glob("zhouji-*.bundle.tar.gz"))
    assert len(sql_backups) == 1
    assert len(bundles) == 1
    assert stat.S_IMODE(sql_backups[0].stat().st_mode) == 0o600
    assert stat.S_IMODE(bundles[0].stat().st_mode) == 0o600
    assert "CREATE TABLE `tasks`" in gzip.decompress(sql_backups[0].read_bytes()).decode()
    dump_args = dump_args_file.read_text(encoding="utf-8").split()
    assert "--databases" not in dump_args
    assert dump_args[-1] == "zhouji"
    assert "--routines" in dump_args
    assert "--events" in dump_args
    with tarfile.open(bundles[0], "r:gz") as archive:
        members = {member.name for member in archive.getmembers() if member.isfile()}
        assert members == {
            "database/zhouji.sql.gz",
            "configuration/api.env",
            "secrets/token-encryption-key",
            "secrets/apple-login.p8",
            "secrets/wechat-app-secret",
        }
        assert archive.extractfile("configuration/api.env").read() == b"ZHOUJI_DB_NAME=zhouji\n"
        assert archive.extractfile("secrets/token-encryption-key").read() == b"token-key\n"
    assert not list(output.glob(".zhouji-backup.*"))


def test_readable_mysql_defaults_file_preserves_socket_when_host_not_explicit(tmp_path: Path):
    environment, _ = backup_environment(
        tmp_path,
        """#!/bin/sh
case "$1" in
  --defaults-extra-file=*) ;;
  *) exit 42 ;;
esac
[ -z "${MYSQL_PWD:-}" ] || exit 43
printf '%s\\n' "$*" > "${DUMP_ARGS_FILE:?}"
printf 'CREATE DATABASE `zhouji`;\\n'
""",
    )
    dump_args_file = tmp_path / "dump-args"
    defaults_file = tmp_path / "debian.cnf"
    defaults_file.write_text("[client]\nuser=debian-sys-maint\npassword=fixture\n", encoding="utf-8")
    environment["ZHOUJI_MYSQL_DEFAULTS_FILE"] = str(defaults_file)
    environment["ZHOUJI_DB_PASSWORD_FILE"] = str(tmp_path / "missing-password-file")
    environment["DUMP_ARGS_FILE"] = str(dump_args_file)
    environment.pop("ZHOUJI_DB_PASSWORD")
    environment.pop("ZHOUJI_DB_HOST")
    environment.pop("ZHOUJI_DB_PORT")

    result, output = run_backup(tmp_path, environment)

    assert result.returncode == 0, result.stderr
    assert len(list(output.glob("zhouji-*.bundle.tar.gz"))) == 1
    dump_args = dump_args_file.read_text(encoding="utf-8").split()
    assert not any(argument.startswith("--host=") for argument in dump_args)
    assert not any(argument.startswith("--port=") for argument in dump_args)


def test_readable_mysql_defaults_file_allows_explicit_network_override(tmp_path: Path):
    environment, _ = backup_environment(
        tmp_path,
        """#!/bin/sh
printf '%s\\n' "$*" > "${DUMP_ARGS_FILE:?}"
printf 'CREATE TABLE tasks (id bigint);\\n'
""",
    )
    dump_args_file = tmp_path / "dump-args"
    defaults_file = tmp_path / "debian.cnf"
    defaults_file.write_text("[client]\nuser=debian-sys-maint\npassword=fixture\n", encoding="utf-8")
    environment["ZHOUJI_MYSQL_DEFAULTS_FILE"] = str(defaults_file)
    environment["DUMP_ARGS_FILE"] = str(dump_args_file)
    environment.pop("ZHOUJI_DB_PASSWORD")

    result, _ = run_backup(tmp_path, environment)

    assert result.returncode == 0, result.stderr
    dump_args = dump_args_file.read_text(encoding="utf-8").split()
    assert "--host=db.internal" in dump_args
    assert "--port=3306" in dump_args


def write_restore_bundle(path: Path, members: dict[str, bytes]) -> None:
    with tarfile.open(path, "w:gz") as archive:
        for name, content in members.items():
            info = tarfile.TarInfo(name)
            info.size = len(content)
            info.mode = 0o600
            archive.addfile(info, io.BytesIO(content))


def run_ops_check(
    tmp_path: Path,
    *,
    bundle_age: int = 0,
    failed_url: str = "",
    bundle_content: bytes | None = None,
    bundle_members: dict[str, bytes] | None = None,
) -> tuple[subprocess.CompletedProcess[str], Path]:
    backup_dir = tmp_path / "backups"
    backup_dir.mkdir(parents=True)
    bundle = backup_dir / "zhouji-20260919-010203.bundle.tar.gz"
    if bundle_content is not None:
        bundle.write_bytes(bundle_content)
    else:
        write_restore_bundle(bundle, bundle_members or REQUIRED_BUNDLE_MEMBERS)
    timestamp = int(bundle.stat().st_mtime) - bundle_age
    os.utime(bundle, (timestamp, timestamp))

    calls = tmp_path / "health-calls"
    probe = tmp_path / "health-probe"
    write_executable(
        probe,
        """#!/bin/sh
printf '%s\\n' "$1" >> "${HEALTH_CALLS:?}"
[ "$1" != "${FAILED_URL:-}" ]
""",
    )
    environment = os.environ.copy()
    environment.update(
        {
            "ZHOUJI_HEALTH_PROBE": str(probe),
            "HEALTH_CALLS": str(calls),
            "FAILED_URL": failed_url,
        }
    )
    result = subprocess.run(
        [
            "/bin/sh",
            str(OPS_CHECK_SCRIPT),
            str(backup_dir),
            "https://zhouji.example",
            "129600",
        ],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    return result, calls


def test_ops_check_verifies_local_public_health_and_fresh_complete_bundle(tmp_path: Path):
    result, calls = run_ops_check(tmp_path)

    assert result.returncode == 0, result.stderr
    assert calls.read_text(encoding="utf-8").splitlines() == [
        "http://127.0.0.1:8011",
        "https://zhouji.example",
    ]


def test_ops_check_fails_for_public_health_failure_or_stale_bundle(tmp_path: Path):
    failed_health, _ = run_ops_check(
        tmp_path / "health", failed_url="https://zhouji.example"
    )
    stale, _ = run_ops_check(tmp_path / "stale", bundle_age=129601)

    assert failed_health.returncode != 0
    assert stale.returncode != 0
    assert "stale" in stale.stderr.lower()


def test_ops_check_rejects_empty_or_corrupted_restore_bundle(tmp_path: Path):
    empty, _ = run_ops_check(tmp_path / "empty", bundle_content=b"")
    corrupt, _ = run_ops_check(tmp_path / "corrupt", bundle_content=b"not-a-gzip")

    assert empty.returncode != 0
    assert corrupt.returncode != 0


def test_ops_check_rejects_missing_or_unexpected_tar_members(tmp_path: Path):
    missing_secret = dict(REQUIRED_BUNDLE_MEMBERS)
    missing_secret.pop("secrets/wechat-app-secret")
    with_extra = dict(REQUIRED_BUNDLE_MEMBERS)
    with_extra["unexpected.txt"] = b"unexpected"

    missing, _ = run_ops_check(
        tmp_path / "missing", bundle_members=missing_secret
    )
    extra, _ = run_ops_check(tmp_path / "extra", bundle_members=with_extra)

    assert missing.returncode != 0
    assert extra.returncode != 0


def test_ops_check_rejects_corrupted_inner_database_dump(tmp_path: Path):
    members = dict(REQUIRED_BUNDLE_MEMBERS)
    members["database/zhouji.sql.gz"] = b"not-an-inner-gzip"

    result, _ = run_ops_check(tmp_path, bundle_members=members)

    assert result.returncode != 0


def read_unit(name: str) -> configparser.ConfigParser:
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    with (ROOT / "deploy" / name).open(encoding="utf-8") as handle:
        parser.read_file(handle)
    return parser


def test_systemd_units_schedule_daily_backup_five_minute_checks_and_daily_purge():
    backup_service = read_unit("zhouji-backup.service")
    backup_timer = read_unit("zhouji-backup.timer")
    check_service = read_unit("zhouji-ops-check.service")
    check_timer = read_unit("zhouji-ops-check.timer")
    purge_service = read_unit("zhouji-purge.service")
    purge_timer = read_unit("zhouji-purge.timer")

    assert backup_service["Service"]["ExecStart"] == (
        "/usr/local/sbin/zhouji-backup /var/backups/zhouji"
    )
    # Backup uses the administrator cnf; business TCP settings must not override it.
    assert "EnvironmentFile" not in backup_service["Service"]
    assert backup_timer["Timer"]["OnCalendar"] == "*-*-* 03:17:00"
    assert backup_timer["Timer"].getboolean("Persistent")

    assert check_service["Service"]["ExecStart"] == (
        "/usr/local/sbin/zhouji-ops-check /var/backups/zhouji "
        "https://zhouji.xiangdangdang.top 129600"
    )
    assert check_timer["Timer"]["OnUnitActiveSec"] == "5min"

    assert purge_service["Service"]["EnvironmentFile"] == "/etc/zhouji/api.env"
    assert purge_service["Service"]["Environment"] == (
        "PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=/opt/zhouji-api/current/src"
    )
    assert purge_service["Service"]["ExecStart"] == (
        "/opt/zhouji-api/current/.venv/bin/python -m zhouji_api.maintenance purge"
    )
    assert purge_timer["Timer"]["OnCalendar"] == "*-*-* 04:05:00"
    assert purge_timer["Timer"].getboolean("Persistent")
