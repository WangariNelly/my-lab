"""Prometheus HTTP API helpers (also works against Thanos/Mimir query APIs)."""

from __future__ import annotations

from typing import Any

from . import config
from .http import request


def query(promql: str, *, url: str | None = None) -> list[dict[str, Any]]:
    resp = request("GET", f"{(url or config.prometheus_url()).rstrip('/')}/api/v1/query", params={"query": promql})
    if resp.get("status") != "success":
        raise RuntimeError(f"Prometheus query failed: {resp}")
    return resp["data"]["result"]


def scalar(promql: str, *, url: str | None = None) -> float | None:
    """First sample value of an instant query, or None if the result is empty."""
    result = query(promql, url=url)
    if not result:
        return None
    return float(result[0]["value"][1])


def firing_alerts(alertname: str | None = None, *, url: str | None = None) -> list[dict[str, Any]]:
    resp = request("GET", f"{(url or config.prometheus_url()).rstrip('/')}/api/v1/alerts")
    alerts = [a for a in resp["data"]["alerts"] if a.get("state") == "firing"]
    if alertname:
        alerts = [a for a in alerts if a.get("labels", {}).get("alertname") == alertname]
    return alerts
