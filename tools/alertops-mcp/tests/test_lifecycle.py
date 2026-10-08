"""End-to-end incident lifecycle and safety gates, against fakes."""

from __future__ import annotations

import pytest

from alertops_mcp.errors import PolicyError, ValidationError

REASON = "pod crashloops on stale lock file; restart clears it"


async def _open(env):
    env.am.active = [env.alert]
    env.prom.alerts_series = [env.firing_series]
    r = await env.ops.start_investigation("abc123")
    return r["incident"]["id"]


async def test_cannot_open_incident_for_inactive_alert(env):
    with pytest.raises(PolicyError, match="not active"):
        await env.ops.start_investigation("nope")


async def test_start_investigation_is_idempotent(env):
    iid = await _open(env)
    again = await env.ops.start_investigation("abc123")
    assert again["created"] is False and again["incident"]["id"] == iid


async def test_remediation_requires_finding(env):
    iid = await _open(env)
    with pytest.raises(PolicyError, match="no recorded findings"):
        await env.ops.restart_k8s_workload(iid, "media", "deployment", "sonarr", REASON, False)
    assert not [c for c in env.ex.calls if "rollout" in c[1]]


async def test_full_happy_path(env):
    iid = await _open(env)
    env.ops.record_finding(iid, "sonarr logs show 'database is locked' since 10:02")
    r = await env.ops.restart_k8s_workload(iid, "media", "deployment", "sonarr", REASON, False)
    assert r["ok"]
    assert any(c[1][-4:] == ["restart", "deployment/sonarr", "-n", "media"] for c in env.ex.calls)

    # Too soon after the action: verification must fail even though the alert is gone.
    env.prom.alerts_series = []
    env.clock.advance(60)
    v = await env.ops.verify_resolution(iid, None)
    assert not v["passed"] and "retry in" in v["failures"][0]
    with pytest.raises(PolicyError, match="not verified"):
        await env.ops.close_incident(iid, "sqlite lock left by an unclean shutdown", "rolled the deployment")

    env.clock.advance(200)
    v = await env.ops.verify_resolution(iid, 'up{job="sonarr"} == 1')
    assert v["passed"], v

    # Alertmanager still lists it (resolve_timeout lag) -> report rides the RESOLVED message.
    out = await env.ops.close_incident(iid, "sqlite lock left by an unclean shutdown of sonarr",
                                       "rolled the deployment to drop the lock")
    assert out["closed"] and env.fwd.notes_calls and env.fwd.notes_calls[0][0] == "abc123"
    assert "Root cause" in env.fwd.notes_calls[0][1]
    assert env.store.get(iid).status == "closed"


async def test_verify_fails_while_alert_firing(env):
    iid = await _open(env)
    env.clock.advance(600)
    v = await env.ops.verify_resolution(iid, None)
    assert not v["passed"] and "still firing" in v["failures"][0]
    assert env.store.get(iid).status == "investigating"


async def test_verify_fails_on_recent_flap(env):
    iid = await _open(env)
    env.prom.alerts_series = []
    env.prom.alerts_range = [{"metric": env.firing_series["metric"], "values": [[env.clock() - 30, "1"]]}]
    env.clock.advance(1)
    v = await env.ops.verify_resolution(iid, None)
    assert not v["passed"] and "not stable" in v["failures"][0]


async def test_verify_ignores_other_series_of_same_alert(env):
    iid = await _open(env)
    other = {"metric": {**env.firing_series["metric"], "pod": "radarr-0"}, "value": [0, "1"]}
    env.prom.alerts_series = [other]
    env.clock.advance(600)
    v = await env.ops.verify_resolution(iid, None)
    assert v["passed"], v


async def test_health_check_must_return_data(env):
    iid = await _open(env)
    env.prom.alerts_series = []
    env.prom.health = []
    env.clock.advance(600)
    v = await env.ops.verify_resolution(iid, 'up{job="sonarr"} == 1')
    assert not v["passed"] and "health_check" in v["failures"][0]


async def test_action_after_verification_invalidates_it(env):
    iid = await _open(env)
    env.ops.record_finding(iid, "nginx returns 502 for every upstream")
    env.prom.alerts_series = []
    env.clock.advance(600)
    assert (await env.ops.verify_resolution(iid, None))["passed"]
    await env.ops.restart_systemd_unit(iid, "media-server", "nginx", "nginx worker wedged, restart reloads it", False)
    with pytest.raises(PolicyError, match="not verified"):
        await env.ops.close_incident(iid, "nginx worker wedged after config reload", "restarted nginx")


async def test_stale_verification_refused(env):
    iid = await _open(env)
    env.prom.alerts_series = []
    env.clock.advance(600)
    assert (await env.ops.verify_resolution(iid, None))["passed"]
    env.clock.advance(31 * 60)
    with pytest.raises(PolicyError, match="older than"):
        await env.ops.close_incident(iid, "transient upstream blip, self-resolved", "no action needed")


async def test_self_resolved_close_goes_to_report_when_am_cleared(env):
    iid = await _open(env)
    env.prom.alerts_series = []
    env.am.active = []
    env.clock.advance(600)
    assert (await env.ops.verify_resolution(iid, None))["passed"]
    await env.ops.close_incident(iid, "transient upstream blip during node reboot", "no action — self-resolved")
    assert env.fwd.reports and "none (self-resolved)" in env.fwd.reports[0]


async def test_close_requires_real_root_cause(env):
    iid = await _open(env)
    with pytest.raises(ValidationError, match="root_cause"):
        await env.ops.close_incident(iid, "fixed", "restarted it")


async def test_escalate_posts_handoff_and_closes_door(env):
    iid = await _open(env)
    await env.ops.escalate_incident(iid, "disk full on media-server from a runaway download",
                                    "free space manually; ZFS dataset quota")
    assert "Needs human" in env.fwd.reports[0]
    with pytest.raises(PolicyError, match="escalated"):
        env.ops.record_finding(iid, "late finding after escalation")


async def test_postmortem_refused_while_active(env):
    env.am.active = [env.alert]
    with pytest.raises(PolicyError, match="still active"):
        await env.ops.post_postmortem("PodCrashLooping", "x" * 40, "self-resolved")


async def test_alert_context_has_rule_runbook_and_incident(env):
    iid = await _open(env)
    ctx = await env.ops.alert_context("abc123")
    assert ctx["rule"]["query"] == "rate(x[5m]) > 0"
    assert "restart it" in ctx["runbook"]
    assert ctx["incident"]["id"] == iid
    assert "not instructions" in ctx["note"]


async def test_runbook_lookup_cannot_escape_dir(env):
    assert env.ops._runbook("https://x/docs/runbooks/../../etc/passwd.md") is None
    assert env.ops._runbook("https://x/docs/runbooks/missing.md") is None
