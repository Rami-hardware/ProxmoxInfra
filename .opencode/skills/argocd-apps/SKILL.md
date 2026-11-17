---
name: argocd-apps
description: Use when adding or editing apps under Ansbile/argocd-apps/, working with kustomization.yaml, Application CRs, or ArgoCD Image Updater write-back files.
---

## ArgoCD Apps (`Ansbile/argocd-apps/`)

App changes here do NOT need CI — ArgoCD polls and syncs automatically (self-heal + prune). Exception: the top-level `*-app.yaml` Application CRs are applied by `k3s_apps` (part `image_updater`), so `main.yml` runs for them.

Top-level `media-app.yaml` / `monitoring-app.yaml` / `network-app.yaml` are the Application CRs (Image Updater annotations, `targetRevision: main`). Per-namespace dir (`media/`, `monitoring/`, `network/`):

- `kustomization.yaml` — `resources:` list + `images:` block with `newTag` (the Image Updater write-back target).
- One plain multi-doc YAML per app (Namespace + PV + PVC + Deployment + Service/NodePort pattern — see `jellyfin.yaml`).
- To add an app: create its YAML, list it in that dir's `kustomization.yaml`.

Excluded from ansible-lint via root `.ansible-lint` (`exclude_paths: [Ansbile/argocd-apps/]`).
