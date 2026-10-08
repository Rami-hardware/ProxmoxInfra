"""Entry point: `alertops-mcp` (stdio, default) or `alertops-mcp --http --port 8765`."""

from __future__ import annotations

import argparse
import logging
import sys

from .server import build_server


def main() -> None:
    p = argparse.ArgumentParser(prog="alertops-mcp")
    p.add_argument("--http", action="store_true", help="serve streamable HTTP instead of stdio")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8765)
    p.add_argument("--config", help="config file (default: $ALERTOPS_CONFIG or bundled config.yaml)")
    args = p.parse_args()

    # stdout belongs to the MCP protocol on stdio — log to stderr only.
    logging.basicConfig(stream=sys.stderr, level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")

    from .config import load_config
    server = build_server(load_config(args.config))
    if args.http:
        server.run("streamable-http", host=args.host, port=args.port)
    else:
        server.run("stdio")


if __name__ == "__main__":
    main()
