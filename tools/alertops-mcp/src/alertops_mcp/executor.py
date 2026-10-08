"""Remote command execution over ssh.

No local shell is ever involved: ssh is exec'd with an argv list, and the remote
command is a single shlex.join()-quoted string built from validated argv.
"""

from __future__ import annotations

import asyncio
import shlex
import time
from dataclasses import dataclass

from .config import Config
from .errors import UpstreamError, ValidationError
from .inventory import Host


@dataclass
class CmdResult:
    host: str
    command: str
    exit_code: int
    stdout: str
    stderr: str
    duration_s: float

    @property
    def ok(self) -> bool:
        return self.exit_code == 0

    def render(self) -> str:
        parts = [f"$ [{self.host}] {self.command}  (exit {self.exit_code}, {self.duration_s:.1f}s)"]
        if self.stdout.strip():
            parts.append(self.stdout.rstrip())
        if self.stderr.strip():
            parts.append(f"[stderr]\n{self.stderr.rstrip()}")
        return "\n".join(parts)


def truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    head = limit * 2 // 3
    tail = limit - head
    return f"{text[:head]}\n... [{len(text) - limit} chars truncated] ...\n{text[-tail:]}"


class SSHExecutor:
    def __init__(self, cfg: Config, hosts: dict[str, Host]):
        self.cfg = cfg
        self.hosts = hosts

    def host(self, name: str) -> Host:
        try:
            return self.hosts[name]
        except KeyError:
            raise ValidationError(f"unknown host {name!r}; inventory hosts: {sorted(self.hosts)}") from None

    async def run(self, host_name: str, argv: list[str], timeout: float | None = None) -> CmdResult:
        host = self.host(host_name)
        remote = shlex.join(argv)
        ssh_argv = [
            "ssh",
            "-o", "BatchMode=yes",
            "-o", f"ConnectTimeout={self.cfg.ssh.connect_timeout_seconds}",
            "-o", f"StrictHostKeyChecking={self.cfg.ssh.strict_host_key_checking}",
            "-o", "LogLevel=ERROR",
            "-i", str(self.cfg.ssh.key_file),
            f"{host.user}@{host.address}",
            "--",
            remote,
        ]
        limit = timeout or self.cfg.ssh.command_timeout_seconds
        start = time.monotonic()
        proc = await asyncio.create_subprocess_exec(
            *ssh_argv,
            stdin=asyncio.subprocess.DEVNULL,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            out, err = await asyncio.wait_for(proc.communicate(), timeout=limit)
        except TimeoutError:
            proc.kill()
            await proc.wait()
            raise UpstreamError(f"[{host_name}] command timed out after {limit}s: {remote}") from None
        if proc.returncode == 255:
            raise UpstreamError(f"[{host_name}] ssh failed: {err.decode(errors='replace').strip()}")
        cap = self.cfg.max_output_chars
        return CmdResult(
            host=host_name,
            command=remote,
            exit_code=proc.returncode,
            stdout=truncate(out.decode(errors="replace"), cap),
            stderr=truncate(err.decode(errors="replace"), cap // 4),
            duration_s=time.monotonic() - start,
        )

    async def kubectl(self, args: list[str], timeout: float | None = None) -> CmdResult:
        return await self.run(self.cfg.kubernetes.via_host, [*self.cfg.kubernetes.kubectl, *args], timeout)
