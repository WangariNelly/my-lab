"""ServiceNow Table API client (works on a free Personal Developer Instance).

Only the small surface the curriculum needs: create/update/query records on
incident, change_request, sc_request-style tables and CMDB classes.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

from . import config
from .http import basic_auth, request

# Incident state values on a default instance.
INCIDENT_STATES = {
    "new": "1",
    "in_progress": "2",
    "on_hold": "3",
    "resolved": "6",
    "closed": "7",
    "canceled": "8",
}


@dataclass
class ServiceNow:
    instance: str
    user: str
    password: str

    @classmethod
    def from_env(cls) -> ServiceNow:
        return cls(**config.servicenow())

    # -- low level -------------------------------------------------------
    def _url(self, table: str, sys_id: str | None = None) -> str:
        base = f"{self.instance.rstrip('/')}/api/now/table/{table}"
        return f"{base}/{sys_id}" if sys_id else base

    def _headers(self) -> dict[str, str]:
        return {"Authorization": basic_auth(self.user, self.password)}

    def query(
        self, table: str, sysparm_query: str, *, fields: list[str] | None = None, limit: int = 100
    ) -> list[dict[str, Any]]:
        params: dict[str, Any] = {"sysparm_query": sysparm_query, "sysparm_limit": limit}
        if fields:
            params["sysparm_fields"] = ",".join(fields)
        resp = request("GET", self._url(table), params=params, headers=self._headers())
        return resp.get("result", [])

    def create(self, table: str, record: dict[str, Any]) -> dict[str, Any]:
        resp = request("POST", self._url(table), body=record, headers=self._headers())
        return resp["result"]

    def update(self, table: str, sys_id: str, fields: dict[str, Any]) -> dict[str, Any]:
        resp = request("PATCH", self._url(table, sys_id), body=fields, headers=self._headers())
        return resp["result"]

    def upsert(self, table: str, key_field: str, record: dict[str, Any]) -> dict[str, Any]:
        """Create a record or update the one whose key_field matches (idempotent seeding)."""
        existing = self.query(table, f"{key_field}={record[key_field]}", limit=1)
        if existing:
            return self.update(table, existing[0]["sys_id"], record)
        return self.create(table, record)

    # -- incidents -------------------------------------------------------
    def incident_by_number(self, number: str) -> dict[str, Any] | None:
        rows = self.query("incident", f"number={number}", limit=1)
        return rows[0] if rows else None

    def find_incidents(self, sysparm_query: str) -> list[dict[str, Any]]:
        return self.query("incident", sysparm_query + "^ORDERBYDESCsys_created_on")

    def add_work_note(self, table: str, sys_id: str, note: str) -> None:
        self.update(table, sys_id, {"work_notes": note})

    def wait_for(
        self,
        table: str,
        sysparm_query: str,
        *,
        timeout_s: int = 600,
        poll_s: int = 15,
    ) -> dict[str, Any] | None:
        """Poll until a record matching the query exists, or time out."""
        deadline = time.monotonic() + timeout_s
        while time.monotonic() < deadline:
            rows = self.query(table, sysparm_query, limit=1)
            if rows:
                return rows[0]
            time.sleep(poll_s)
        return None

    def journal(self, sys_id: str, element: str = "work_notes") -> list[dict[str, Any]]:
        """Work notes / comments on a record, oldest first."""
        return self.query(
            "sys_journal_field",
            f"element_id={sys_id}^element={element}^ORDERBYsys_created_on",
            fields=["value", "sys_created_on", "sys_created_by"],
            limit=500,
        )
