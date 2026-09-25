---
name: deploy
description: Deploy ZapZap to production on the NAS (192.168.1.147) — scripts/deploy_nas.sh builds the four images on the dev machine, pushes them to the LAN registry 192.168.1.25:5050 tagged with the 12-character sha, and the NAS deploy directory /home/vemore/docker/zapzap (no git clone) pulls and starts them; the health wait, the checks through the public URL, logs, `--rollback <sha>` (the compose file that tag ran with), `--build-only`, and the one-off switch from the old NAS clone. Use after a merge that changed zapzap-rust/ (the Rust backend production runs), frontend/, frontend-flutter/, nginx/ or docker-compose.prod.yml, when rolling back a bad deploy, or when diagnosing the live service. Triggers: "déploie", "deploy", "mets en prod", "push to prod", "rollback", "logs de prod", "le site est down".
---

# Deploying to the NAS

Facts, and why it works this way: `.llmwiki/Deployment.md`. Production runs four containers
from `docker-compose.prod.yml`: the **Rust** backend (`zapzap-backend`, built with
`CARGO_FEATURES=bedrock`), the React client on `/`, the Flutter PWA on `/app/` and the proxy
(`zapzap-proxy`, `nginx/nginx.conf` baked in). **Nothing is built on the NAS and it holds no
clone**: `scripts/deploy_nas.sh` builds on the dev machine, pushes to the registry, and the
NAS pulls.

| | |
|---|---|
| NAS | `ssh vemore@192.168.1.147`; Docker in `/usr/local/bin` (remote commands start with `export PATH=$PATH:/usr/local/bin;`), `docker-compose` **1.29.2** (v1) |
| Deploy directory | `/home/vemore/docker/zapzap`: `compose.yaml` (written by the script), `.env` (the secrets — **never print it, never copy it off the NAS**), `data/` (`zapzap.db`, `bot-strategies/`, backups) |
| Registry | `192.168.1.25:5050`, authenticated; images `zapzap-backend`, `zapzap-frontend`, `zapzap-frontend-flutter`, `zapzap-proxy`, each tagged with the first 12 characters of the sha and `latest` |
| Configuration | `scripts/deploy.env` (gitignored; from `scripts/deploy.env.example`): `REGISTRY`, `NAS_SSH`, `NAS_DEPLOY_DIR`, `PUBLIC_URL`; the Google client id comes from the repository's `.env` |

Every command on the NAS by hand uses the project name the script uses:

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin COMPOSE_PROJECT_NAME=zapzap; cd /home/vemore/docker/zapzap && docker-compose -f compose.yaml ps'
```

## 0. Once per machine

On the dev machine that deploys (the main checkout, or a worktree set up with
`scripts/worktree_setup.sh --deploy`, which links the main checkout's `.env` and
`scripts/deploy.env`):

- `cp scripts/deploy.env.example scripts/deploy.env` and check its values.
- `/etc/docker/daemon.json` lists `"insecure-registries": ["192.168.1.25:5050"]` (the dev
  machine has it) and `docker login 192.168.1.25:5050` has been done.
- `.env` at the repository root holds `VITE_GOOGLE_OAUTH_CLIENT_ID` (not a secret; the script
  refuses to build without it). Read it without printing the file:
  `grep -c '^VITE_GOOGLE_OAUTH_CLIENT_ID=.' .env` answers `1`.
- **Room to build is needed here, on the dev machine, not on the NAS**: ≥ 6 GB free for
  Docker (the Flutter builder stage alone is ~3.5 GB; the Rust builder, `rust:1.92-alpine`
  with `musl-dev cmake perl make clang linux-headers`, adds its own for a ~29 MB image) and
  ≥ 2 GB free RAM (`dart2js`). `df -h /var/lib/docker; free -m; docker system df`. A build
  short of it fails before anything is pushed, which costs nothing but the minutes. The NAS
  only needs room for the pulled images.

### First deploy: switching the NAS from the old clone

Until this is done, production runs from the git clone `/home/vemore/workspace/zapzap` on the
NAS, built there by the removed `deploy.sh`. The switch touches production and needs `sudo`
on the NAS: **the user runs or approves each step.** Its containers have the same names and
the same compose project (`zapzap`) as the deploy directory's, so the first
`deploy_nas.sh` replaces them.

0. **#106 (the Alpine backend image) is merged *and deployed* first**, through the old clone
   and its `deploy.sh`, as any deploy before this switch. `docker-compose.prod.yml` checks the
   backend with `wget`, which only that image carries: `deploy_nas.sh` refuses to push a
   backend image without it, so building from a master that lacks #106 stops at the build.

1. **The NAS trusts the registry.** `/etc/docker/daemon.json` does not exist there
   (2026-09-25). Restarting the daemon stops every container of the NAS for a few seconds —
   schedule it; `restart: unless-stopped` brings them back. The NAS is an Ubuntu host with
   Docker in `/usr/local/bin`: if `systemctl restart docker` names no unit there, find how
   its daemon is started (`systemctl list-units | grep -i docker`) before going on.

   ```bash
   ssh -t vemore@192.168.1.147 'echo "{\"insecure-registries\": [\"192.168.1.25:5050\"]}" | sudo tee /etc/docker/daemon.json && sudo systemctl restart docker'
   ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker info 2>/dev/null | grep -A3 "Insecure Registries"'   # lists 192.168.1.25:5050
   ```

2. **The NAS logs in to the registry**, the user typing the credentials:
   `ssh -t vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker login 192.168.1.25:5050'`.

3. **The deploy directory, and the secrets**, copied without printing them (the clone keeps
   its copy as the fallback of step 8; it goes with the clone):

   ```bash
   ssh vemore@192.168.1.147 'mkdir -p /home/vemore/docker/zapzap/data && cp -p /home/vemore/workspace/zapzap/.env /home/vemore/docker/zapzap/.env && ls -la /home/vemore/docker/zapzap'
   ```

4. **Build and push first, while the clone still serves**, from the dev machine (§0 done,
   §1's clean checkout of master):

   ```bash
   scripts/deploy_nas.sh --build-only
   ```

   It builds, checks the backend image has `wget`, and pushes — without touching the NAS,
   so it does not need the deploy directory's database yet. Step 6's deploy then rebuilds
   from the Docker cache in seconds and its pushes are no-ops: the downtime is only the
   data copy, the pull and the start.

5. **Count what must survive**, before anything stops:

   ```bash
   ssh vemore@192.168.1.147 'cd /home/vemore/workspace/zapzap && python3 -c "import sqlite3; c=sqlite3.connect(\"file:data/zapzap.db?mode=ro\", uri=True); print([c.execute(f\"SELECT COUNT(*) FROM {t}\").fetchone()[0] for t in (\"users\", \"parties\")])"'
   ```

6. **Stop the clone's stack, back up and copy the data.** Downtime starts here and lasts until
   step 7's health wait ends (a copy, a pull and a start: the images are pushed already).
   The backend reads only `zapzap.db` and `bot-strategies/` from `data/`; the tracked bot
   parameter files and models there are not read by the Rust backend.

   ```bash
   ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && \
     docker-compose down --remove-orphans && \
     cp -p data/zapzap.db data/zapzap.db.bak-$(date +%F-%H%M) && \
     cp -a data/zapzap.db data/bot-strategies /home/vemore/docker/zapzap/data/ && \
     find /home/vemore/docker/zapzap/data -maxdepth 2 ! -uid 1000'    # prints nothing
   ```

7. **The first deploy**, from the dev machine: `scripts/deploy_nas.sh` (§2). Then §3, and the
   checks of the switch itself:

   ```bash
   ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker inspect -f "{{range .Mounts}}{{.Source}} {{end}}" zapzap-backend'   # /home/vemore/docker/zapzap/data
   ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker images --format "{{.Repository}}:{{.Tag}}" | grep zapzap'
   ```

   and the counts of step 5 again, run in `/home/vemore/docker/zapzap`: the same numbers.

   **If it fails** and no quick fix is in sight, the clone is the fallback, untouched:
   `ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin COMPOSE_PROJECT_NAME=zapzap; cd /home/vemore/docker/zapzap && docker-compose -f compose.yaml down --remove-orphans; cd /home/vemore/workspace/zapzap && docker-compose up -d'`
   — on the database *of the clone*: anything played on the new stack meanwhile is lost,
   so ask the user first if players were on.

8. **At D+7**, the new stack having held: delete the clone (its `.env` goes with it) and its
   locally built images (`zapzap_backend`, `zapzap_frontend`, `zapzap_frontend-flutter`,
   and what `docker image prune` then finds dangling). Ask the user before deleting.

## 1. Preflight

- The commit to deploy is on `origin/master` and its CI is green (`gh run list --branch
  master --limit 1`), and the checkout you deploy from is **on that commit and clean**: the
  script refuses a modified tracked file, and an untracked one in a build context
  (`zapzap-rust/`, `frontend/`, `frontend-flutter/`, `nginx/`), before building anything.
  `git switch master && git pull --ff-only` in the main checkout.
- **Note the rollback target**: what production runs now.

  ```bash
  ssh vemore@192.168.1.147 'grep "image:" /home/vemore/docker/zapzap/compose.yaml'
  ```

  The file names exactly what runs (tags are the first 12 characters of the commit sha): the
  script swaps it only once the new images are pulled and the old stack is down, keeps the
  one before as `compose.yaml.prev`, and every deployed one as `composes/compose.<tag>.yaml`
  (the last 10) — what a rollback restores. The script also prints the tag it replaces.
- Registry login on the dev machine: `docker login 192.168.1.25:5050` if the last push was
  refused.
- Disk on the NAS: each deploy pulls four images (the backend's is the largest) and keeps the
  previous tags, which is what makes a rollback a pull-free restart. Prune old tags now and
  then, never the last two deploys': `docker images | grep 192.168.1.25:5050/zapzap`.

The script checks the rest itself, on the NAS, before building: the deploy directory, its
`.env`, `data/zapzap.db`, and that **uid 1000** (the backend image's user) owns `data/`, the
database files and `bot-strategies/` — refusing with the `chown` to run otherwise.

## 2. Deploy

```bash
scripts/deploy_nas.sh
```

In order, stopping at the first failure:

1. configuration (`REGISTRY`, `NAS_SSH`, `NAS_DEPLOY_DIR`, each named when missing), a clean
   tree, the Google client id;
2. the NAS check above, **before** a build of several minutes;
3. four `docker build`s of HEAD, each tagged with the first 12 characters of the sha and
   `latest`, labelled with the full revision; a refusal if the backend image has no `wget`
   (its health check); four pushes of each tag;
4. `docker-compose.prod.yml` sent to the NAS as `compose.yaml.next`, the registry and the tag
   written in;
5. on the NAS: `docker-compose config` (a `.env` without `JWT_SECRET`, or a compose file
   missing an essential service, is refused), `docker-compose pull` — **the old containers
   still serving** —, the database backup `data/zapzap.db.bak-<YYYY-MM-DD-HHMMSS>-<tag>` by
   SQLite's online backup (python3), checked with `integrity_check`, never over an existing
   file;
6. `down --remove-orphans` **with the running compose file**; only once it succeeded,
   `compose.yaml` → `compose.yaml.prev`, `.next` → `compose.yaml` (and a copy in `composes/`);
   `up -d`, and **the health wait**: `backend`, `frontend` and `nginx` healthy and
   `/api/health` 200 within 90 s; then a 60 s grace for `frontend-flutter`.

`scripts/deploy_nas.sh --build-only` stops after the pushes: it needs only `REGISTRY` and
never contacts the NAS.

**Read its exit status; it is three-valued.**

| Exit | Meaning | What to do |
|---|---|---|
| `0` | deployed, every container healthy | §3 |
| `1` | refused before touching anything, **or** an outage | the message says which; §4 for an outage |
| `2` | deployed and serving, but a **non-essential** service is not healthy | §3, then fix that service in a new pull request |

- **Everything up to the backup stops nothing**: a failed build, push, `config`, pull or
  backup, a backend image without `wget`, a missing `.env`, database or ownership —
  production still serves what it served and `compose.yaml` is unchanged. Fix the cause and
  run the script again.
- **The site is down only for the down/up window**, and the script's `✓ Site answering again
  — downtime was 3.4s` is measured from just before the `down` to the first 200.
- **A failing `down`, a failing `up -d`, or an essential service not healthy in 90 s are
  outages**, and the script says so: it names each container with its state, prints its
  last 30 log lines, and names the rollback command with the previous tag. A failing `down`
  immediately restarts the compose file that was running — never the new, unchecked images. `up -d` returning 0 is not success: a container crash-looping
  under `restart: unless-stopped` satisfies it.
- **`frontend-flutter` is deliberately not essential**: nginx resolves it per request, so an
  unhealthy PWA is a 502 on `/app/` and nothing else. The script warns, says a rollback is
  optional, ends with `⚠ Deployed <sha>, DEGRADED: …` and exits 2. Do not roll back for it by
  reflex. If `docker ps -a` ever shows `zapzap-proxy` in `Created`,
  `docker start zapzap-proxy` restores `/` and `/api/` at once.
- **An ssh drop mid-deploy** exits 1 saying what production runs is unknown: look
  (`docker ps -a` on the NAS) before anything else.

`ESSENTIAL_SERVICES` and `PROXY_SERVICE` at the top of `scripts/deploy_nas.sh`,
`docker-compose.prod.yml` and `nginx/nginx.conf` change together.

## 3. Verify

```bash
curl -fsS https://zapzap.ombivince.synology.me/api/health
curl -fsS -o /dev/null -w '%{http_code}\n' https://zapzap.ombivince.synology.me/
# The Flutter PWA: the page, a deep link (the SPA fallback), and the manifest.
curl -fsS https://zapzap.ombivince.synology.me/app/ | grep -o '<base href="/app/">'
curl -fsS -o /dev/null -w '%{http_code}\n' https://zapzap.ombivince.synology.me/app/parties
curl -fsS https://zapzap.ombivince.synology.me/app/manifest.json | head -6
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}" | grep zapzap'
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker logs --tail 50 zapzap-backend'
```

The four containers run `192.168.1.25:5050/zapzap-*:<the sha deployed>` and are `healthy`.
The backend logs are the Rust ones (`RUST_LOG`, `info` by default): a `Starting ZapZap backend
on 0.0.0.0:9999` line, and `AWS Bedrock LLM service initialized` when the LLM bots are on.

**After a deploy that changed the backend, prove it serves, and serves the players'
data**, from your own machine:

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker inspect -f "{{.Config.Image}} {{index .Config.Labels \"org.opencontainers.image.revision\"}} {{.Created}}" zapzap-backend; docker logs zapzap-backend 2>&1 | grep -m1 "Starting ZapZap backend"'
# A password login through the public URL. The operator types the account and password;
# nothing is echoed, stored or put on a command line. A dedicated test account keeps a
# player's password out of it, but any account works.
read -rp 'user: ' U; read -rsp 'password: ' PW; echo
TOKEN=$(jq -n --arg u "$U" --arg p "$PW" '{username: $u, password: $p}' \
  | curl -fsS -H 'content-type: application/json' -d @- https://zapzap.ombivince.synology.me/api/auth/login \
  | jq -r .token); unset PW; [ -n "$TOKEN" ] && [ "$TOKEN" != null ] && echo "login: ok"
# The parties being played (an admin account), then the state of those this account plays in.
curl -fsS -H "authorization: Bearer $TOKEN" 'https://zapzap.ombivince.synology.me/api/admin/parties?status=playing' | jq -r '.parties[] | "\(.id) \(.name)"'
curl -fsS -o /dev/null -w '%{http_code}\n' -H "authorization: Bearer $TOKEN" https://zapzap.ombivince.synology.me/api/game/<id>/state
unset TOKEN
```

The image carries the deployed revision in its label, the log has the start-up line, the
login answers a token, and each `/state` answers 200 — a 500 there, with `Invalid game state
JSON` in the log, is a stored game state the backend cannot read. A party the account does
not play in is checked by its players; watch the log (`docker logs -f zapzap-backend`).

**One real LLM bot move, after a deploy that changed the backend image.** No test crosses
the Bedrock TLS handshake from the production image, so prove it: in a browser, start a
party with an `llm` bot among the players, play until the bot has played a turn, then

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker logs --since 15m zapzap-backend 2>&1 | grep -E "LLM (selected play|draw decision|play selection failed|draw decision failed|ZapZap decision failed)"'
```

`LLM selected play` / `LLM draw decision` lines are a Bedrock round trip that worked
(`zapzap-rust/src/infrastructure/bot/strategies/llm_bot.rs`); a `… failed` line — or none,
the bot quietly playing like Hard — means the LLM service is broken or off
(`AWS Bedrock LLM service initialized` missing at start-up). The site still serves: fix it in
a new pull request, not by a rollback, unless the user wants the LLM bots back at once.

All four containers `healthy`, health answers 200, `/` still serves the React client, `/app/`
carries the `/app/` base href, `/app/parties` answers 200, no error at startup. Then drive
the path the change touched in a browser (Playwright on
`https://zapzap.ombivince.synology.me/`); for the PWA, sign in at `/app/` and check Chrome
offers "Install app". Record what was checked.

## 4. Roll back

To the sha noted in §1 (or the one the failing deploy printed):

```bash
scripts/deploy_nas.sh --rollback <sha>
```

It builds nothing and needs no clean tree. `<sha>` is a commit (shortened to its 12-character
tag) or a tag as `composes/` names it. On the NAS it restores **the compose file that tag was
deployed with** — its environment and health checks, not only its images —,
`composes/compose.<tag>.yaml`; for a tag older than the last 10 deploys, it uses that
commit's `docker-compose.prod.yml`, rendered on the dev machine from git, and a tag neither
stored nor known to the local checkout is refused, stopping nothing. It skips the pull when
every image is still on the NAS (so a rollback works with the registry down or the login
expired), otherwise pulls — a tag no deploy pushed is refused there, stopping nothing —, then
the same backup, `down`, swap, `up -d`, health wait and exit codes as a deploy. Verify with
§3.

The target is always a commit deployed through the registry; the images the old clone built
are not in it. A schema change the older backend cannot read needs a database backup
(`data/zapzap.db.bak-<date>-<tag>`, one per deploy and rollback): restoring it loses what players did since —
ask the user first.

## 5. After

The fix of whatever broke is a new pull request (`ship-parallel` §6), never a hand edit on
the NAS. A `.env` change alone needs no deploy: edit it on the NAS (never print it), then
`docker-compose -f compose.yaml up -d` in the deploy directory with
`COMPOSE_PROJECT_NAME=zapzap`, and §3.
