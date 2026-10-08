"""Error types. All are surfaced to the agent as tool errors with an actionable message."""


class AlertOpsError(Exception):
    """Base class."""


class ValidationError(AlertOpsError):
    """Bad input (name format, not in an allowlist, out of range)."""


class PolicyError(AlertOpsError):
    """The request is well-formed but the safety policy or incident state machine refuses it."""


class UpstreamError(AlertOpsError):
    """Alertmanager / Prometheus / Loki / forwarder / ssh failed."""
