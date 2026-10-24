## What and why

<!-- What changed, and the problem it solves. Link the ServiceNow record (REQ/CHG/INC). -->

## How it was tested

<!-- Commands run, grader output, screenshots. "It looked fine" is not a test. -->

## Reviewer checklist (docs/conventions.md)

- [ ] Blast radius and rollback are stated
- [ ] Cost impact stated (new resources tagged `program/owner/module/ttl`)
- [ ] IaC: plan attached, no drift, no hard-coded credentials/account ids
- [ ] Least privilege for any new IAM/RBAC; CI uses OIDC, not static keys
- [ ] Observability: new things emit telemetry and have an alert/runbook if user-facing
- [ ] Teardown updated (`scripts/down.sh`) and verified
- [ ] AI involvement noted (tool + what for), output verified — see AI-use policy
- [ ] `task check` passes locally
