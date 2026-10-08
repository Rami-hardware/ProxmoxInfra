from __future__ import annotations

import shlex
from pathlib import Path

import pytest

from alertops_mcp.config import load_config
from alertops_mcp.executor import CmdResult
from alertops_mcp.inventory import parse_inventory
from alertops_mcp.service import AlertOps
from alertops_mcp.store import Store

INVENTORY = """
[gateway-vm]
gateway-server ansible_host=10.0.0.200 ansible_user=gateway

[media-vm]
media-server ansible_host=10.0.0.201 ansible_user=media

[git-k3s-server-vm]
git-k3s-server ansible_host=10.0.0.204 ansible_user=github

[host-node]
host-node ansible_host=10.0.0.250 ansible_user=root

[all_docker_hosts:children]
gateway-vm
"""

CONFIG = """
alertmanager_url: http://am
prometheus_url: http://prom
loki_url: http://loki
forwarder_url: http://fwd
repo_dir: repo
inventory: inventory.ini
runbooks_dir: runbooks
state_dir: state
kubernetes:
  via_host: git-k3s-server
  kubectl: [sudo, -n, k3s, kubectl]
  read_namespaces: [media, monitoring, kube-system]
  remediation_namespaces: [media]
hosts:
  read: [gateway-server, media-server, git-k3s-server, host-node]
  remediation:
    media-server:
      systemd_units: [nginx.service]
      docker_containers: [docker_exporter]
remediation:
  max_actions_per_incident: 2
  max_actions_per_hour: 5
  target_cooldown_minutes: 15
verification:
  stable_minutes: 3
  step_seconds: 15
  max_age_minutes: 30
"""


class Clock:
    def __init__(self, t: float = 1_800_000_000.0):
        self.t = t

    def __call__(self) -> float:
        return self.t

    def advance(self, seconds: float) -> None:
        self.t += seconds


class FakeExecutor:
    def __init__(self, hosts):
        self.hosts = hosts
        self.calls: list[tuple[str, list[str]]] = []
        self.responses: dict[str, CmdResult | str] = {}  # substring of command -> stdout

    def host(self, name):
        from alertops_mcp.errors import ValidationError
        if name not in self.hosts:
            raise ValidationError(f"unknown host {name!r}")
        return self.hosts[name]

    async def run(self, host, argv, timeout=None):
        self.host(host)
        self.calls.append((host, argv))
        cmd = shlex.join(argv)
        for key, resp in self.responses.items():
            if key in cmd:
                if isinstance(resp, CmdResult):
                    return resp
                return CmdResult(host, cmd, 0, resp, "", 0.1)
        return CmdResult(host, cmd, 0, "ok", "", 0.1)

    async def kubectl(self, args, timeout=None):
        return await self.run("git-k3s-server", ["sudo", "-n", "k3s", "kubectl", *args], timeout)


class FakeAM:
    def __init__(self):
        self.active: list[dict] = []

    async def alerts(self, include_silenced=False):
        return self.active

    async def alert(self, fp):
        return next((a for a in self.active if a["fingerprint"] == fp), None)


class FakeProm:
    def __init__(self):
        self.rules = [{"name": "PodCrashLooping", "query": "rate(x[5m]) > 0", "group": "k8s", "duration": 300,
                       "health": "ok", "state": "firing"}]
        self.alerts_series: list[dict] = []     # current ALERTS result
        self.alerts_range: list[dict] = []      # ALERTS in window
        self.health: list[dict] = [{"metric": {"job": "x"}, "value": [0, "1"]}]
        self.reloaded = 0

    async def query(self, q, at=None):
        if q.startswith("ALERTS"):
            return self.alerts_series
        if q.startswith("up"):
            return self.health
        return []

    async def query_range(self, q, start, end, step):
        return self.alerts_range

    async def rule(self, name):
        return next((r for r in self.rules if r["name"] == name), None)

    async def reload(self):
        self.reloaded += 1


class FakeFwd:
    def __init__(self):
        self.notes_calls: list[tuple[str, str]] = []
        self.reports: list[str] = []

    async def notes(self, fp, text):
        self.notes_calls.append((fp, text))

    async def report(self, text):
        self.reports.append(text)


@pytest.fixture
def env(tmp_path: Path):
    (tmp_path / "repo" / "runbooks").mkdir(parents=True)
    (tmp_path / "repo" / "runbooks" / "k8s-workloads.md").write_text("# K8s workloads\nrestart it\n")
    (tmp_path / "repo" / "inventory.ini").write_text(INVENTORY)
    (tmp_path / "config.yaml").write_text(CONFIG)
    cfg = load_config(tmp_path / "config.yaml")
    hosts = parse_inventory(cfg.inventory)
    clock = Clock()
    store = Store(cfg.state_dir, clock=clock)
    ex = FakeExecutor(hosts)
    am, prom, fwd = FakeAM(), FakeProm(), FakeFwd()
    ops = AlertOps(cfg, hosts, store, ex, am, prom, loki=None, forwarder=fwd, clock=clock)

    class Env:
        pass

    e = Env()
    e.cfg, e.ops, e.store, e.ex, e.am, e.prom, e.fwd, e.clock, e.tmp = cfg, ops, store, ex, am, prom, fwd, clock, tmp_path
    e.alert = {
        "fingerprint": "abc123",
        "labels": {"alertname": "PodCrashLooping", "namespace": "media", "pod": "sonarr-1", "severity": "warning"},
        "annotations": {"summary": "crashloop",
                        "runbook_url": "https://github.com/x/y/blob/main/docs/runbooks/k8s-workloads.md"},
        "startsAt": "2026-10-08T10:00:00Z",
        "status": {"state": "active"},
    }
    e.firing_series = {"metric": {"__name__": "ALERTS", "alertname": "PodCrashLooping", "alertstate": "firing",
                                  "namespace": "media", "pod": "sonarr-1", "severity": "warning"},
                       "value": [0, "1"]}
    return e
