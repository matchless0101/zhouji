"""Dedicated ZhouJi maintenance entry points; never prints configuration."""
import argparse

from .database import make_engine
from .settings import Settings
from .sync import purge_soft_deleted


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['purge'])
    parser.parse_args()
    engine = make_engine(Settings.from_environment())
    try:
        count = purge_soft_deleted(engine)
        print(f'purged_content_rows={count}')
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()
