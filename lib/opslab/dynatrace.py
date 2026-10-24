"""Dynatrace Environment API v2 helpers (problems, metrics, events)."""

from __future__ import annotations

from typing import Any

from . import config
from .http import request


class Dynatrace:
    def __init__(self, url: str, token: str):
        self.url = url.rstrip("/")
        self.token = token

    @classmethod
    def from_env(cls) -> Dynatrace:
        return cls(**config.dynatrace())

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Api-Token {self.token}"}

    def problems(self, *, problem_selector: str | None = None, from_: str = "now-2h") -> list[dict[str, Any]]:
        params: dict[str, Any] = {"from": from_, "pageSize": 100}
        if problem_selector:
            params["problemSelector"] = problem_selector
        resp = request("GET", f"{self.url}/api/v2/problems", params=params, headers=self._headers())
        return resp.get("problems", [])

    def metric(self, selector: str, *, from_: str = "now-30m", resolution: str = "1m") -> dict[str, Any]:
        params = {"metricSelector": selector, "from": from_, "resolution": resolution}
        return request("GET", f"{self.url}/api/v2/metrics/query", params=params, headers=self._headers())

    def send_event(self, event: dict[str, Any]) -> dict[str, Any]:
        """POST /api/v2/events/ingest — e.g. CUSTOM_DEPLOYMENT events from CI."""
        return request("POST", f"{self.url}/api/v2/events/ingest", body=event, headers=self._headers())
