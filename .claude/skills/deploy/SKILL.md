---
name: deploy
description: Deploy ZapZap to production on the Synology NAS (192.168.1.147) — the git clone there, deploy.sh (git pull, docker-compose build, then down/up), the database safety check, the health check through the public URL, logs, and rollback to the previous commit. Use after a merge that changed zapzap-rust/ (the Rust backend production runs), frontend/, frontend-flutter/, nginx/ or the compose files, when rolling back a bad deploy, or when diagnosing the live service. Triggers: "déploie", "deploy", "mets en prod", "push to prod", "rollback", "logs de prod", "le site est down".
---

# Deploying to the NAS

Facts, and why it works this way: `.llmwiki/Deployment.md`. Production runs the **Rust**
backend (`zapzap-rust/`, built with `CARGO_FEATURES=bedrock`, service `backend`, container
`zapzap-backend`), the React frontend on `/` and the Flutter PWA on `/app/`, from the root
`docker-compose.yml`. A rollback is the previous commit of that deployment (§4).

Every command runs over `ssh vemore@192.168.1.147`; Docker is in `/usr/local/bin`, so start
remote commands with `export PATH=$PATH:/usr/local/bin;`. The clone is
`/home/vemore/workspace/zapzap`, on `master`, tracking GitHub over https. Its `.env` holds
the secrets: never print it, never copy it off the NAS.

## 0. Before anything: the database must not be tracked

The production database is `data/zapzap.db` in that clone, bind-mounted as `/app/data`.
Until 2026-09-22 git tracked it; master no longer does, so a `git pull` against a clone that
still tracks it either stops ("local changes would be overwritten") or — if the file were
unmodified — **deletes the production database**. `deploy.sh` refuses to run while the file
is tracked and prints the sequence below, but check it yourself first: the refusal is a net,
not the procedure.

```bash
ssh vemore@192.168.1.147 'cd /home/vemore/workspace/zapzap && git ls-files data/zapzap.db'
```

If that prints the path, do this once, and nothing else first:

```bash
ssh vemore@192.168.1.147 'cd /home/vemore/workspace/zapzap && \
  cp -p data/zapzap.db data/zapzap.db.bak-$(date +%F-%H%M) && \
  git rm --cached -q data/zapzap.db && git status --short'
```

`git rm --cached` keeps the file on disk. Check it is still there (`ls -la data/zapzap.db`)
before going on.

### Then pull by hand, before running the script

**`deploy.sh` cannot deploy a change to itself.** bash reads the script as it goes and keeps
the file it opened: after `deploy.sh` pulls a new version of itself, the *old* code carries
on to the end. So the first deploy after any change to `deploy.sh` would run the previous
version's steps — for the change of 2026-09-23 that means the old order (stop, then build)
during the first 3.6 GB Flutter build, with no database guard, no `--ff-only` and no
`--remove-orphans`. Once the database check above is clean, pull the clone yourself first:

```bash
ssh vemore@192.168.1.147 'cd /home/vemore/workspace/zapzap && git pull --ff-only && git log --oneline -1'
```

Then run `./deploy.sh` (its own pull is then a no-op). Run it **from the clone root** as
`./deploy.sh`; it also `cd`s to its own directory, so a call from elsewhere is safe rather
than silently checking the wrong paths.

## 1. Preflight

- The commit to deploy is on `origin/master` and its CI is green (`gh run list --branch
  master --limit 1`).
- Note the commit production runs now — the rollback target:
  `ssh vemore@192.168.1.147 'cd /home/vemore/workspace/zapzap && git rev-parse --short HEAD'`.
  **HEAD is only the commit production runs while no deploy has half-happened.** A pull
  that succeeded and a build that then failed leaves the clone at the new commit with the
  old images serving, so after any failed deploy read the running images instead:
  `docker ps --format '{{.Names}}\t{{.Image}}\t{{.CreatedAt}}'`. Note the rollback target
  *before* anything else, and write it down.
- `git status --short` on the NAS shows nothing tracked as modified, **except** two entries
  §0 left there on 2026-09-22 and that are expected: the staged `D data/zapzap.db`, and
  `?? data/zapzap.db.bak-2026-09-22-1356` — the commit the NAS is on predates the `.gitignore`
  rule for `data/*.db.bak-*` (#24), so its backups show as untracked until the pull brings
  that rule in. Anything else: stop and ask the user — someone changed production by hand,
  and `deploy.sh` will refuse the pull rather than merge over it (§2).
- Back up the database: `cp -p data/zapzap.db data/zapzap.db.bak-$(date +%F-%H%M)` (keep the
  last few). They are gitignored from #24 on, and the commit hook refuses them — but a clone
  older than #24 shows them as untracked, which is the second expected entry above.
- **`data/` is writable by uid 1000**, the user the backend image runs as. A file in it owned
  by anyone else (a backup restored as root, say) makes the database or the LLM bots' memory
  unwritable. `vemore` cannot `chown` a root file, a container can; the `find` must print
  nothing (backups `*.bak-*` are left out: the backend never opens them):

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && \
  find data -maxdepth 2 \( -name "zapzap.db*" -o -path "data/bot-strategies*" \) ! -name "*.bak-*" ! -uid 1000'
# if it prints anything:
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && \
  docker run --rm -v "$PWD/data:/data" alpine sh -c "chown -R 1000:1000 /data/bot-strategies /data/zapzap.db*"'
```

- **Room to build** — a deploy that rebuilds the Flutter PWA image needs both:

```bash
ssh vemore@192.168.1.147 'df -h /volume1; free -m; export PATH=$PATH:/usr/local/bin; docker system df; docker-compose version'
```

  - **≥ 6 GB free**: the builder stage is 3.47 GB (Flutter SDK 2.3 GB, pub cache 650 MB) and
    the served image 107 MB, plus transient space. Prune with `docker image prune -f`.
    A Rust backend rebuild adds its own builder stage (`rust:1.92-slim-bookworm` and a release
    `target/` with the AWS SDK; not measured on the NAS) for a served image of 135 MB.
  - **≥ 2 GB free RAM**: `dart2js` needs about that; a NAS short of it fails the build
    mid-way — which since 2026-09-23 costs nothing but the wasted minutes, because
    `deploy.sh` builds before it stops anything (§2).
  - **`docker-compose` version**: the NAS runs **1.29.2**, the v1 Python CLI. The procedure
    here works on it — that is why every `down` carries `--remove-orphans`, which v1 needs
    to remove a container the compose file no longer declares (it otherwise only warns, and
    then fails to remove the network). 1.29.2 does honour `depends_on: condition:
    service_healthy`, so `zapzap-proxy` waits for `backend` and `frontend`. Upgrading to
    v2 is tracked separately; note the version you saw, and do not assume v2 behaviour.

## 2. Deploy

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && ./deploy.sh'
```

`deploy.sh` checks the database is untracked (refusing too when git cannot answer), pulls
(`--ff-only`), **builds the images while the old containers keep serving**, then runs
`docker-compose down --remove-orphans` and `docker-compose up -d`, and finally **waits until
`backend`, `frontend` and `nginx` are healthy and `/api/health` answers 200**. It exits at
the first failing step (`set -e`, `pipefail`).

**Read its exit status; it is three-valued.**

| Exit | Meaning | What to do |
|---|---|---|
| `0` | deployed, every container healthy | §3 |
| `1` | refused before touching anything, **or** an outage | the message says which; §4 for an outage |
| `2` | deployed and serving, but a **non-essential** service is not healthy | §3, then fix that service in a new pull request |

The essential set is `backend frontend nginx` — the proxy plus what its `depends_on`
conditions wait on, which is what serves `/`, `/api/` and `/suscribeupdate`. It is named
once at the top of `deploy.sh` (`ESSENTIAL_SERVICES`, `PROXY_SERVICE`), and the script
**refuses before building** if the compose file stops declaring one of them, so a rename
cannot quietly turn an essential service into an optional one. **`frontend-flutter` is
deliberately not in it**: nginx resolves the PWA per request (`nginx/nginx.conf`), so a PWA
container that never becomes healthy costs `/app/` a 502 and nothing else. That case prints
a `⚠ WARNING` naming the container and its state, says the React client and the API are
unaffected, shows its last 30 log lines, says a rollback is **optional**, ends with
`⚠ Deployed, DEGRADED: …` instead of `✨ Deployment complete!`, and exits **2**. Do not read
it as an outage and do not roll back for it by reflex — the site is serving, and fixing the
PWA in a new pull request keeps it that way.

- **The site is down only for the down/up window.** The script's `✓ Site answering again —
  downtime was 3.4s` is measured from just before the `down` to the first 200, so it
  counts the containers' start-up too, not just how long compose took. The build before it
  costs no downtime at all, however long it takes.
- **A failed build stops nothing.** Production is still serving the previous images, so
  there is no outage and **nothing to roll back**: fix the cause and run `./deploy.sh`
  again. But the clone *did* pull, so HEAD no longer says what production runs — read the
  running images (§1).
- **A refusal before the build** — a tracked `data/zapzap.db` (§0), git unable to answer, or
  a pull that would not fast-forward — leaves production untouched. For the pull, read
  **git's own message**, which the script prints above its own: a diverged branch and a
  detached HEAD are the usual causes, but so are an untracked file the pull would overwrite
  and plain DNS or credential failures. Fix it by hand (`git status --short`,
  `git checkout master`), never with a force or a blind merge.
- **A failing `down`, a failing `up -d`, or an *essential* service that never becomes
  healthy are all outages, and the script says so.** A failing `down` may leave the stack
  half stopped; the script immediately retries `up -d` and then tells you to look at
  `docker ps -a` (a `down` that fails on "network has active endpoints" usually means a
  container the compose file no longer declares: `docker rm -f <name>`, then deploy again).
  An essential service not healthy — or `/api/health` not answering 200 — within 90 s exits
  **1**, names each container with its state and prints its last 30 log lines. **`up -d`
  returning 0 is not success**: a container crash-looping under `restart: unless-stopped`
  satisfies it, which is exactly what the health wait is there to catch. Roll back (§4) if
  the logs do not point at something you can fix at once.
- **A non-essential service that never becomes healthy is not an outage.** It gets its own
  60 s grace once the site is answering, then a `⚠ WARNING`, its logs, and exit **2**. For
  `frontend-flutter` that means `/app/` answers 502 while `/`, `/api/` and `/suscribeupdate`
  serve normally — verify with §3's list and the PWA checks will fail, which is expected;
  the fix is a new pull request, not a rollback.

The **first** deploy that carries the Flutter PWA builds `zapzap-frontend-flutter` too: it
downloads the Flutter SDK inside the image, so allow several extra minutes and **~3.6 GB of
new Docker storage** (builder 3.47 GB + image 107 MB) — the §1 preflight checks the room.

The PWA cannot take the site down by itself — `/app/` is resolved per request
(`nginx/nginx.conf`) and no `depends_on` waits on its health, so a broken PWA is a 502 on
`/app/` while `/` and `/api/` serve. If `up -d` nevertheless aborts with "dependency failed
to start" and `docker ps -a` shows `zapzap-proxy` in `Created`, start it by hand — that
restores `/` and `/api/` immediately, and only works while the container exists:

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker start zapzap-proxy'
```

## 3. Verify

```bash
curl -fsS https://zapzap.ombivince.synology.me/api/health
curl -fsS -o /dev/null -w '%{http_code}\n' https://zapzap.ombivince.synology.me/
# The Flutter PWA: the page, a deep link (the SPA fallback), and the manifest.
curl -fsS https://zapzap.ombivince.synology.me/app/ | grep -o '<base href="/app/">'
curl -fsS -o /dev/null -w '%{http_code}\n' https://zapzap.ombivince.synology.me/app/parties
curl -fsS https://zapzap.ombivince.synology.me/app/manifest.json | head -6
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker ps --format "{{.Names}}\t{{.Status}}" | grep zapzap'
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker logs --tail 50 zapzap-backend'
```

The backend logs are the Rust ones (`RUST_LOG`, `info` by default): a `Starting ZapZap backend
on 0.0.0.0:9999` line, and `AWS Bedrock LLM service initialized` when the LLM bots are on.

**After a deploy that changed the backend, prove it serves, and serves the players'
data**, from your own machine:

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker inspect -f "{{.Config.Image}} {{.Config.Cmd}} {{.Created}}" zapzap-backend; docker logs zapzap-backend 2>&1 | grep -m1 "Starting ZapZap backend"'
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

The container runs `[/app/zapzap-backend]` and was created by this deploy, the log has the
start-up line, the login answers a token, and each `/state` answers 200 — a 500 there, with
`Invalid game state JSON` in the log, is a stored game state the backend cannot read. A party the account does not play in
is checked by its players; watch the log (`docker logs -f zapzap-backend`) while they do.

All four containers `healthy`, health answers 200, `/` still serves the React client, `/app/`
carries the `/app/` base href, `/app/parties` answers 200, no error at startup. Then drive
the path the change touched in a browser (Playwright on
`https://zapzap.ombivince.synology.me/`); for the PWA, sign in at `/app/` and check Chrome
offers "Install app" (its installability check must report no error). Record what was
checked.

## 4. Roll back

To the commit noted in §1 — **the one you wrote down before deploying**, not whatever HEAD
says now: a deploy that pulled and then failed already moved HEAD forward. On a detached
HEAD, rebuilt in the same order `deploy.sh` uses — **build, then down, then up**, so a
rollback whose build fails leaves whatever is currently serving alone instead of adding an
outage to an outage. The target is always a Rust commit: one older than `b3fb9e6` (#99)
builds the Node backend, removed since, and is no rollback target any more.

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && \
  git checkout --detach <previous-sha> && docker-compose build && \
  docker-compose down --remove-orphans && docker-compose up -d'
```

`--remove-orphans`: a commit older than the Flutter PWA declares no `frontend-flutter`
service, and without it the container stays up as an orphan — on `docker-compose` v1 the
`down` then only warns and fails to remove the network. If it survives anyway:
`docker rm -f zapzap-frontend-flutter`.

**Verify a rollback with this list, not §3** — §3 describes the newer deployment, and on a
version without the PWA `/app/` answers **200 with the React index.html** (the `/` SPA
fallback), which reads like a pass:

```bash
curl -fsS https://zapzap.ombivince.synology.me/api/health
curl -fsS -o /dev/null -w '%{http_code}\n' https://zapzap.ombivince.synology.me/
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker ps --format "{{.Names}}\t{{.Status}}" | grep zapzap'
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker logs --tail 50 zapzap-backend'
```

Health 200, `/` serves the React client, the containers the rolled-back commit declares are
all `healthy` (**three** before the PWA, four after) and no other `zapzap-*` container is
left running, no error at startup. Then sign in on `/` in a browser. `/app/` is expected to
be gone: do not read its 200 as the PWA working.

The clone stays detached until the fix is merged; the next deploy starts with
`git checkout master`. A schema change the old code cannot read needs the database backup of
§1 — restoring it loses what players did since: ask the user first.

## 5. After

The fix of whatever broke is a new pull request (`ship-parallel` §6), never a hand edit on
the NAS.
