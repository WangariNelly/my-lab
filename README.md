# Lab repository

Your own copy of the working files for the DevOps and SRE course. It was created by `opslab-init.sh`; everything in it is yours to change.

## What is here

- `Taskfile.yml` is the task runner. Run `task --list` to see every command.
- `.devcontainer/` pins the workstation. Open the repository in a dev container (or GitHub Codespaces) and the tools are ready.
- `.github/` holds the pull request template and the `lab-checks` workflow.
- `lib/opslab/`, `itsm/`, `faults/run.sh` and `scripts/` are the shared tooling the lessons call.
- `modules/`, `convergence/`, `scenarios/` and the other empty folders fill up as you copy each week's files in from the course site.
- `platform/` is the platform you build, week by week.

## Working rules

1. One branch per change, merged by pull request. CI must be green.
2. Never commit `.env`, state files, kubeconfigs or keys. Copy `.env.example` to `.env` for local settings.
3. Tag every cloud resource `program=opslab`, `owner`, `module` and `ttl`, and tear down the same day.

## Check it

```bash
task check
```
