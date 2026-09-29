# Deployment

> Scope: where production runs, how it is built, shipped through the registry and started,
> where its data and secrets live, the Rust backend service, and the rollback.
> Procedure: the `deploy` skill. Related: [[Architecture]] · [[ParallelDelivery]] · [[Backend]]
> Updated: 2026-09-29

## Facts

### Where

| | Value | Source |
|---|---|---|
| Host | `192.168.1.147` (hostname `n150`), user `vemore`, SSH | checked 2026-09-22 |
| Public URL | `https://zapzap.ombivince.synology.me/` | old `CLAUDE.md` |
| Deploy directory | `/home/vemore/docker/zapzap` (`NAS_DEPLOY_DIR`): `compose.yaml`, `.env`, `data/` — no git clone | decided 2026-09-25 |
| Registry | `192.168.1.25:5050`, authenticated, plain HTTP (`insecure-registries` on both ends) | `scripts/deploy.env.example` |
| Docker | `/usr/bin/docker`, Compose **v2** as the plugin `docker compose` (**5.5.1**, `/usr/libexec/docker/cli-plugins/docker-compose`); no `docker-compose` binary any more (v1.29.2 until 2026-09-28). The ssh PATH already holds `/usr/local/bin`: no `export PATH` prefix. The host runs Ubuntu, bash 5.2, `curl`, `jq`, `python3` | on the NAS, 2026-09-28 |
| Secrets | the deploy directory's `.env` (JWT, Google, AWS Bedrock) — never printed, never copied off the NAS | `docker-compose.prod.yml`, service `backend` |

`192.168.1.25` is the registry host only (the user-level `deploy-nas` skill's; it refuses
SSH). Until 2026-09-25 production ran from a git clone at `/home/vemore/workspace/zapzap` on
the NAS, built there; the clone and its images are deleted (history below).

### What runs

| Container | Image | Command | Mounts |
|---|---|---|---|
| `zapzap-backend` | built from `zapzap-rust/Dockerfile` with `CARGO_FEATURES=bedrock`: a static musl binary on `alpine:3.22` with `ca-certificates` only (29 MB), runs as uid 1000 | `/app/zapzap-backend` | `data/ → /app/data` |
| `zapzap-frontend-flutter` | `zapzap-frontend-flutter`, built from `frontend-flutter/Dockerfile` | nginx serving the Flutter web bundle under `/app/` | — |
| `zapzap-proxy` | `zapzap-proxy`, built from `nginx/Dockerfile`: `nginx:alpine` with `nginx/nginx.conf` and `nginx/privacy.html` baked in | nginx | — |

In production all three come from `docker-compose.prod.yml`, as
`192.168.1.25:5050/<image>:<first 12 characters of the sha>` — built on the dev machine, pulled by the NAS, never
built there. The root `docker-compose.yml` builds the same images (the proxy from `nginx:alpine`
with the conf and the privacy page mounted) for local use and CI. `zapzap-frontend-flutter` has served the
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
| `JWT_SECRET` | `${JWT_SECRET:?...}` | no default: Compose refuses the file without it, and the binary refuses a blank or published placeholder ([[Backend]]). Production's `.env` has a private 44-character one (checked 2026-09-24) |
| `RUST_LOG` | `${RUST_LOG:-info}` | stdout only: the Rust backend writes no log file, so there is no `logs/` mount |
| `GOOGLE_OAUTH_CLIENT_ID` | from `.env` | Google login |
| `ALLOWED_ORIGINS` | `${ALLOWED_ORIGINS:-https://zapzap.ombivince.synology.me}` | the only origin CORS grants (below); a default in the compose file, so no deploy runs permissive for want of a `.env` line. Production's `.env` has no such line (checked 2026-09-27): the default applies. The root and `zapzap-rust/` compose files pass it bare, only when set |
| `BOT_ACTION_DELAY_MS` | `${BOT_ACTION_DELAY_MS:-1000}` | the pause between two bot actions, read by `action_delay_from` (`zapzap-rust/src/application/bot/runner.rs`, default 1000 ms, `0` means no pause); production's `.env` sets `2000` |
| `AWS_BEDROCK_ENABLED`, `AWS_BEDROCK_REGION`, `AWS_BEDROCK_MODEL_ID`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | bare keys: passed only when `.env` sets them | a present `AWS_BEDROCK_ENABLED` decides alone, and an empty `AWS_BEDROCK_REGION` would replace the `us-east-1` default ([[Backend]], `llm_enabled`). Compose v2 — the NAS's — resolves bare keys from `.env`, and leaves one `.env` does not set out (`docker compose config`, 5.5.1, 2026-09-28); v1.29.2 did the same (checked 2026-09-24) |
| `BOT_STRATEGIES_DIR` | `/app/data/bot-strategies` | the LLM bots' memory, on the mount |

`/suscribeupdate` carries its session JWT as `?token=` (EventSource cannot set headers,
[[Architecture]] "Real-time updates"): the token stays in the URL, but not in nginx's access
log. `nginx/nginx.conf` defines a `log_format sse_no_token` using `$uri` (no query string) in
place of `$request`, and only `location /suscribeupdate` overrides `access_log` to use it;
every other location keeps the default combined format, query string included. nginx's
error log still records the full request line, token included, on an upstream error (a
backend restart closes every open stream).

Production's `.env` holds none of the keys only the removed Node backend read — `NODE_ENV`,
`ALLOWED_ORIGINS`, `LOG_LEVEL`, `LOG_DIR` — nor `DB_PATH`, which the backend reads only when
`DATABASE_URL` is unset (compose sets it): dropped 2026-09-25, a backup `.env.bak-*-node-keys`
kept next to it. `ALLOWED_ORIGINS` is read again since 2026-09-27, by Rust, with its
production value in the compose file.

**CORS answers the production origin only.** The backend grants the origins of
`ALLOWED_ORIGINS` (`AllowedOrigins`, `zapzap-rust/src/infrastructure/cors.rs`; parsing and
the development default: [[Backend]]), which production sets to
`https://zapzap.ombivince.synology.me`: a preflight or request from that origin gets
`access-control-allow-origin`, one from any other site does not, so a foreign page cannot read
the API's answers. Nothing is refused server-side: requests without an `Origin` — the Android
app, a same-origin `GET` — or with another one are served as before, and the web client is
same-origin under that domain (the PWA under `/app/`), so CORS never applies to it. The startup log says which behaviour runs: `CORS answers only the origins of
ALLOWED_ORIGINS: …` (info), or `ALLOWED_ORIGINS not set: CORS answers every origin` (warn).

**Ownership of `data/`.** The image runs as uid 1000 (`zapzap-rust/Dockerfile`, user
`zapzap`): `data/`, `data/zapzap.db` (and its `-wal`/`-journal` files) and
`data/bot-strategies/` must be writable by it. A root-owned `bot-strategies/` lets Rust read
an LLM bot's memory but not save it (the save fails and is logged, `reflect_on_round.rs`).
The Node image ran as root and left that directory `root:root`, so the switch began with a
one-time `chown` to `1000:1000`; `scripts/deploy_nas.sh` checks the ownership on the NAS
before it builds, and refuses with the command.

**The schema step on the production database.** At start-up the backend runs its DDL, all
`IF NOT EXISTS`, in one transaction ([[Backend]]); on the production database, created by
the Node backend and opened by it for months, the DDL is a no-op (checked on a copy before the
switch: `sqlite_master` and the row counts unchanged). The migrations it has not had run
after it, in the same transaction, once each (`PRAGMA user_version`): the first start of
fix/game-state-version adds `game_state.version` (existing rows 0), that of
fix/google-id-unique-index the unique index `idx_users_google_id_unique` — which fails, the
backend refusing to start with the file unchanged, if two users share a `google_id` (none on
2026-09-27; the read-only check is the query `SELECT google_id FROM users WHERE google_id IS
NOT NULL GROUP BY google_id HAVING COUNT(*) > 1`). If it fails anyway, `scripts/deploy_nas.sh
--rollback <previous sha>` restores service on the untouched file; find the duplicate users
with that read-only query, remove or merge the extra one, then redeploy. The first start of
feat/guest-play adds `users.is_guest` (existing users 0), which no data can make fail. They are
additive, so an older image rolled back to reads and writes the migrated file as before.

**After the deploy of feat/guest-play**, create one guest from a phone on mobile data and
read `docker compose logs backend | grep "Guest account created"`: the address must be the
phone's, not DSM's LAN one — the check of the proxy assumption in [[Api]] § Guest accounts.

`CI`'s `image` job builds this very service (`scripts/backend_image_smoke.sh`: `docker buildx
bake` on the root compose file with a GitHub Actions layer cache, `docker compose build backend`
without one, then the container on an empty database until its compose health check
passes — busybox `wget`, the image has no curl —, then uid 1000, the CA store and the size).

**The image** (since 2026-09-25, feat/backend-image-alpine): builder `rust:1.92-alpine` (in step with
`rust-toolchain.toml`) with `musl-dev cmake perl make clang linux-headers`, for the two crates
that compile C, `libsqlite3-sys` (bundled SQLite) and `aws-lc-sys` (rustls' crypto under
`bedrock`); the binary is static (the build fails on a `NEEDED` entry) and stripped. Runtime
`alpine:3.22` with `ca-certificates` only: nothing links OpenSSL (reqwest uses rustls with
bundled webpki roots for Google's keys; the Bedrock client, `rustls-native-certs`, reads
`/etc/ssl/certs`). 29 MB served, against 135 MB for the Debian `bookworm-slim` image
before (`libssl3`, `curl`). The binary is root-owned and only `/app/data` belongs to uid 1000
(a recursive `chown` of `/app` after the `COPY` stored the binary twice, 20 MB); everything
the backend writes lives under `data/`.

### Rolling back

`scripts/deploy_nas.sh --rollback <sha>` (the `deploy` skill's §4) restores the compose
file the tag was deployed with (`composes/compose.<tag>.yaml`) — not the current one with its
tags swapped, which would run an old image under a newer environment and health checks. A
tag older than the ten kept falls back to that commit's `docker-compose.prod.yml`, rendered
from the dev machine's git; neither is refused. The pull is skipped when every image is
still on the NAS, so a rollback survives a registry that is down; then the same backup,
`down`, swap, `up -d` and health wait as a deploy. Nothing is rebuilt: the target is a tag
an earlier deploy pushed; the images the old NAS clone built are not in the registry.

### The Flutter PWA under `/app/`

- `nginx/nginx.conf` sends `/app` to a relative 301 to `/app/`, and proxies `/app/` to the
  `frontend-flutter` container with the URI unchanged (`nginx/nginx.conf:8-11`, `:111-138`).
  The API keeps `/api/`: one domain, so the PWA reaches the API without CORS.
- The image (`frontend-flutter/Dockerfile`) downloads the Flutter SDK **pinned to 3.47.2**
  and checks its sha256 (the version `.github/workflows/ci.yml` pins), runs
  `flutter build web --release --base-href /app/`, and copies the bundle into
  `/usr/share/nginx/html/app` behind `frontend-flutter/nginx.conf`. Its build argument
  `GOOGLE_CLIENT_ID` is `VITE_GOOGLE_OAUTH_CLIENT_ID`, the key the removed React image read
  (`docker-compose.yml`, service `frontend-flutter`; in production `scripts/deploy_nas.sh`
  passes it from `scripts/deploy.env` or the dev machine's `.env`); empty, the PWA shows no Google button ([[FlutterAndroidPwa]]).
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
- **The PWA cannot take the API down.** `location /app/` resolves `frontend-flutter`
  through Docker's DNS (`resolver 127.0.0.11`) with the host in a variable, so nginx starts
  whether or not the container exists and answers 502 on the web alone. An `upstream` block
  would be resolved once at start-up and a missing container would stop nginx altogether
  (`host not found in upstream`), and a `depends_on: frontend-flutter: service_healthy`
  would hold `zapzap-proxy` in `Created` after the deploy has already stopped the old
  containers — `/api/`, hence the Android app, unreachable too, with `restart:
  unless-stopped` powerless. Neither is used: there is deliberately **no** condition on
  `frontend-flutter`, although the deploy calls it essential (below). Should a proxy ever
  sit in `Created` after a failed dependency, `docker start zapzap-proxy` restores `/api/`
  and `/app/` at once.
- CI builds the image and runs `scripts/pwa_image_smoke.sh` against it (the `image` job):
  `/app/`, the deep links, the manifest scope, the icons, the cache headers.

### The URLs of the removed React client

The React client served `/` and its own paths until 2026-09-29 ([[Frontend]]). The proxy
answers each with a **301** — `/` alone with a **302** —, relative (`absolute_redirect off`
for the whole server: the public scheme and port are the Synology proxy's), query string kept
(`nginx/nginx.conf:153-186`):

| Old URL | Redirect |
|---|---|
| `/` (302) | `/app/` |
| `/party/<id>` (`[A-Za-z0-9_-]+`, trailing `/` allowed) | `/app/parties/<id>` |
| `/create-party`, `/create-party/` | `/app/parties/new` |
| `/account/delete`, `/account/delete/` (the Play listing's deletion URL) | `/app/account` |
| any other path — `/login`, `/register`, `/parties`, `/game/<id>`, `/history[/<id>]`, `/stats`, `/admin[/<tab>]` | `/app` + the path as sent (`$request_uri`) |

`/api/`, `/suscribeupdate`, `/app`, `/app/`, `/privacy`, `/privacy.html` and `/nginx-health`
keep their own locations. `//host` becomes `/app//host`, a path on this host, never an open
redirect. `scripts/proxy_redirects_smoke.sh` (CI's `image` job) runs the real proxy image
between a stub backend and a stub PWA and checks each redirect's status and `Location`, and
that every unchanged path still reaches what it did.

### The privacy policy at `/privacy`

- `https://zapzap.ombivince.synology.me/privacy` (and `/privacy.html`) is served by the proxy
  itself, not proxied: `location = /privacy` in `nginx/nginx.conf` aliases
  `/usr/share/nginx/zapzap/privacy.html`, which `nginx/Dockerfile` copies into the image. Google
  Play links to it.
- The page is generated from the root `privacy_policy.md` by `scripts/build_privacy_page.py`
  (pandoc 3.6.4, pinned in the script; `--check` fails when the committed page is stale, and
  CI's `image` job runs it, [[Testing]]). Edit
  the Markdown, run the script, commit both; the next deploy of the proxy image publishes it.
  Nothing else is needed: no environment variable, no file in the deploy directory.
- The web page for deleting an account (also asked by Play, named in the policy) is
  `/account/delete`, a 301 to the PWA's account page (above).

### How a deploy happens

`scripts/deploy_nas.sh`, run on the dev machine from a clean checkout of the commit to deploy,
configured by the untracked `scripts/deploy.env` (`REGISTRY`, `NAS_SSH`, `NAS_DEPLOY_DIR`,
`PUBLIC_URL`; `scripts/deploy.env.example`). In order, stopping at the first failure:

1. **refuse** a missing `REGISTRY`, `NAS_SSH` or `NAS_DEPLOY_DIR` (naming it), a modified
   tracked file or an untracked file in a build context, and a missing
   `VITE_GOOGLE_OAUTH_CLIENT_ID` (the Google client id of the PWA, from
   `deploy.env` or the repository's `.env`);
2. **check the NAS** before building: the deploy directory, its `.env`, `data/zapzap.db`, and
   uid 1000 owning `data/` — the refusals print the fix;
3. `docker build` HEAD's three images — `zapzap-backend` (`CARGO_FEATURES=bedrock`),
   `zapzap-frontend-flutter` (with the client id), `zapzap-proxy` — tagged with the first 12 characters of the sha (a fixed length, unlike
   `--short`) and `latest`, labelled `org.opencontainers.image.revision`; **refuse** a backend
   image without `wget` (`docker run --entrypoint sh … -c 'command -v wget'`), which the
   production health check runs and only the Alpine image of #106 carries; `docker push`
   both tags (`--build-only` stops here, never contacting the NAS);
4. pipe `docker-compose.prod.yml` over ssh to `compose.yaml.next`, with the registry and the
   sha written in (no scp);
5. on the NAS — the same file, sent over ssh and run as `--remote deploy`: the Compose it
   has (below), `config` (a `.env` without `JWT_SECRET`, or a compose file missing an
   essential service, is refused with compose's reason), `pull` — **the old containers still
   serving** —, the database backup `data/zapzap.db.bak-<YYYY-MM-DD-HHMMSS>-<tag>` by SQLite's
   online backup API (python3 on the NAS: a file copy could catch a write half-way), checked
   with `integrity_check`, refused rather than written over an existing file;
6. `down --remove-orphans` with the **running** compose file; only after it succeeded
   `compose.yaml` → `compose.yaml.prev`, `.next` → `compose.yaml`, and a copy kept as
   `composes/compose.<tag>.yaml` (the last 10); a failed `down` restarts the running file,
   never the unchecked images; then `up -d`, and **wait until `backend`, `frontend-flutter` and `nginx` are
   `healthy` (or `running`) and `/api/health` answers 200**, polling every 2 s for up to 90 s;
   then a 60 s grace for the other services, `ps` and the health payload.

`compose.yaml` on the NAS therefore always names exactly the images that run, and
`compose.yaml.prev` those of the deploy before — the rollback target. Every compose call
runs with `COMPOSE_PROJECT_NAME=zapzap`: the project name the clone had (its directory was
`zapzap`), so the deploy directory takes over the clone's containers on the first deploy.

### Which Compose

The remote preflight picks it once (`pick_compose`, `scripts/deploy_nas.sh`): `docker
compose` when `docker compose version` answers, else `docker-compose` on PATH, else a refusal
before anything is built. It prints `🐳 Compose: docker compose 5.5.1`, and every call —
`config`, `pull`, `down`, `up -d`, `ps`, `port`, `logs`, deploy and rollback alike — goes
through it. The NAS answers v2 since 2026-09-28; v1 stays a fallback.

**v2 manages the containers v1 created**: both select them by the label
`com.docker.compose.project=zapzap`, and every service sets `container_name`, so v2's
`<project>-<service>-1` naming never applies; the network is `zapzap_zapzap-network` under
both, with the labels v2 checks. On the NAS, 2026-09-28, before any v2 deploy, `docker compose
-p zapzap -f compose.yaml ps` listed the four v1 containers (label `version=1.29.2`) healthy,
and `port nginx 80` answered one line, `0.0.0.0:8092`. What v2 changes:

- **`depends_on: condition: service_healthy` holds `up -d`** until `backend` is healthy
  (`frontend` too before 2026-09-29); if it turns unhealthy, `up -d` exits 1 (`dependency failed to start`) and
  leaves `zapzap-proxy` in `Created` (checked locally, 5.5.1). `START FAILED` then names each
  essential container not healthy, its state and last 30 log lines. (The 2026-09-23 entry
  recorded v1.29.2 as ignoring the condition.)
- **`ps` lists running containers only** unless `-a`: the health checks call `ps -a -q`, so
  the proxy reads `nginx(created)`, not `nginx(no container)`.
- **Orphans** fail a `down` on the network where v1 only warned: `--remove-orphans`, below.

### What the script calls essential, and what it does not

`ESSENTIAL_SERVICES` is `backend frontend-flutter nginx` — the proxy, the service its
`depends_on: condition: service_healthy` waits on (`backend`, what `/api/` and
`/suscribeupdate` reach), and since 2026-09-29 the PWA, the only web client, what `/app/`
reaches and every old React URL redirects to. nginx still resolves the PWA per request, so
an unhealthy one leaves `/api/` (the Android app) serving — but the web has nothing else,
so the deploy calls it an outage and names the rollback. `PROXY_SERVICE` is `nginx`, and the
published port comes from `port "$PROXY_SERVICE" 80` rather than being assumed to be 80.
Both names live in one place in the script, with a comment tying them to the two other files.

Any other service is **not** essential. `docker-compose.prod.yml` declares none today; the
split stays for one added later outside the proxy's `depends_on`. (A rollback to a compose
file from before 2026-09-29 is not such a case: its proxy `depends_on` the React client's
`frontend` being healthy, so under Compose v2 an unhealthy `frontend` fails `up -d` —
`START FAILED`, exit 1.) The exit status:

| Exit | Meaning |
|---|---|
| `0` | deployed, every container healthy |
| `1` | refused before touching anything, or an outage (an essential service, or `/api/health`) |
| `2` | deployed and serving, but a non-essential service is not healthy |

Exit 2 prints a `⚠ WARNING` naming the container and its state, says which services *are*
serving and that `/app/`, `/api/` and `/suscribeupdate` are unaffected, shows the
container's last 30 log lines, says a rollback is **optional**, and ends with `⚠ Deployed,
DEGRADED: …` instead of `✨ Deployment complete!`.
Non-zero so no script can miss it, distinct so no script mistakes it for an outage.

**Everything that can fail slowly happens before the `down`**: the build and the push on the
dev machine, the `config` and the `pull` on the NAS. Any of them failing stops nothing and
leaves `compose.yaml` as it was — production serves what it served. The backup comes before
the `down` too; only `down` and `up -d` remain, local to the NAS. The build's room — ≥ 6 GB for
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
reproduced locally on Compose v2, what the NAS runs since 2026-09-28; v1 1.29.2 only warned.

`scripts/deploy_nas_selftest.sh` pins all of this offline (the `hooks` CI job, 199 cases): a
sandbox repository and deploy directory, `ssh` stubbed to run the remote half locally, and
`docker`, `curl`, `jq` and `sleep` stubbed, the `docker` stub answering a state per service.
Compose is one stub behind `docker compose` (v2, its `ps` hiding a `Created` container
without `-a`) and `docker-compose` (v1), the host's own kept off PATH: the suite runs on v2
alone, asserting no call reached v1; then v1 alone, both (v2 wins) and neither (refused). It asserts each refusal and that it builds, pulls and stops nothing, the
order `pull`, `down --remove-orphans`, `up -d`, the online backup and its naming, the pinned
and stored `compose.yaml`, that a failed `down` restarts the old file, the `wget` refusal,
`--build-only`, the split health verdict (exit 1 / 2), and `--rollback` (stored compose,
rendered from git, no pull when the images are present, refusals).

### The production database

`data/zapzap.db` in the deploy directory, bind-mounted into the backend as `/app/data`. No
git checkout exists on the NAS any more, so no `git pull` can reach it. Every deploy and
rollback backs it up first (`data/zapzap.db.bak-<YYYY-MM-DD-HHMMSS>-<tag>`, SQLite's online
backup, never overwritten); prune old backups by hand. Backups are gitignored (`data/*.db.bak-*`) and the commit hook refuses them
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
- **Build before `down` (2026-09-23).** `deploy.sh` stopped the containers and *then*
  built, so every build failure — and the PWA image added many: a 700 MB SDK, ~3.6 GB of
  storage, 2 GB of RAM for `dart2js` — was an outage for the whole fix-or-rollback cycle.
  Building against the new compose file while the old containers serve costs nothing:
  planned downtime went from minutes to ~3 s, an unplanned one to "the deploy did nothing".
- **A deploy is not over until the site answers (2026-09-23, same change, after review).**
  The first version reported "Deployment complete" over a site unreachable for 27 s: `up -d`
  returns 0 for a crash-looping container, and the health check could not fail (no
  `pipefail`). Hence the health wait and the guards on `down` and `up -d`. The same review
  found the database guard failing **open** (`git ls-files` read relative to `$PWD`), fixed
  and pinned by `scripts/hooks_selftest.sh`.
- **The health gate is split, because the services are not equal (2026-09-23, same change,
  second review).** Requiring every service healthy would have called an unhealthy PWA
  "production is DOWN" on the very deploy where it was newest, while React served `/`: the
  PWA was made non-essential (exit 2), until the React client went (2026-09-29, below). The
  service names live once in the script, which refuses a compose file that stops declaring one.
- **Production switches to the Rust backend (2026-09-22 → 2026-09-25).** The user named
  `zapzap-rust/` the target on 2026-09-22 and decided the switch once its gaps had closed:
  the schema bootstrap (2026-09-23), Google login, bot creation and authorization, a private
  `JWT_SECRET`, and the React client passing `?token=` to `/suscribeupdate` (#94), all by
  2026-09-24. The root compose's `backend` service then built `zapzap-rust/` (Bedrock
  feature) under the same names, so nginx and `deploy.sh` stayed as they were; Node stayed
  one day as the rollback (Rust keeps its bcrypt hashes, #100). The switch added one refusal:
  a compose file Compose cannot read (a `.env` without `JWT_SECRET`) stops the deploy before
  the build. The step-by-step account is this page at `055c288`.
- **CORS restricted to the production origin (2026-09-27, fix/rust-cors-allow-list).** Rust
  had answered every origin since the switch (`CorsLayer::permissive()`), where Node had
  honoured `ALLOWED_ORIGINS`; tower-http documents the permissive layer as unfit for
  production. The value lives in `docker-compose.prod.yml` as a default rather than in the
  NAS `.env`: the `.env` had dropped the key on 2026-09-25, and a restriction that depends on
  a hand-edited file would silently fall back to permissive on the next rebuilt deploy
  directory. Unset stays permissive for development (the Flutter web client and the e2e run
  call the API from another port), logged as a warning so a production start without it
  shows. A malformed entry stops the backend, as a bad `JWT_SECRET` does, rather than grant
  something other than what was written. After review (same PR): the preflight's request
  headers are mirrored instead of answered `*`, since by the Fetch standard `*` never covers
  `Authorization` and a strict browser would refuse every authenticated call from a listed
  origin; and a `*` among the entries logs that it is a wildcard, not "not set".
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
- **The switch is closed (2026-09-25, docs/nas-switch-done).** The first `deploy_nas.sh`
  (34918bab08a6) came up healthy with 25 users and 29 parties before and after; the user deleted
  the clone and its `zapzap_*` images the same day instead of waiting a week, and the Node-only
  keys left the `.env`. The step-by-step switch left the `deploy` skill.
- **Compose v2 on the NAS (2026-09-28, fix/deploy-compose-v2).** Between two deploys that
  day the NAS lost `docker-compose` 1.29.2 and gained the v2 plugin (5.5.1); the preflight
  refused and #172 waited. The 2026-09-23 constraint "compose stays at v1.29.2" no longer
  holds. The script probes for v2 and falls back to v1 rather than switching outright, so
  either NAS deploys; `COMPOSE_PROJECT_NAME=zapzap` stays, the running containers' label. The
  `export PATH=$PATH:/usr/local/bin` prefix went: the NAS's ssh PATH already holds it.
- **The React client is removed; the PWA becomes essential (2026-09-29,
  chore/remove-react-client).** Three images instead of four; the proxy's `location /` became
  the redirects above and its `depends_on` lost `frontend`. The PWA joined
  `ESSENTIAL_SERVICES`, reversing the split of 2026-09-23 for it: that split protected `/`,
  which the React client served, and there is no other web client left to protect. The
  per-request resolution stays, for `/api/`. 301 rather than 302 for the old React paths:
  they are gone for good, and bookmarks should learn the new ones; `/` answers a 302 (after
  review), so the root stays free for a later landing page or a single image serving both.
  Nothing to change in the deploy directory; the old `zapzap-frontend` images are tagged, so
  `docker image prune` keeps them: remove them by tag (the `deploy` skill, "Disk on the NAS").
- 2026-09-25 (feat/delete-own-account): the privacy policy is baked into the proxy image rather than served by the React image or mounted from the deploy directory: the NAS holds no clone, and the proxy is the one image that owns the site's own paths (`/app`, `/nginx-health`). A policy change is then an ordinary deploy.
