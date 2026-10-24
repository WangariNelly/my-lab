"""Environment-driven configuration. Never hard-code credentials."""

from __future__ import annotations

import os


class MissingConfig(RuntimeError):
    """Raised when a required environment variable is not set."""


def env(name: str, default: str | None = None, *, required: bool = True) -> str | None:
    value = os.environ.get(name, default)
    if required and not value:
        raise MissingConfig(
            f"Environment variable {name} is not set. "
            "See lib/README.md and .env.example for the variables each tool needs."
        )
    return value


def servicenow() -> dict[str, str]:
    return {
        "instance": env("SN_INSTANCE"),  # e.g. https://dev12345.service-now.com
        "user": env("SN_USER"),
        "password": env("SN_PASSWORD"),
    }


def prometheus_url() -> str:
    return env("PROM_URL", "http://localhost:9090")


def dynatrace() -> dict[str, str]:
    return {
        "url": env("DT_ENV_URL"),  # e.g. https://abc12345.live.dynatrace.com
        "token": env("DT_API_TOKEN"),
    }
