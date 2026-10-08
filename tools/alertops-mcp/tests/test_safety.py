"""Allowlists, rate limits, kill switch, input validation."""

from __future__ import annotations

import json

import pytest

from alertops_mcp import validation as v
from alertops_mcp.errors import PolicyError, ValidationError
from alertops_mcp.executor import CmdResult

REASON = "service wedged per journal; restart is the documented fix"


@pytest.fixture
async def iid(env):
    env.am.active = [env.alert]
    r = await env.ops.start_investigation("abc123")
    env.ops.record_finding(r["incident"]["id"], "journal shows the worker deadlocked at 10:01")
    return r["incident"]["id"]


async def test_namespace_not_allowlisted(env, iid):
    with pytest.raises(ValidationError, match="not allowed in namespace"):
        await env.ops.restart_k8s_workload(iid, "kube-system", "deployment", "coredns", REASON, False)


async def test_unit_not_allowlisted(env, iid):
    with pytest.raises(ValidationError, match="allowlist"):
        await env.ops.restart_systemd_unit(iid, "media-server", "docker", REASON, False)


async def test_host_without_remediation(env, iid):
    with pytest.raises(ValidationError, match="no remediation allowed"):
        await env.ops.restart_systemd_unit(iid, "host-node", "pveproxy", REASON, False)


async def test_cooldown_and_incident_cap(env, iid):
    await env.ops.restart_systemd_unit(iid, "media-server", "nginx", REASON, False)
    with pytest.raises(PolicyError, match="cooldown"):
        await env.ops.restart_systemd_unit(iid, "media-server", "nginx.service", REASON, False)
    env.clock.advance(16 * 60)
    await env.ops.restart_systemd_unit(iid, "media-server", "nginx", REASON, False)
    env.clock.advance(16 * 60)
    with pytest.raises(PolicyError, match="limit 2"):
        await env.ops.restart_systemd_unit(iid, "media-server", "nginx", REASON, False)


async def test_dry_run_runs_nothing_and_ignores_limits(env, iid):
    r = await env.ops.restart_k8s_workload(iid, "media", "deployment", "sonarr", REASON, True)
    assert r["dry_run"] and "rollout restart deployment/sonarr" in r["would_run"]
    assert not [c for c in env.ex.calls if "restart" in c[1]]
    assert env.store.get(iid).status == "investigating"


async def test_kill_switch(env, iid):
    env.cfg.state_dir.mkdir(parents=True, exist_ok=True)
    env.cfg.kill_switch.touch()
    with pytest.raises(PolicyError, match="disabled"):
        await env.ops.restart_systemd_unit(iid, "media-server", "nginx", REASON, False)


async def test_delete_bare_pod_refused(env, iid):
    env.ex.responses["get pod"] = json.dumps({"metadata": {"ownerReferences": []}})
    with pytest.raises(PolicyError, match="not controller-managed"):
        await env.ops.delete_k8s_pod(iid, "media", "debug-pod", REASON, False)


async def test_delete_managed_pod(env, iid):
    env.ex.responses["get pod"] = json.dumps(
        {"metadata": {"ownerReferences": [{"kind": "ReplicaSet", "controller": True}]}})
    r = await env.ops.delete_k8s_pod(iid, "media", "sonarr-abc", REASON, False)
    assert r["ok"]


async def test_failed_precheck_records_nothing(env, iid):
    env.ex.responses["get deployment/ghost"] = CmdResult("git-k3s-server", "x", 1, "", "NotFound", 0.1)
    with pytest.raises(ValidationError, match="must exist"):
        await env.ops.restart_k8s_workload(iid, "media", "deployment", "ghost", REASON, False)
    assert env.store.get(iid).actions == []


async def test_short_reason_refused(env, iid):
    with pytest.raises(ValidationError, match="reason"):
        await env.ops.restart_systemd_unit(iid, "media-server", "nginx", "fix", False)


async def test_journal_vacuum_floor(env, iid):
    with pytest.raises(ValidationError, match=">="):
        await env.ops.vacuum_journal(iid, "media-server", "10M", REASON, False)


async def test_root_host_gets_no_sudo(env):
    await env.ops.host_check("host-node", "zpool_status", None, 30, None)
    await env.ops.host_check("media-server", "zpool_status", None, 30, None)
    assert env.ex.calls[0][1][0] == "zpool" and env.ex.calls[1][1][:2] == ["sudo", "-n"]


async def test_host_check_requires_read_allowlist(env):
    with pytest.raises(ValidationError, match="not allowed"):
        await env.ops.host_check("monitoring-server", "disk", None, 30, None)


async def test_secrets_not_readable(env):
    with pytest.raises(ValidationError, match="not allowed"):
        await env.ops.k8s_get("secrets", "media", None, None, "wide")


@pytest.mark.parametrize("bad", ["a;rm -rf /", "$(id)", "Foo", "a b", "-n", "x" * 300, ""])
def test_k8s_name_rejects(bad):
    with pytest.raises(ValidationError):
        v.k8s_name(bad)


@pytest.mark.parametrize("bad", ["nginx;reboot", "../x.service", "a b.service", "$(x).service"])
def test_unit_rejects(bad):
    with pytest.raises(ValidationError):
        v.systemd_unit(bad)


@pytest.mark.parametrize("bad", ["relative", "/a/../etc", "/a b", "/$(id)", "//x"])
def test_path_rejects(bad):
    with pytest.raises(ValidationError):
        v.abs_path(bad)


def test_inventory_parsing(env):
    assert env.ops.hosts["media-server"].address == "10.0.0.201"
    assert env.ops.hosts["host-node"].user == "root"
    assert "gateway-vm" not in env.ops.hosts  # :children entries are groups, not hosts
