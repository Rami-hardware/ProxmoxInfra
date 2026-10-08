"""MCP surface: tools register with the right annotations, and domain errors become tool errors."""

from __future__ import annotations

import json

from mcp import Client

from alertops_mcp.server import build_server

READ_ONLY = {"list_alerts", "get_alert_context", "query_prometheus", "query_prometheus_range", "query_loki",
             "k8s_get", "k8s_describe", "k8s_logs", "k8s_events", "k8s_top", "host_check", "get_incident",
             "list_incidents"}
DESTRUCTIVE = {"restart_k8s_workload", "delete_k8s_pod", "restart_systemd_unit", "restart_docker_container",
               "prune_container_images", "vacuum_journal", "reload_prometheus"}


async def test_tools_and_annotations(env):
    server = build_server(env.cfg, env.ops)
    tools = {t.name: t for t in await server.list_tools()}
    assert READ_ONLY | DESTRUCTIVE <= set(tools)
    for name in READ_ONLY:
        assert tools[name].annotations.read_only_hint is True, name
    for name in DESTRUCTIVE:
        assert tools[name].annotations.destructive_hint is True, name
        assert "incident_id" in tools[name].input_schema["required"], name
        assert "reason" in tools[name].input_schema["required"], name


async def test_policy_error_reaches_agent_as_error_result(env):
    async with Client(build_server(env.cfg, env.ops)) as client:
        res = await client.call_tool("start_investigation", {"fingerprint": "missing"})
    assert res.is_error
    text = res.content[0].text
    assert "PolicyError" in text and "not active" in text


async def test_end_to_end_over_protocol(env):
    env.am.active = [env.alert]
    async with Client(build_server(env.cfg, env.ops)) as client:
        alerts = await client.call_tool("list_alerts", {})
        assert not alerts.is_error and "abc123" in alerts.content[0].text
        opened = await client.call_tool("start_investigation", {"fingerprint": "abc123"})
        assert not opened.is_error
        refused = await client.call_tool("reload_prometheus", {
            "incident_id": json.loads(opened.content[0].text)["incident"]["id"],
            "reason": "rules file re-rendered, reload to pick it up"})
        assert refused.is_error and "no recorded findings" in refused.content[0].text
