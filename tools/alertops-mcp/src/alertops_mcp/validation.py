"""Input validation. Every value that reaches a remote command passes through here first.

Commands are additionally built as argv and shell-quoted with shlex.join, so validation
is defense in depth, not the only barrier.
"""

from __future__ import annotations

import re

from .errors import ValidationError

_K8S_NAME = re.compile(r"^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$")
_LABEL_SELECTOR = re.compile(r"^[A-Za-z0-9_./=,!-]{1,256}$")
_UNIT = re.compile(r"^[A-Za-z0-9@_.:-]{1,128}\.(service|timer|socket)$")
_CONTAINER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
_PATH = re.compile(r"^/[A-Za-z0-9_./@+-]{0,255}$")
_SIZE = re.compile(r"^([1-9][0-9]{0,4})([KMG])$")

K8S_READ_RESOURCES = frozenset({
    "pods", "deployments", "statefulsets", "daemonsets", "replicasets", "services",
    "endpoints", "persistentvolumeclaims", "persistentvolumes", "nodes", "events",
    "ingresses", "configmaps", "jobs", "cronjobs", "applications",
})
CLUSTER_SCOPED = frozenset({"nodes", "persistentvolumes"})
K8S_RESTARTABLE = frozenset({"deployment", "statefulset", "daemonset"})


def k8s_name(value: str, what: str = "name") -> str:
    if not _K8S_NAME.fullmatch(value or ""):
        raise ValidationError(f"invalid Kubernetes {what}: {value!r}")
    return value


def label_selector(value: str) -> str:
    if not _LABEL_SELECTOR.fullmatch(value):
        raise ValidationError(f"invalid label selector: {value!r} (allowed: key=value[,key!=value])")
    return value


def k8s_resource(value: str) -> str:
    v = value.lower()
    if v not in K8S_READ_RESOURCES:
        raise ValidationError(f"resource {value!r} not allowed; allowed: {sorted(K8S_READ_RESOURCES)}")
    return v


def systemd_unit(value: str) -> str:
    if not value.endswith((".service", ".timer", ".socket")):
        value = f"{value}.service"
    if not _UNIT.fullmatch(value):
        raise ValidationError(f"invalid systemd unit: {value!r}")
    return value


def container(value: str) -> str:
    if not _CONTAINER.fullmatch(value):
        raise ValidationError(f"invalid container name: {value!r}")
    return value


def abs_path(value: str) -> str:
    if not _PATH.fullmatch(value) or "/../" in f"{value}/" or "//" in value:
        raise ValidationError(f"invalid path: {value!r} (absolute, no '..')")
    return value


def size_to_bytes(value: str) -> int:
    m = _SIZE.fullmatch(value.upper())
    if not m:
        raise ValidationError(f"invalid size {value!r}; expected e.g. 500M or 2G")
    return int(m.group(1)) * {"K": 1 << 10, "M": 1 << 20, "G": 1 << 30}[m.group(2)]


def bounded(value: int, lo: int, hi: int, what: str) -> int:
    if not lo <= value <= hi:
        raise ValidationError(f"{what} must be between {lo} and {hi}, got {value}")
    return value
