"""Incident store (SQLite) + append-only JSONL audit log.

Lifecycle (enforced here, not by the agent's good behaviour):

    investigating ──record_action──▶ remediating
         │  ▲                             │
         │  └──────── verify fails ◀──────┤
         ▼                                ▼
      verify passes ─────────────────▶ verified ──close──▶ closed
         (self-resolved, no actions)      │
                                          └─record_action─▶ remediating (verification invalidated)
    any open state ──escalate──▶ escalated

- Remediation needs at least one recorded finding (diagnose before acting).
- close() needs a fresh, passing verification recorded *after* the last action.
"""

from __future__ import annotations

import json
import secrets
import sqlite3
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .errors import PolicyError, ValidationError

INVESTIGATING = "investigating"
REMEDIATING = "remediating"
VERIFIED = "verified"
CLOSED = "closed"
ESCALATED = "escalated"
OPEN_STATES = (INVESTIGATING, REMEDIATING, VERIFIED)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS incidents (
    id TEXT PRIMARY KEY,
    fingerprint TEXT NOT NULL,
    alertname TEXT NOT NULL,
    labels TEXT NOT NULL,
    status TEXT NOT NULL,
    opened_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    last_action_at REAL,
    verified_at REAL,
    verification TEXT,
    root_cause TEXT,
    fix_summary TEXT,
    closed_at REAL
);
CREATE INDEX IF NOT EXISTS incidents_fp ON incidents(fingerprint, status);
CREATE TABLE IF NOT EXISTS findings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT NOT NULL REFERENCES incidents(id),
    at REAL NOT NULL,
    text TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT NOT NULL REFERENCES incidents(id),
    at REAL NOT NULL,
    action TEXT NOT NULL,
    target TEXT NOT NULL,
    params TEXT NOT NULL,
    reason TEXT NOT NULL,
    dry_run INTEGER NOT NULL,
    ok INTEGER NOT NULL,
    output TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS actions_target ON actions(action, target, at);
"""


@dataclass
class Incident:
    id: str
    fingerprint: str
    alertname: str
    labels: dict[str, str]
    status: str
    opened_at: float
    updated_at: float
    last_action_at: float | None = None
    verified_at: float | None = None
    verification: dict | None = None
    root_cause: str | None = None
    fix_summary: str | None = None
    closed_at: float | None = None
    findings: list[dict] = field(default_factory=list)
    actions: list[dict] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        def ts(v: float | None) -> str | None:
            return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(v)) if v else None

        return {
            "id": self.id,
            "fingerprint": self.fingerprint,
            "alertname": self.alertname,
            "labels": self.labels,
            "status": self.status,
            "opened_at": ts(self.opened_at),
            "last_action_at": ts(self.last_action_at),
            "verified_at": ts(self.verified_at),
            "verification": self.verification,
            "root_cause": self.root_cause,
            "fix_summary": self.fix_summary,
            "closed_at": ts(self.closed_at),
            "findings": [{"at": ts(f["at"]), "text": f["text"]} for f in self.findings],
            "actions": [
                {"at": ts(a["at"]), "action": a["action"], "target": a["target"], "dry_run": bool(a["dry_run"]),
                 "ok": bool(a["ok"]), "reason": a["reason"]}
                for a in self.actions
            ],
        }


class Store:
    def __init__(self, state_dir: Path, clock=time.time):
        state_dir.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(state_dir / "incidents.sqlite3", isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(_SCHEMA)
        self.audit_path = state_dir / "audit.jsonl"
        self.clock = clock

    # ── audit ────────────────────────────────────────────────────────────
    def audit(self, event: str, **data: Any) -> None:
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(self.clock())), "event": event, **data}
        with self.audit_path.open("a") as f:
            f.write(json.dumps(rec, default=str) + "\n")

    # ── reads ────────────────────────────────────────────────────────────
    def get(self, incident_id: str) -> Incident:
        row = self.db.execute("SELECT * FROM incidents WHERE id = ?", (incident_id,)).fetchone()
        if not row:
            raise ValidationError(f"unknown incident {incident_id!r}")
        inc = Incident(
            id=row["id"], fingerprint=row["fingerprint"], alertname=row["alertname"],
            labels=json.loads(row["labels"]), status=row["status"], opened_at=row["opened_at"],
            updated_at=row["updated_at"], last_action_at=row["last_action_at"], verified_at=row["verified_at"],
            verification=json.loads(row["verification"]) if row["verification"] else None,
            root_cause=row["root_cause"], fix_summary=row["fix_summary"], closed_at=row["closed_at"],
        )
        inc.findings = [dict(r) for r in self.db.execute(
            "SELECT at, text FROM findings WHERE incident_id = ? ORDER BY id", (incident_id,))]
        inc.actions = [dict(r) for r in self.db.execute(
            "SELECT * FROM actions WHERE incident_id = ? ORDER BY id", (incident_id,))]
        return inc

    def open_for_fingerprint(self, fingerprint: str) -> Incident | None:
        row = self.db.execute(
            f"SELECT id FROM incidents WHERE fingerprint = ? AND status IN ({','.join('?' * len(OPEN_STATES))}) "
            "ORDER BY opened_at DESC LIMIT 1", (fingerprint, *OPEN_STATES)).fetchone()
        return self.get(row["id"]) if row else None

    def list(self, status: str | None = None, limit: int = 50) -> list[Incident]:
        q, args = "SELECT id FROM incidents", []
        if status:
            q += " WHERE status = ?"
            args.append(status)
        q += " ORDER BY opened_at DESC LIMIT ?"
        return [self.get(r["id"]) for r in self.db.execute(q, (*args, limit))]

    def real_actions_since(self, since: float) -> int:
        return self.db.execute("SELECT COUNT(*) FROM actions WHERE dry_run = 0 AND at >= ?", (since,)).fetchone()[0]

    def last_action_on(self, action: str, target: str) -> float | None:
        row = self.db.execute(
            "SELECT MAX(at) FROM actions WHERE action = ? AND target = ? AND dry_run = 0", (action, target)).fetchone()
        return row[0]

    # ── transitions ──────────────────────────────────────────────────────
    def open(self, fingerprint: str, alertname: str, labels: dict[str, str]) -> tuple[Incident, bool]:
        existing = self.open_for_fingerprint(fingerprint)
        if existing:
            return existing, False
        now = self.clock()
        iid = f"inc-{time.strftime('%Y%m%d', time.gmtime(now))}-{secrets.token_hex(3)}"
        self.db.execute(
            "INSERT INTO incidents (id, fingerprint, alertname, labels, status, opened_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)", (iid, fingerprint, alertname, json.dumps(labels), INVESTIGATING, now, now))
        self.audit("incident_opened", incident=iid, fingerprint=fingerprint, alertname=alertname)
        return self.get(iid), True

    def _require_open(self, inc: Incident) -> None:
        if inc.status not in OPEN_STATES:
            raise PolicyError(f"incident {inc.id} is {inc.status}; open a new investigation if the alert fires again")

    def add_finding(self, incident_id: str, text: str) -> Incident:
        inc = self.get(incident_id)
        self._require_open(inc)
        if len(text.strip()) < 10:
            raise ValidationError("finding is too short to be useful — state what you observed and what it implies")
        now = self.clock()
        self.db.execute("INSERT INTO findings (incident_id, at, text) VALUES (?, ?, ?)", (incident_id, now, text.strip()))
        self.db.execute("UPDATE incidents SET updated_at = ? WHERE id = ?", (now, incident_id))
        self.audit("finding", incident=incident_id, text=text.strip())
        return self.get(incident_id)

    def require_can_remediate(self, inc: Incident) -> None:
        self._require_open(inc)
        if not inc.findings:
            raise PolicyError(
                f"incident {inc.id} has no recorded findings — record_finding with your diagnosis before remediating")

    def record_action(self, incident_id: str, action: str, target: str, params: dict, reason: str,
                      dry_run: bool, ok: bool, output: str) -> None:
        now = self.clock()
        self.db.execute(
            "INSERT INTO actions (incident_id, at, action, target, params, reason, dry_run, ok, output) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (incident_id, now, action, target, json.dumps(params), reason, int(dry_run), int(ok), output))
        if not dry_run:
            # Any real change invalidates a previous verification.
            self.db.execute(
                "UPDATE incidents SET status = ?, last_action_at = ?, verified_at = NULL, verification = NULL, "
                "updated_at = ? WHERE id = ?", (REMEDIATING, now, now, incident_id))
        self.audit("action", incident=incident_id, action=action, target=target, params=params, reason=reason,
                   dry_run=dry_run, ok=ok)

    def record_verification(self, incident_id: str, passed: bool, details: dict) -> Incident:
        inc = self.get(incident_id)
        self._require_open(inc)
        now = self.clock()
        if passed:
            self.db.execute(
                "UPDATE incidents SET status = ?, verified_at = ?, verification = ?, updated_at = ? WHERE id = ?",
                (VERIFIED, now, json.dumps(details), now, incident_id))
        else:
            back = REMEDIATING if inc.last_action_at else INVESTIGATING
            self.db.execute(
                "UPDATE incidents SET status = ?, verified_at = NULL, verification = ?, updated_at = ? WHERE id = ?",
                (back, json.dumps(details), now, incident_id))
        self.audit("verification", incident=incident_id, passed=passed, details=details)
        return self.get(incident_id)

    def require_can_close(self, inc: Incident, max_age_s: float) -> None:
        if inc.status != VERIFIED or not inc.verified_at:
            raise PolicyError(
                f"incident {inc.id} is {inc.status}, not verified — run verify_resolution and get a pass before closing")
        if inc.last_action_at and inc.verified_at <= inc.last_action_at:
            raise PolicyError("verification predates the last remediation — verify again")
        if self.clock() - inc.verified_at > max_age_s:
            raise PolicyError(f"verification is older than {int(max_age_s // 60)} min — verify again before closing")

    def close(self, incident_id: str, root_cause: str, fix_summary: str) -> Incident:
        now = self.clock()
        self.db.execute(
            "UPDATE incidents SET status = ?, root_cause = ?, fix_summary = ?, closed_at = ?, updated_at = ? "
            "WHERE id = ?", (CLOSED, root_cause, fix_summary, now, now, incident_id))
        self.audit("incident_closed", incident=incident_id, root_cause=root_cause, fix_summary=fix_summary)
        return self.get(incident_id)

    def escalate(self, incident_id: str, summary: str) -> Incident:
        inc = self.get(incident_id)
        self._require_open(inc)
        now = self.clock()
        self.db.execute(
            "UPDATE incidents SET status = ?, root_cause = ?, closed_at = ?, updated_at = ? WHERE id = ?",
            (ESCALATED, summary, now, now, incident_id))
        self.audit("incident_escalated", incident=incident_id, summary=summary)
        return self.get(incident_id)
