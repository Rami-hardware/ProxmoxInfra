# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

All agent rules, commands, conventions and load-bearing quirks live in AGENTS.md (shared with other agents) — keep them there, not here:

@AGENTS.md

The cross-cutting architecture — host/IP/role map, which layer owns what (Terraform vs Ansible vs ArgoCD), how to expose a service, and the Istio ambient mesh / NetworkPolicy model — lives in the `homelab-architecture` skill. Load it before any change that spans more than one layer.
