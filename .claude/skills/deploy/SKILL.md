---
name: deploy
description: Deploy ZapZap to production on the Synology NAS (192.168.1.147) — the git clone there, deploy.sh (git pull, docker-compose build, up), the database safety check, the health check through the public URL, logs, and rollback to the previous commit. Use after a merge that changed frontend/, frontend-flutter/, the Node backend, nginx/ or the compose files, when rolling back a bad deploy, or when diagnosing the live service. Triggers: "déploie", "deploy", "mets en prod", "push to prod", "rollback", "logs de prod", "le site est down".
---

# Deploying to the NAS

Facts, and why it works this way: `.llmwiki/Deployment.md`. Production runs the **Node**
backend (`src/`, root `Dockerfile`), the React frontend on `/` and the Flutter PWA on
`/app/`, from the root `docker-compose.yml`. `zapzap-rust/` is not deployed yet (a wip
entry).

Every command runs over `ssh vemore@192.168.1.147`; Docker is in `/usr/local/bin`, so start
remote commands with `export PATH=$PATH:/usr/local/bin;`. The clone is
`/home/vemore/workspace/zapzap`, on `master`, tracking GitHub over https. Its `.env` holds
the secrets: never print it, never copy it off the NAS.

## 0. Before anything: the database must not be tracked

The production database is `data/zapzap.db` in that clone, bind-mounted as `/app/data`.
Until 2026-09-22 git tracked it; master no longer does, so a `git pull` against a clone that
still tracks it either stops ("local changes would be overwritten") or — if the file were
unmodified — **deletes the production database**.

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

## 1. Preflight

- The commit to deploy is on `origin/master` and its CI is green (`gh run list --branch
  master --limit 1`).
- Note the commit production runs now — the rollback target:
  `ssh vemore@192.168.1.147 'cd /home/vemore/workspace/zapzap && git rev-parse --short HEAD'`.
- `git status --short` on the NAS shows nothing tracked as modified. Anything else: stop and
  ask the user — someone changed production by hand.
- Back up the database: `cp -p data/zapzap.db data/zapzap.db.bak-$(date +%F-%H%M)` (keep the
  last few; they are gitignored).
- **Room to build** — a deploy that rebuilds the Flutter PWA image needs both:

```bash
ssh vemore@192.168.1.147 'df -h /volume1; free -m; export PATH=$PATH:/usr/local/bin; docker system df; docker-compose version'
```

  - **≥ 6 GB free**: the builder stage is 3.47 GB (Flutter SDK 2.3 GB, pub cache 650 MB) and
    the served image 107 MB, plus transient space. Prune with `docker image prune -f`.
  - **≥ 2 GB free RAM**: `dart2js` needs about that; a NAS short of it fails the build
    mid-way (and the site is already down by then).
  - **`docker-compose` v2**: v1 ignores `depends_on.condition` and leaves orphan containers
    behind. If it reports 1.x, say so before going on.

## 2. Deploy

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && ./deploy.sh'
```

`deploy.sh` pulls, stops the four containers, rebuilds the images and starts them. The site
is down for the build (a few minutes). It exits at the first failing step (`set -e`).

The **first** deploy that carries the Flutter PWA builds `zapzap-frontend-flutter` too: it
downloads the Flutter SDK inside the image, so allow several extra minutes and **~3.6 GB of
new Docker storage** (builder 3.47 GB + image 107 MB) — the §1 preflight checks the room.
If the build fails, the site stays down: roll back (§4).

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

All four containers `healthy`, health answers 200, `/` still serves the React client, `/app/`
carries the `/app/` base href, `/app/parties` answers 200, no error at startup. Then drive
the path the change touched in a browser (Playwright on
`https://zapzap.ombivince.synology.me/`); for the PWA, sign in at `/app/` and check Chrome
offers "Install app" (its installability check must report no error). Record what was
checked.

## 4. Roll back

To the commit noted in §1, on a detached HEAD, rebuilt the same way:

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && \
  git checkout --detach <previous-sha> && docker-compose down --remove-orphans && \
  docker-compose build && docker-compose up -d'
```

`--remove-orphans`: a commit older than the Flutter PWA declares no `frontend-flutter`
service, and without it the container stays up as an orphan. If it survives anyway:
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
