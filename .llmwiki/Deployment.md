# Deployment

> Scope: where production runs, how it is built and started, where its data and secrets
> live, and the gap between what is deployed and what the project targets.
> Procedure: the `deploy` skill. Related: [[Architecture]] · [[ParallelDelivery]] · [[Backend]]
> Updated: 2026-09-23

## Facts

### Where

| | Value | Source |
|---|---|---|
| Host | `192.168.1.147` (hostname `n150`), user `vemore`, SSH | checked 2026-09-22 |
| Public URL | `https://zapzap.ombivince.synology.me/` | old `CLAUDE.md` |
| Checkout | `/home/vemore/workspace/zapzap`, a git clone of `https://github.com/vemore/zapzap.git` on `master`, at `d43e199` (2025-12-20) on 2026-09-22 | `git log -1` on the NAS |
| Docker | `/usr/local/bin/docker`, `docker-compose` **1.29.2** — the v1 Python CLI, not `docker compose` | `docker-compose version` on the NAS, 2026-09-23 |
| Secrets | the clone's `.env` (JWT, Google, AWS Bedrock) — never printed, never copied | root `docker-compose.yml:10-22` |

`192.168.1.25` (the user-level `deploy-nas` skill's registry host) refuses SSH and is not
part of this deployment.

### What runs (checked 2026-09-22)

| Container | Image | Command | Mounts |
|---|---|---|---|
| `zapzap-backend` | `zapzap-backend`, built from the root `Dockerfile` | `node scripts/docker-entrypoint.js` | `data/ → /app/data`, `logs/ → /app/logs` |
| `zapzap-frontend` | `zapzap-frontend`, built from `frontend/Dockerfile` | nginx serving the Vite build | — |
| `zapzap-frontend-flutter` | `zapzap-frontend-flutter`, built from `frontend-flutter/Dockerfile` | nginx serving the Flutter web bundle under `/app/` | — |
| `zapzap-proxy` | `nginx:alpine` | nginx | `nginx/nginx.conf → /etc/nginx/conf.d/default.conf` |

All four come from the root `docker-compose.yml`; the backend and frontend containers were
created 2026-04-23, and `zapzap-frontend-flutter` was declared 2026-09-23 — it is **not on
the NAS until that change is deployed**. **Production runs the legacy Node backend (`src/`),
not `zapzap-rust/`**, which has its own `Dockerfile` and `docker-compose.yml` (the same four
services) and has never been deployed.

### The Flutter PWA under `/app/`

- `nginx/nginx.conf` sends `/app` to a relative 301 to `/app/`, and proxies `/app/` to the
  `frontend-flutter` container with the URI unchanged (`nginx/nginx.conf:12-14`, `:91-113`).
  The React client keeps `/`, the API keeps `/api/`: one domain, so the PWA reaches the API
  without CORS.
- The image (`frontend-flutter/Dockerfile`) downloads the Flutter SDK **pinned to 3.47.2**
  and checks its sha256 (the version `.github/workflows/ci.yml` pins), runs
  `flutter build web --release --base-href /app/`, and copies the bundle into
  `/usr/share/nginx/html/app` behind `frontend-flutter/nginx.conf`.
- That conf: the SPA fallback `try_files $uri $uri/ /app/index.html` (a deep link such as
  `/app/parties` is served the app, never a 404); `index.html`, `flutter_bootstrap.js` and
  `flutter_service_worker.js` answer with `Cache-Control: no-cache, no-store,
  must-revalidate` and the rest of the bundle with `no-cache`, because no Flutter web output
  file is content-hashed and Flutter 3.47's service worker caches nothing (it unregisters
  itself on activate); anything under `/app/` with a file extension, and anything under
  `/app/assets/`, `/app/canvaskit/` or `/app/icons/`, 404s instead of falling back — a
  missing manifest icon answered with HTML costs the install prompt silently;
  `/healthz` answers the container health check.
- The bundle carries CanvasKit itself (`--no-web-resources-cdn`): the engine is served from
  `/app/canvaskit/`, not from `www.gstatic.com`, so a client that cannot reach Google still
  gets an app rather than a blank page. The flag is in `frontend-flutter/Dockerfile` **and**
  in the CI `flutter` job, which must build what the image builds.
- **The PWA cannot take the site down.** `location /app/` resolves `frontend-flutter`
  through Docker's DNS (`resolver 127.0.0.11`) with the host in a variable, so nginx starts
  whether or not the container exists and answers 502 on `/app/` alone. An `upstream` block
  would be resolved once at start-up and a missing container would stop nginx altogether
  (`host not found in upstream`), and a `depends_on: frontend-flutter: service_healthy`
  would hold `zapzap-proxy` in `Created` after `deploy.sh` has already stopped the old
  containers — `/` and `/api/health` both unreachable, with `restart: unless-stopped`
  powerless. Neither is used: there is deliberately **no** condition on `frontend-flutter`.
  Should a proxy ever sit in `Created` after a failed dependency, `docker start
  zapzap-proxy` restores `/` and `/api/` at once.
- CI builds the image and runs `scripts/pwa_image_smoke.sh` against it (the `image` job):
  `/app/`, the deep links, the manifest scope, the icons, the cache headers.

### How a deploy happens

`deploy.sh` at the root, run in the NAS clone, in this order (`set -e`: it stops at the
first failure):

1. **refuse if `data/zapzap.db` is tracked** — `git ls-files data/zapzap.db`, before the
   pull, naming the backup and `git rm --cached` (see the database section below);
2. `git pull --ff-only` — refused rather than merged when the clone has local commits or a
   detached HEAD after a rollback;
3. `docker-compose build` — **the old containers are still up and still serving**;
4. `docker-compose down --remove-orphans`, then `docker-compose up -d` — the whole downtime;
5. a 15 s wait, `docker-compose ps`, `curl -m 10 http://localhost:80/api/health`.

**The build comes before the `down`, so a failed build is a no-op**: the images are built
against the new compose file while the previous ones keep serving, and the script exits
saying nothing was stopped and no rollback is needed. Only step 4 is downtime — **measured
3.1 s** locally against a 31 s build (`deploy.sh` itself prints the figure). Before that
order, any build failure — a dependency timeout, ENOSPC, the OOM killer on `dart2js` — left
the site stopped for the whole fix-or-rollback cycle.

`--remove-orphans` is on **every** `down` in the procedure, the rollback included: a compose
file that no longer declares a service (any commit older than the Flutter PWA) otherwise
leaves the container running, and the `down` then reports `Network ... Resource is still in
use` and never removes the network — reproduced locally on `docker-compose` v2, and v1
1.29.2 (what the NAS runs) only warns about the orphan.

`deploy.sh` builds and starts whatever the compose file declares, so the `frontend-flutter`
service needs no change to it — but its first build downloads the Flutter SDK and adds a few
minutes and **~3.6 GB** of Docker storage to the host (measured 2026-09-23: builder stage
3.47 GB — SDK 2.3 GB, pub cache 650 MB —, served image 107 MB, web bundle 42 MB). The
`deploy` skill's preflight wants ≥ 6 GB free and ≥ 2 GB free RAM, since `dart2js` needs about
2 GB; short of it the build now fails harmlessly instead of failing with the site down.

`scripts/hooks_selftest.sh` pins all of this offline (the `hooks` CI job): the step order
including `--remove-orphans`, that a failing build reaches no `down`, and both refusals. It
drives the real `deploy.sh` in a sandbox clone with `docker-compose`, `curl`, `jq` and
`sleep` stubbed.

### The production database

`data/zapzap.db` in the NAS clone, bind-mounted into the backend. On 2026-09-22 the NAS
clone still **tracks** it (`M data/zapzap.db`), while `master` stopped tracking it (#21). A
`git pull` there refuses until the file is untracked locally — and had the file been
unmodified, it would have been deleted. The `deploy` skill's §0 is the safe sequence
(backup, `git rm --cached`, then pull), and since 2026-09-23 `deploy.sh` refuses to run at
all while the file is tracked, printing that sequence.

Done on the NAS on 2026-09-22 (backup `data/zapzap.db.bak-2026-09-22-1356`, 1400832 bytes, no
container touched): the clone's index holds the deletion, so the next `git pull` fast-forwards
and leaves the file in place. Backups `data/*.db.bak-*` are gitignored and refused by the hook.

## Decisions & History

- **The old `CLAUDE.md` deploy recipe** (`scp` a file, `docker cp` it into the container,
  `docker restart`) patched the running container outside git: the next `deploy.sh` rebuild
  silently reverted it. It is not used any more; every change reaches production through
  `master` and `deploy.sh`.
- **The PWA is served on the production domain, under `/app/` (2026-09-23).** A separate
  host or port would have made the API cross-origin, and the Node backend answers only the
  origins of `ALLOWED_ORIGINS` (`src/api/server.js:32-57`); under `/app/` the Flutter client
  resolves its API base from `Uri.base.origin` and nothing about CORS changes
  ([[FrontendFlutter]]). The bundle is built in an image of its own rather than copied into
  the React one, so each client is built, deployed and rolled back on its own.
- **Build before `down` (2026-09-23).** `deploy.sh` used to stop the four containers and
  *then* build, so every build failure was an outage lasting the whole fix-or-rollback
  cycle — and the Flutter PWA image multiplied the ways a build can fail (a 700 MB SDK
  download, ~3.6 GB of storage, `dart2js` wanting 2 GB of RAM on a NAS that has little
  spare). Building first costs nothing: `docker-compose build` does not touch running
  containers, and building against the *new* compose file while the *old* containers serve
  is exactly the wanted behaviour. Planned downtime went from minutes to ~3 s, and an
  unplanned one from "the site is down" to "the deploy did nothing".
  The two refusals added with it — a tracked `data/zapzap.db`, and a pull that would not
  fast-forward — both stop before anything is built or stopped, because both mean the clone
  is not in a state anyone should deploy from.
- **Rust not yet deployed (2026-09-22).** The user named `zapzap-rust/` as the target backend,
  and CI gates it, but the switch is a separate decision with known gaps (schema bootstrap,
  Google login, bot creation, authorization) — tracked in `wip/`.
