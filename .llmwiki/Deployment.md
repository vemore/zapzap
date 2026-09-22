# Deployment

> Scope: where production runs, how it is built and started, where its data and secrets
> live, and the gap between what is deployed and what the project targets.
> Procedure: the `deploy` skill. Related: [[Architecture]] · [[ParallelDelivery]] · [[Backend]]
> Updated: 2026-09-22

## Facts

### Where

| | Value | Source |
|---|---|---|
| Host | `192.168.1.147` (hostname `n150`), user `vemore`, SSH | checked 2026-09-22 |
| Public URL | `https://zapzap.ombivince.synology.me/` | old `CLAUDE.md` |
| Checkout | `/home/vemore/workspace/zapzap`, a git clone of `https://github.com/vemore/zapzap.git` on `master`, at `d43e199` (2025-12-20) on 2026-09-22 | `git log -1` on the NAS |
| Docker | `/usr/local/bin/docker`, `docker-compose` (v1 CLI name) | NAS |
| Secrets | the clone's `.env` (JWT, Google, AWS Bedrock) — never printed, never copied | root `docker-compose.yml:10-22` |

`192.168.1.25` (the user-level `deploy-nas` skill's registry host) refuses SSH and is not
part of this deployment.

### What runs (checked 2026-09-22)

| Container | Image | Command | Mounts |
|---|---|---|---|
| `zapzap-backend` | `zapzap-backend`, built from the root `Dockerfile` | `node scripts/docker-entrypoint.js` | `data/ → /app/data`, `logs/ → /app/logs` |
| `zapzap-frontend` | `zapzap-frontend`, built from `frontend/Dockerfile` | nginx serving the Vite build | — |
| `zapzap-proxy` | `nginx:alpine` | nginx | `nginx/nginx.conf → /etc/nginx/conf.d/default.conf` |

All three come from the root `docker-compose.yml`; the backend and frontend containers were
created 2026-04-23. **Production runs the legacy Node backend (`src/`), not `zapzap-rust/`**,
which has its own `Dockerfile` and `docker-compose.yml` and has never been deployed.

### How a deploy happens

`deploy.sh` at the root, run in the NAS clone: `git pull`, `docker-compose down`,
`docker-compose build`, `docker-compose up -d`, a 15 s wait, `docker-compose ps`, and
`curl http://localhost:80/api/health`. `set -e`: it stops at the first failure. The site is
down during the build.

### The production database

`data/zapzap.db` in the NAS clone, bind-mounted into the backend. On 2026-09-22 the NAS
clone still **tracks** it (`M data/zapzap.db`), while `master` stopped tracking it (#21). A
`git pull` there refuses until the file is untracked locally — and had the file been
unmodified, it would have been deleted. The `deploy` skill's §0 is the safe sequence
(backup, `git rm --cached`, then pull).

Done on the NAS on 2026-09-22 (backup `data/zapzap.db.bak-2026-09-22-1356`, 1400832 bytes, no
container touched): the clone's index holds the deletion, so the next `git pull` fast-forwards
and leaves the file in place. Backups `data/*.db.bak-*` are gitignored and refused by the hook.

## Decisions & History

- **The old `CLAUDE.md` deploy recipe** (`scp` a file, `docker cp` it into the container,
  `docker restart`) patched the running container outside git: the next `deploy.sh` rebuild
  silently reverted it. It is not used any more; every change reaches production through
  `master` and `deploy.sh`.
- **Rust not yet deployed (2026-09-22).** The user named `zapzap-rust/` as the target backend,
  and CI gates it, but the switch is a separate decision with known gaps (schema bootstrap,
  Google login, bot creation, authorization) — tracked in `wip/`.
