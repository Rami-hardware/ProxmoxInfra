"""Configuration loading. One YAML file, paths resolved relative to it."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml

DEFAULT_CONFIG = Path(__file__).resolve().parents[2] / "config.yaml"


@dataclass(frozen=True)
class SSHConfig:
    key_file: Path
    connect_timeout_seconds: int = 10
    command_timeout_seconds: int = 90
    strict_host_key_checking: str = "yes"


@dataclass(frozen=True)
class KubernetesConfig:
    via_host: str
    kubectl: tuple[str, ...]
    read_namespaces: frozenset[str]
    remediation_namespaces: frozenset[str]


@dataclass(frozen=True)
class HostRemediation:
    systemd_units: frozenset[str] = frozenset()
    docker_containers: frozenset[str] = frozenset()


@dataclass(frozen=True)
class RemediationConfig:
    enabled: bool = True
    max_actions_per_incident: int = 3
    max_actions_per_hour: int = 10
    target_cooldown_minutes: int = 15
    journal_vacuum_min_size: str = "200M"


@dataclass(frozen=True)
class VerificationConfig:
    stable_minutes: int = 3
    step_seconds: int = 15
    max_age_minutes: int = 30


@dataclass(frozen=True)
class CloseConfig:
    min_root_cause_chars: int = 30
    min_fix_summary_chars: int = 15


@dataclass(frozen=True)
class Config:
    alertmanager_url: str
    prometheus_url: str
    loki_url: str
    forwarder_url: str
    repo_dir: Path
    inventory: Path
    runbooks_dir: Path
    state_dir: Path
    ssh: SSHConfig
    kubernetes: KubernetesConfig
    read_hosts: frozenset[str]
    host_remediation: dict[str, HostRemediation] = field(default_factory=dict)
    remediation: RemediationConfig = RemediationConfig()
    verification: VerificationConfig = VerificationConfig()
    close: CloseConfig = CloseConfig()
    http_timeout_seconds: float = 15
    max_output_chars: int = 12000

    @property
    def kill_switch(self) -> Path:
        return self.state_dir / "DISABLE_REMEDIATION"


def _path(base: Path, value: str) -> Path:
    p = Path(os.path.expanduser(value))
    return (p if p.is_absolute() else base / p).resolve()


def load_config(path: str | os.PathLike | None = None) -> Config:
    cfg_path = Path(path or os.environ.get("ALERTOPS_CONFIG") or DEFAULT_CONFIG).resolve()
    raw = yaml.safe_load(cfg_path.read_text()) or {}
    base = cfg_path.parent
    repo = _path(base, raw.get("repo_dir", "."))

    ssh = raw.get("ssh", {})
    k8s = raw["kubernetes"]
    hosts = raw.get("hosts", {})
    return Config(
        alertmanager_url=raw["alertmanager_url"].rstrip("/"),
        prometheus_url=raw["prometheus_url"].rstrip("/"),
        loki_url=raw["loki_url"].rstrip("/"),
        forwarder_url=raw["forwarder_url"].rstrip("/"),
        repo_dir=repo,
        inventory=_path(repo, raw.get("inventory", "Ansbile/inventory.ini")),
        runbooks_dir=_path(repo, raw.get("runbooks_dir", "docs/runbooks")),
        state_dir=_path(base, raw.get("state_dir", "~/.local/state/alertops")),
        ssh=SSHConfig(
            key_file=_path(base, ssh.get("key_file", "~/.ssh/id_rsa")),
            connect_timeout_seconds=int(ssh.get("connect_timeout_seconds", 10)),
            command_timeout_seconds=int(ssh.get("command_timeout_seconds", 90)),
            strict_host_key_checking=str(ssh.get("strict_host_key_checking", "yes")),
        ),
        kubernetes=KubernetesConfig(
            via_host=k8s["via_host"],
            kubectl=tuple(k8s.get("kubectl", ["kubectl"])),
            read_namespaces=frozenset(k8s.get("read_namespaces", [])),
            remediation_namespaces=frozenset(k8s.get("remediation_namespaces", [])),
        ),
        read_hosts=frozenset(hosts.get("read", [])),
        host_remediation={
            name: HostRemediation(
                systemd_units=frozenset((spec or {}).get("systemd_units", [])),
                docker_containers=frozenset((spec or {}).get("docker_containers", [])),
            )
            for name, spec in (hosts.get("remediation") or {}).items()
        },
        remediation=RemediationConfig(**(raw.get("remediation") or {})),
        verification=VerificationConfig(**(raw.get("verification") or {})),
        close=CloseConfig(**(raw.get("close") or {})),
        http_timeout_seconds=float(raw.get("http_timeout_seconds", 15)),
        max_output_chars=int(raw.get("max_output_chars", 12000)),
    )
