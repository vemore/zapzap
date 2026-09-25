# Deployment

> Scope: where production runs, how it is built, shipped through the registry and started,
> where its data and secrets live, the Rust backend service, and the rollback.
> Procedure: the `deploy` skill. Related: [[Architecture]] · [[ParallelDelivery]] · [[Backend]]
> Updated: 2026-09-25

## Facts

### Where

| | Value | Source |
|---|---|---|
| Host | `192.168.1.147` (hostname `n150`), user `vemore`, SSH | checked 2026-09-22 |
| Public URL | `https://zapzap.ombivince.synology.me/` | old `CLAUDE.md` |
| Deploy directory | `/home/vemore/docker/zapzap` (`NAS_DEPLOY_DIR`): `compose.yaml`, `.env`, `data/` — no git clone | decided 2026-09-25 |
| Registry | `192.168.1.25:5050`, authenticated, plain HTTP (`insecure-registries` on both ends) | `scripts/deploy.env.example` |
| Docker | `/usr/local/bin/docker`, `docker-compose` **1.29.2** — the v1 Python CLI, not `docker compose`; the host runs Ubuntu, bash 5.2, `curl`, `jq`, `python3` | on the NAS, 2026-09-23 and 2026-09-25 |
| Secrets | the deploy directory's `.env` (JWT, Google, AWS Bedrock) — never printed, never copied off the NAS | `docker-compose.prod.yml`, service `backend` |

`192.168.1.25` is the registry host only (the user-level `deploy-nas` skill's; it refuses
SSH). Until the switch of the `deploy` skill's "First deploy" section, production ran from a
git clone at `/home/vemore/workspace/zapzap` on the NAS, built there (history below).

### What runs

| Container | Image | Command | Mounts |
|---|---|---|---|
| `zapzap-backend` | built from `zapzap-rust/Dockerfile` with `CARGO_FEATURES=bedrock`, runs as uid 1000 | `/app/zapzap-backend` | `data/ → /app/data` |
| `zapzap-frontend` | `zapzap-frontend`, built from `frontend/Dockerfile` | nginx serving the Vite build | — |
| `zapzap-frontend-flutter` | `zapzap-frontend-flutter`, built from `frontend-flutter/Dockerfile` | nginx serving the Flutter web bundle under `/app/` | — |
| `zapzap-proxy` | `zapzap-proxy`, built from `nginx/Dockerfile`: `nginx:alpine` with `nginx/nginx.conf` baked in | nginx | — |

In production all four come from `docker-compose.prod.yml`, as
`192.168.1.25:5050/<image>:<short sha>` — built on the dev machine, pulled by the NAS, never
built there. The root `docker-compose.yml` builds the same images (the proxy from `nginx:alpine`
with the conf mounted) for local use and CI. `zapzap-frontend-flutter` has served the
PWA under `/app/` since #36 (2026-09-23). **The `backend` service is the Rust backend
(`zapzap-rust/`) from the switch of 2026-09-24 on**; until then it was the Node backend,
removed from the repository since (history below). `zapzap-rust/docker-compose.yml` is a
standalone copy for local use (container `zapzap-rust-backend`, port 9999 published, no
Bedrock by default); production does not use it.

### The backend service (Rust, since 2026-09-24)

The service and container keep the names `backend` and `zapzap-backend`: `nginx/nginx.conf`
proxies `/api/` and `/suscribeupdate` to `backend:9999`, and `scripts/deploy_nas.sh`'s
`ESSENTIAL_SERVICES` names it. Its environment (`docker-compose.prod.yml`, the same in the
root `docker-compose.yml`):

| Variable | Value | Why |
|---|---|---|
| `PORT` | `9999` | the nginx upstream |
| `DATABASE_URL` | `sqlite:/app/data/zapzap.db` | the bind-mounted file; no `mode=rwc`, so a missing file stops the backend instead of starting it on an empty database |
| `JWT_SECRET` | `${JWT_SECRET:?...}` | no default: `docker-compose` refuses the file without it, and the binary refuses a blank or published placeholder ([[Backend]]). Production's `.env` has a private 44-character one (checked 2026-09-24) |
| `RUST_LOG` | `${RUST_LOG:-info}` | stdout only: the Rust backend writes no log file, so there is no `logs/` mount |
| `GOOGLE_OAUTH_CLIENT_ID` | from `.env` | Google login |
| `BOT_ACTION_DELAY_MS` | `${BOT_ACTION_DELAY_MS:-1000}` | the pause between two bot actions, read by `action_delay_from` (`zapzap-rust/src/application/bot/runner.rs`, default 1000 ms, `0` means no pause); production's `.env` sets `2000` |
| `AWS_BEDROCK_ENABLED`, `AWS_BEDROCK_REGION`, `AWS_BEDROCK_MODEL_ID`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | bare keys: passed only when `.env` sets them | a present `AWS_BEDROCK_ENABLED` decides alone, and an empty `AWS_BEDROCK_REGION` would replace the `us-east-1` default ([[Backend]], `llm_enabled`). `docker-compose` 1.29.2 — the NAS's — resolves bare keys from `.env` too (checked locally with 1.29.2, 2026-09-24) |
| `BOT_STRATEGIES_DIR` | `/app/data/bot-strategies` | the LLM bots' memory, on the mount |

Production's `.env` may still hold keys only the removed Node backend read — `NODE_ENV`,
`ALLOWED_ORIGINS`, `LOG_LEVEL`, `LOG_DIR` — and `DB_PATH`, which the backend reads only when
`DATABASE_URL` is unset (compose sets it): nothing reads them, they can be dropped
(`.env.example`).

**CORS answers every origin.** The Rust router uses `CorsLayer::permissive()`
(`zapzap-rust/src/api/mod.rs:32`); there is no allow-list (`ALLOWED_ORIGINS` is read by
nothing). Both clients are
same-origin under the production domain, and authentication is a bearer token, never a
cookie, so another site cannot ride a player's session; restricting it is tracked in
`wip/`.

**Ownership of `data/`.** The image runs as uid 1000 (`zapzap-rust/Dockerfile`, user
`zapzap`): `data/`, `data/zapzap.db` (and its `-wal`/`-journal` files) and
`data/bot-strategies/` must be writable by it. A root-owned `bot-strategies/` lets Rust read
an LLM bot's memory but not save it (the save fails and is logged, `reflect_on_round.rs`).
The Node image ran as root and left that directory `root:root`, so the switch began with a
one-time `chown` to `1000:1000`; `scripts/deploy_nas.sh` checks the ownership on the NAS
before it builds, and refuses with the command.

**The schema step on the production database.** At start-up the backend runs its DDL, all
`IF NOT EXISTS`, in one transaction ([[Backend]]); on the production database, created by
the Node backend and opened by it for months, it is a no-op (checked on a copy before the
switch: `sqlite_master` and the row counts unchanged).

`CI`'s `image` job builds this very service (`scripts/backend_image_smoke.sh`: `docker compose
build backend`, then the container on an empty database until its compose health check
passes).

### Rolling back

`scripts/deploy_nas.sh --rollback <sha>` (the `deploy` skill's §4): every image of the
deployed `compose.yaml` re-pinned to `:<sha>`, pulled, then the same backup, `down
--remove-orphans`, `up -d` and health wait as a deploy. Nothing is rebuilt, so the target is
a sha an earlier deploy pushed; the images the old NAS clone built are not in the registry.

### The Flutter PWA under `/app/`

- `nginx/nginx.conf` sends `/app` to a relative 301 to `/app/`, and proxies `/app/` to the
  `frontend-flutter` container with the URI unchanged (`nginx/nginx.conf:12-14`, `:91-113`).
  The React client keeps `/`, the API keeps `/api/`: one domain, so the PWA reaches the API
  without CORS.
- The image (`frontend-flutter/Dockerfile`) downloads the Flutter SDK **pinned to 3.47.2**
  and checks its sha256 (the version `.github/workflows/ci.yml` pins), runs
  `flutter build web --release --base-href /app/`, and copies the bundle into
  `/usr/share/nginx/html/app` behind `frontend-flutter/nginx.conf`. Its build argument
  `GOOGLE_CLIENT_ID` is `VITE_GOOGLE_OAUTH_CLIENT_ID`, the key the React image already reads
  (`docker-compose.yml`, service `frontend-flutter`; in production `scripts/deploy_nas.sh`
  passes it from `scripts/deploy.env` or the dev machine's `.env`): no new key; empty, the PWA shows no Google button ([[FrontendFlutter]]).
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
  would hold `zapzap-proxy` in `Created` after the deploy has already stopped the old
  containers — `/` and `/api/health` both unreachable, with `restart: unless-stopped`
  powerless. Neither is used: there is deliberately **no** condition on `frontend-flutter`.
  Should a proxy ever sit in `Created` after a failed dependency, `docker start
  zapzap-proxy` restores `/` and `/api/` at once.
- CI builds the image and runs `scripts/pwa_image_smoke.sh` against it (the `image` job):
  `/app/`, the deep links, the manifest scope, the icons, the cache headers.

### How a deploy happens

`scripts/deploy_nas.sh`, run on the dev machine from a clean checkout of the commit to deploy,
configured by the untracked `scripts/deploy.env` (`REGISTRY`, `NAS_SSH`, `NAS_DEPLOY_DIR`,
`PUBLIC_URL`; `scripts/deploy.env.example`). In order, stopping at the first failure:

1. **refuse** a missing `REGISTRY`, `NAS_SSH` or `NAS_DEPLOY_DIR` (naming it), a modified
   tracked file or an untracked file in a build context, and a missing
   `VITE_GOOGLE_OAUTH_CLIENT_ID` (the Google client id of both web clients, from
   `deploy.env` or the repository's `.env`);
2. **check the NAS** before building: the deploy directory, its `.env`, `data/zapzap.db`, and
   uid 1000 owning `data/` — the refusals print the fix;
3. `docker build` HEAD's four images — `zapzap-backend` (`CARGO_FEATURES=bedrock`),
   `zapzap-frontend`, `zapzap-frontend-flutter` (both with the client id),
   `zapzap-proxy` — tagged `<short sha>` (`git rev-parse --short=7`) and `latest`, labelled
   `org.opencontainers.image.revision`; `docker push` both tags;
4. pipe `docker-compose.prod.yml` over ssh to `compose.yaml.next`, with the registry and the
   sha written in (no scp);
5. on the NAS — the same file, sent over ssh and run as `--remote deploy`: `docker-compose
   config` (a `.env` without `JWT_SECRET`, or a compose file missing an essential service,
   is refused with compose's reason), `docker-compose pull` — **the old containers still
   serving** —, `cp -p data/zapzap.db data/zapzap.db.bak-<date>` checked with `cmp`, then
   `compose.yaml` → `compose.yaml.prev` and `.next` → `compose.yaml`;
6. `down --remove-orphans`, `up -d`, and **wait until `backend`, `frontend` and `nginx` are
   `healthy` (or `running`) and `/api/health` answers 200**, polling every 2 s for up to 90 s;
   then a 60 s grace for the other services, `ps` and the health payload.

`compose.yaml` on the NAS therefore always names exactly the images that run, and
`compose.yaml.prev` those of the deploy before — the rollback target. Every docker-compose
call runs with `COMPOSE_PROJECT_NAME=zapzap`: the project name the clone had (its directory
was `zapzap`), so the deploy directory takes over the clone's containers on the first deploy.

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

**Everything that can fail slowly happens before the `down`**: the build and the push on the
dev machine, the `config` and the `pull` on the NAS. Any of them failing stops nothing and
leaves `compose.yaml` as it was — production serves what it served. Only the backup, `down`
and `up -d` remain after the pull, all local to the NAS. The build's room — ≥ 6 GB for
Docker (the Flutter builder stage alone ~3.5 GB) and ≥ 2 GB of RAM for `dart2js` — is needed
on the dev machine now; the NAS stores only the pulled images.

**Downtime is measured to the first 200, not to `up -d` returning.** `up -d` exits 0 as soon
as the containers are created — a container crash-looping under `restart: unless-stopped`
satisfies it — so the health wait is the gate: it exits non-zero, names each container with
its state, prints its last 30 log lines and the `--rollback` command with the previous tag.
Measured locally against the real four-container stack: **12.9 s** (2026-09-23, the
containers' own start-up, the proxy's `depends_on` health conditions included). A failing
`down` immediately retries `up -d` before giving up, because that is the one step that can
leave nothing running.

`--remove-orphans` is on every `down`: a container the compose file no longer declares
otherwise survives, and the `down` then reports `Network ... Resource is still in use` —
reproduced locally on `docker-compose` v2, and v1 1.29.2 (what the NAS runs) only warns.

`scripts/deploy_nas_selftest.sh` pins all of this offline (the `hooks` CI job, 106 cases): a
sandbox repository and deploy directory, `ssh` stubbed to run the remote half locally, and
`docker`, `docker-compose`, `curl`, `jq` and `sleep` stubbed, the `docker` stub answering a
state per service. It asserts each refusal and that it builds, pulls and stops nothing, the
order `pull`, `down --remove-orphans`, `up -d`, the backup, the pinned `compose.yaml`, the
split health verdict (exit 1 / 2), and `--rollback`.

### The production database

`data/zapzap.db` in the deploy directory, bind-mounted into the backend as `/app/data`. No
git checkout exists on the NAS any more, so no `git pull` can reach it. Every deploy and
rollback backs it up first (`data/zapzap.db.bak-<YYYY-MM-DD-HHMM>`); prune old backups by
hand. Backups are gitignored (`data/*.db.bak-*`) and the commit hook refuses them
([[Hooks]]) — on a dev machine that holds one.

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
  > **Status: Outdated** (2026-09-24) — Google login and bot creation/deletion are ported
  > ([[Api]]); the Rust compose passes `GOOGLE_OAUTH_CLIENT_ID`.
  > **Status: Outdated** (2026-09-24) — the authorization gap is closed (fix/rust-security). The
  > switch now has two preconditions of its own: `JWT_SECRET` must be set to a private value
  > (the Rust binary and `zapzap-rust/docker-compose.yml` refuse to start without it), and the
  > database must have been opened once by the Node app after `scripts/docker-entrypoint.js`
  > rebuilt `users` — the Rust schema step does not port Node's `ADD COLUMN` upgrades and
  > refuses to start, leaving the file untouched, on a `users` table without `google_id`. And the
  > React `GameBoard` and `PartyLobby` must pass `?token=` to `/suscribeupdate`: Rust sends a
  > game's moves and a private party's events only to its players' streams, so tokenless
  > streams would miss them (tracked in `wip/`).
  > **Status: Outdated** (2026-09-24) — the React `GameBoard` and `PartyLobby` pass the token
  > (#94), and production runs the Rust backend (the entry below).
- **Production switches to the Rust backend (2026-09-24).** The user decided the switch once
  the gaps above were closed: the root compose's `backend` service builds `zapzap-rust/`
  with the Bedrock feature, under the same service and container names so that nginx and
  `deploy.sh` stay as they are. The Node backend is kept, buildable and gated in CI, as the
  rollback, because its database is the same file and Rust writes it in Node's formats —
  password hashes excepted until fix/rust-keeps-bcrypt (#100) made Rust keep bcrypt. `deploy.sh` gained one refusal:
  a compose file `docker-compose` cannot read (a `.env` without `JWT_SECRET`) stops the
  deploy before the build, with compose's reason.
- **2026-09-25 (chore/switch-prod-to-rust, after review).** CORS noted (Rust answers every origin, Node restricted `ALLOWED_ORIGINS`); the Argon2 caveat found by the local rehearsal is void since fix/rust-keeps-bcrypt (#100: Rust keeps bcrypt, user decision); the deploy skill's rehearsal got exact commands for both halves, a schema snapshot before and after, and a post-switch check that Rust serves.
- **The Node backend is removed (2026-09-25, chore/remove-node-backend).** The rollback to
  Node, its rehearsal, what it kept readable and the Node-only `.env` keys left this page: a
  rollback is now the previous commit of the Rust deployment, and CI no longer builds the
  root `Dockerfile`. Its code can still be read at `232f168` (the last master commit holding
  `src/`, e.g. `git show 232f168:src/api/server.js`) and `0bfd407` (the last commit whose
  `docker-compose.yml` builds it, the former rollback target).
- **Production ships through a registry, and the NAS holds no clone (2026-09-25,
  feat/deploy-through-registry, user decision).** `deploy.sh` ran on a git clone on the NAS:
  `git pull`, then `docker-compose build` there — the Flutter builder alone wants ~3.6 GB of
  disk and 2 GB of RAM, on the host serving production — then down/up. The clone was the
  reason a `git pull` could delete the production database (tracked until #21, the old §0
  of the `deploy` skill), and bash reading a script that `git pull` replaces meant
  `deploy.sh` could not deploy a change to itself. Modelled on the `countscore` project
  (`backend/scripts/deploy_nas.sh`), images are now built on the dev machine, pushed to the
  LAN registry `192.168.1.25:5050` countscore already uses, and pulled by a deploy directory
  holding only `compose.yaml`, `.env` and `data/`. A rollback is a re-pin of the tags, no
  rebuild. What `deploy.sh` had earned was kept and ported, not reinvented: the
  essential/optional split, exit codes 0/1/2, the health wait, the measured downtime,
  `--remove-orphans`, and every slow or fallible step before the `down`. The registry
  address is in tracked files (`docker-compose.prod.yml`'s default, the example
  configuration): this repository already publishes the NAS address, and the script writes
  the configured one into the compose file it sends. The proxy became an image of its own so
  nothing on the NAS is a file of the repository.
