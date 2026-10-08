"""HTTP clients for Alertmanager, Prometheus, Loki and the alert-forwarder."""

from __future__ import annotations

import time
from typing import Any

import httpx

from .errors import UpstreamError


class _Base:
    name = "upstream"

    def __init__(self, base_url: str, timeout: float, transport: httpx.AsyncBaseTransport | None = None):
        self.http = httpx.AsyncClient(base_url=base_url, timeout=timeout, transport=transport)

    async def _request(self, method: str, path: str, **kw: Any) -> httpx.Response:
        try:
            r = await self.http.request(method, path, **kw)
        except httpx.HTTPError as e:
            raise UpstreamError(f"{self.name} unreachable ({method} {path}): {e}") from e
        if r.status_code >= 400:
            raise UpstreamError(f"{self.name} {method} {path} -> HTTP {r.status_code}: {r.text[:500]}")
        return r

    async def aclose(self) -> None:
        await self.http.aclose()


class Alertmanager(_Base):
    name = "Alertmanager"

    async def alerts(self, include_silenced: bool = False) -> list[dict]:
        params = {"active": "true", "silenced": str(include_silenced).lower(), "inhibited": str(include_silenced).lower()}
        return (await self._request("GET", "/api/v2/alerts", params=params)).json() or []

    async def alert(self, fingerprint: str) -> dict | None:
        for a in await self.alerts(include_silenced=True):
            if a.get("fingerprint") == fingerprint:
                return a
        return None


class Prometheus(_Base):
    name = "Prometheus"
    _rules_cache: tuple[float, list[dict]] | None = None

    async def _api(self, path: str, params: dict) -> Any:
        body = (await self._request("GET", path, params=params)).json()
        if body.get("status") != "success":
            raise UpstreamError(f"Prometheus {path}: {body.get('errorType')}: {body.get('error')}")
        return body["data"]

    async def query(self, promql: str, at: float | None = None) -> list[dict]:
        params = {"query": promql}
        if at is not None:
            params["time"] = str(at)
        return (await self._api("/api/v1/query", params))["result"]

    async def query_range(self, promql: str, start: float, end: float, step: int) -> list[dict]:
        params = {"query": promql, "start": str(start), "end": str(end), "step": str(step)}
        return (await self._api("/api/v1/query_range", params))["result"]

    async def alert_rules(self) -> list[dict]:
        now = time.monotonic()
        if self._rules_cache and now - self._rules_cache[0] < 60:
            return self._rules_cache[1]
        data = await self._api("/api/v1/rules", {"type": "alert"})
        rules = [{**r, "group": g["name"]} for g in data["groups"] for r in g["rules"]]
        self._rules_cache = (now, rules)
        return rules

    async def rule(self, alertname: str) -> dict | None:
        return next((r for r in await self.alert_rules() if r.get("name") == alertname), None)

    async def reload(self) -> None:
        await self._request("POST", "/-/reload")


class Loki(_Base):
    name = "Loki"

    async def query_range(self, logql: str, start: float, end: float, limit: int) -> dict:
        params = {
            "query": logql,
            "start": str(int(start * 1e9)),
            "end": str(int(end * 1e9)),
            "limit": str(limit),
            "direction": "backward",
        }
        body = (await self._request("GET", "/loki/api/v1/query_range", params=params)).json()
        return body.get("data", {})


class Forwarder(_Base):
    name = "alert-forwarder"

    async def notes(self, fingerprint: str, notes: str) -> None:
        await self._request("POST", "/notes", json={"fingerprint": fingerprint, "notes": notes})

    async def report(self, text: str) -> None:
        await self._request("POST", "/report", json={"text": text})
