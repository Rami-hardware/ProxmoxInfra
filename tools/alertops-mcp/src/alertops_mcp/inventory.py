"""Minimal Ansible INI inventory parser — the repo inventory is the single source of truth for host IPs."""

from __future__ import annotations

import shlex
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Host:
    name: str
    address: str
    user: str


def parse_inventory(path: Path) -> dict[str, Host]:
    hosts: dict[str, Host] = {}
    section = ""
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("["):
            section = line.strip("[]")
            continue
        if section.endswith((":children", ":vars")):
            continue
        name, *pairs = shlex.split(line)
        kv = dict(p.split("=", 1) for p in pairs if "=" in p)
        hosts[name] = Host(name=name, address=kv.get("ansible_host", name), user=kv.get("ansible_user", "root"))
    return hosts
