# Deployment

> Scope: where production runs, how it is built and started, where its data and secrets
> live, and the gap between what is deployed and what the project targets.
> Procedure: the `deploy` skill. Related: [[Architecture]] · [[ParallelDelivery]] · [[Backend]]
> Updated: 2026-09-24

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
created 2026-04-23, and `zapzap-frontend-flutter` has served the PWA under `/app/` since #36
(2026-09-23); every Flutter merge since (#62, #63, #64) went out through the `deploy` skill.
**Production runs the legacy Node backend (`src/`),
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

`deploy.sh` at the root, run in the NAS clone, in this order (`set -e` and `set -o pipefail`:
it stops at the first failure, a failure on the left of a pipe included):

0. `cd "$(dirname "$0")"` — every later step reads paths from the clone; without it
   `cd data && ../deploy.sh` asked git about a path that does not exist, was told "not
   tracked", and pulled;
1. **refuse if `data/zapzap.db` is tracked** — `git ls-files -- data/zapzap.db`, before the
   pull, naming the backup and `git rm --cached` (see the database section below). It
   refuses **just as hard when git cannot answer** (git off PATH, a 127): an unanswered
   question is not a clean bill of health;
2. `git pull --ff-only` — refused rather than merged, printing **git's own reason** above
   its own (the cause is not always a diverged branch: an untracked file the pull would
   overwrite, DNS, credentials);
3. `docker-compose build` — **the old containers are still up and still serving**;
4. `docker-compose down --remove-orphans`, then `docker-compose up -d`;
5. **wait until `backend`, `frontend` and `nginx` are `healthy` (or `running`, where a
   service declares no health check) and `/api/health` answers 200**, polling every 2 s for
   up to 90 s; then a 60 s grace for the other services, `docker-compose ps` and the health
   payload.

Between 3 and 4 it also **refuses if the compose file stops declaring one of the essential
services**, while nothing has been built or stopped: `ESSENTIAL_SERVICES` and
`PROXY_SERVICE` at the top of `deploy.sh`, `docker-compose.yml` and `nginx/nginx.conf` have
to change together, and a rename must not silently demote a service that serves the site.

### What the script calls essential, and what it does not

`ESSENTIAL_SERVICES` is `backend frontend nginx` — the proxy plus the two services its
`depends_on: condition: service_healthy` waits on, which are what `nginx/nginx.conf` proxies
`/`, `/api/` and `/suscribeupdate` to. `PROXY_SERVICE` is `nginx`, and the published port
comes from `docker-compose port "$PROXY_SERVICE" 80` rather than being assumed to be 80.
Both names live in one place in the script, with a comment tying them to the two other files.

**`frontend-flutter` is deliberately outside that set.** nginx resolves it per request
(`nginx/nginx.conf:99-108`), so a PWA container that never becomes healthy costs `/app/` a
502 and nothing else — the design decision of #36, and treating it as essential would undo
it at exactly the wrong moment, since on the deploy that first carries the PWA that
container is the newest and likeliest to misbehave. So the verdict is split, and so is the
exit status:

| Exit | Meaning |
|---|---|
| `0` | deployed, every container healthy |
| `1` | refused before touching anything, or an outage (an essential service, or `/api/health`) |
| `2` | deployed and serving, but a non-essential service is not healthy |

Exit 2 prints a `⚠ WARNING` naming the container and its state, says which services *are*
serving and that `/`, `/api/` and `/suscribeupdate` are unaffected, spells out the cost
(`/app/` answers 502), shows the container's last 30 log lines, says a rollback is
**optional**, and ends with `⚠ Deployed, DEGRADED: …` instead of `✨ Deployment complete!`.
Non-zero so no script can miss it, distinct so no script mistakes it for an outage.

**The build comes before the `down`, so a failed build stops nothing**: the images are built
against the new compose file while the previous ones keep serving, and the script exits
saying so. Before that order, any build failure — a dependency timeout, ENOSPC, the OOM
killer on `dart2js` — left the site stopped for the whole fix-or-rollback cycle. Note the
clone *has* pulled by then, so **HEAD stops being the commit production runs** after a
failed deploy; the running images are (`docker ps`).

**Downtime is measured to the first 200, not to `up -d` returning.** `up -d` exits 0 as soon
as the containers are created — a container crash-looping under `restart: unless-stopped`
satisfies it — so the old script could print a downtime figure and "Deployment complete"
over a site that was never coming back. Step 5 is the gate: it exits non-zero, names each
container with its state and prints its last 30 log lines. Measured locally against the real
four-container stack: **12.9 s** (the containers' own start-up, the proxy's `depends_on`
health conditions included) after a build of any length. A broken non-essential service does
not change the figure: the gate that ends the downtime is the essential set plus
`/api/health`. `down` and `up -d` are both guarded too; a failing `down` immediately retries
`up -d` before giving up, because that is the one step that can leave nothing running.

`--remove-orphans` is on **every** `down` in the procedure, the rollback included: a compose
file that no longer declares a service (any commit older than the Flutter PWA) otherwise
leaves the container running, and the `down` then reports `Network ... Resource is still in
use` and never removes the network — reproduced locally on `docker-compose` v2, and v1
1.29.2 (what the NAS runs) only warns about the orphan.

**`deploy.sh` cannot deploy a change to itself.** bash keeps the file it opened, so after the
script pulls a new version of itself the *old* code runs to the end. The first deploy after
any change to `deploy.sh` must therefore be preceded by a manual `git pull --ff-only` in the
clone — the `deploy` skill §0 has the sequence.

`deploy.sh` builds and starts whatever the compose file declares, so the `frontend-flutter`
service needs no change to it — but its first build downloads the Flutter SDK and adds a few
minutes and **~3.6 GB** of Docker storage to the host (measured 2026-09-23: builder stage
3.47 GB — SDK 2.3 GB, pub cache 650 MB —, served image 107 MB, web bundle 42 MB). The
`deploy` skill's preflight wants ≥ 6 GB free and ≥ 2 GB free RAM, since `dart2js` needs about
2 GB; short of it the build now fails harmlessly instead of failing with the site down.

`scripts/hooks_selftest.sh` pins all of this offline (the `hooks` CI job, 42 cases): the step
order including `--remove-orphans`, that a failing build reaches no `down`, that a failing
`down` retries `up -d`, that an unhealthy **essential** container or a silent `/api/health`
fails the deploy while an unhealthy `frontend-flutter` only warns and exits 2, that a compose
file missing an essential service refuses before building, and every refusal — including the
subdirectory invocation and git being unavailable. It drives the real `deploy.sh` in a
sandbox clone with `docker-compose`, `docker`, `curl`, `jq` and `sleep` stubbed, the `docker`
stub answering a state per service.

### The production database

`data/zapzap.db` in the NAS clone, bind-mounted into the backend. On 2026-09-22 the NAS
clone still **tracks** it (`M data/zapzap.db`), while `master` stopped tracking it (#21). A
`git pull` there refuses until the file is untracked locally — and had the file been
unmodified, it would have been deleted. The `deploy` skill's §0 is the safe sequence
(backup, `git rm --cached`, then pull), and since 2026-09-23 `deploy.sh` refuses to run at
all while the file is tracked, printing that sequence.

Done on the NAS on 2026-09-22 (backup `data/zapzap.db.bak-2026-09-22-1356`, 1400832 bytes, no
container touched): the clone's index holds the deletion, so the next `git pull` fast-forwards
and leaves the file in place.

Backups `data/*.db.bak-*` are gitignored **from #24 on**, and the commit hook refuses them
([[Hooks]]) — but the NAS is on a commit *older* than #24, so until it pulls, that backup
shows as `?? data/zapzap.db.bak-2026-09-22-1356` in `git status --short` there. It is
expected, it is not "someone changed production by hand", and the `deploy` skill §1 lists it
alongside the staged `D data/zapzap.db` as the two entries a clean NAS shows today.

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
- **A deploy is not over until the site answers (2026-09-23, same change, after review).**
  The first version of the above still reported success over a dead deploy: `up -d` returns
  0 for a container that crash-loops, and the old health check could not fail (no `pipefail`,
  so the pipeline's status was `jq`'s, and `jq` is happy with empty input). It printed a
  downtime figure and "Deployment complete" while the site had been unreachable for 27 s and
  counting. Hence the health wait, `pipefail`, and guards on `down` and `up -d`: the script
  now refuses to claim a downtime it cannot see the end of. The same review found the
  database guard failing **open** — `git ls-files` was read relative to `$PWD`, so a run from
  a subdirectory printed "✓ Not tracked" about a path that does not exist and pulled, which
  deleted `data/`. The `cd` to the script's directory and the fail-closed check are that fix;
  both are pinned by `scripts/hooks_selftest.sh`.
- **The health gate is split, because the services are not equal (2026-09-23, same change,
  second review).** Requiring *every* service to be healthy would have made an unhealthy
  `frontend-flutter` print "production is DOWN" and exit 1 — false, and an invitation to roll
  back a site that is serving, on the very deploy where that container is newest. #36 made
  the PWA non-essential on purpose (nginx resolves it per request, no `depends_on` on it),
  and the deploy script now agrees with the proxy: essential means "the proxy and what it
  cannot start without", everything else is a warning and exit 2. The two service names are
  named once in the script instead of being spread through it, and the script refuses before
  building if the compose file stops declaring one of them — the cheapest guard against the
  set going stale.
- **Rust not yet deployed (2026-09-22).** The user named `zapzap-rust/` as the target backend,
  and CI gates it, but the switch is a separate decision with known gaps (schema bootstrap,
  Google login, bot creation, authorization) — tracked in `wip/`.
  > **Status: Outdated** (2026-09-23) — the schema bootstrap gap is closed: the Rust backend
  > creates the Node schema itself, and on the production file that step is a no-op
  > ([[Backend]]). The other gaps stand.
  > **Status: Outdated** (2026-09-24) — the authorization gap is closed (fix/rust-security). The
  > switch now has two preconditions of its own: `JWT_SECRET` must be set to a private value
  > (the Rust binary and `zapzap-rust/docker-compose.yml` refuse to start without it), and the
  > database must have been opened once by the Node app after `scripts/docker-entrypoint.js`
  > rebuilt `users` — the Rust schema step does not port Node's `ADD COLUMN` upgrades and
  > refuses to start, leaving the file untouched, on a `users` table without `google_id`. And the
  > React `GameBoard` and `PartyLobby` must pass `?token=` to `/suscribeupdate`: Rust sends a
  > game's moves and a private party's events only to its players' streams, so tokenless
  > streams would miss them (tracked in `wip/`).
