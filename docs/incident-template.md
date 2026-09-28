# Incident post-mortem template

Copy this file to `docs/incidents/YYYY-MM-DD-<slug>.md` for every SEV-1/SEV-2.

## Severity matrix (homelab-adapted)
- **SEV-1** — DNS down, all sites down, data loss risk. Drop everything.
- **SEV-2** — one user-facing service down or degraded >15 min.
- **SEV-3** — redundant-capability lost (one of two paths), alerts noisy.
- **SEV-4** — cosmetic / no user impact.

## Template

**Incident:** <one-line summary>
**Date:** YYYY-MM-DD **Severity:** SEV-? **Duration:** start -> resolved
**Author:** <who wrote this>

### Impact
Who/what was affected and for how long. (e.g. "all *.homelab.lan unreachable
for 12 min; media downloads stalled".)

### Timeline (UTC)
```
HH:MM  trigger / first bad event
HH:MM  first alert fired (which alert)
HH:MM  diagnosis step that found the cause
HH:MM  mitigation applied
HH:MM  resolved / alerts cleared
```

### Root cause
The technical why. No blame — name systems, not people.

### What went well / what didn't
Two bullets each. Honest.

### Action items
| Action | Type (fix/process/monitoring) | Owner | Status |
|---|---|---|---|

### Lessons for the runbooks
Anything that should be added to docs/runbooks/* — do it before closing.
