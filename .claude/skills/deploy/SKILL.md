---
name: deploy
description: Deploy ZapZap to production on the Synology NAS (192.168.1.147) — the git clone there, deploy.sh (git pull, docker-compose build, up), the database safety check, the health check through the public URL, logs, and rollback to the previous commit. Use after a merge that changed frontend/, the Node backend, nginx/ or the compose files, when rolling back a bad deploy, or when diagnosing the live service. Triggers: "déploie", "deploy", "mets en prod", "push to prod", "rollback", "logs de prod", "le site est down".
---

# Deploying to the NAS

Facts, and why it works this way: `.llmwiki/Deployment.md`. Production runs the **Node**
backend (`src/`, root `Dockerfile`) and the React frontend, from the root
`docker-compose.yml`. `zapzap-rust/` is not deployed yet (a wip entry).

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

## 2. Deploy

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && ./deploy.sh'
```

`deploy.sh` pulls, stops the three containers, rebuilds the images and starts them. The site
is down for the build (a few minutes). It exits at the first failing step (`set -e`).

## 3. Verify

```bash
curl -fsS https://zapzap.ombivince.synology.me/api/health
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker ps --format "{{.Names}}\t{{.Status}}" | grep zapzap'
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; docker logs --tail 50 zapzap-backend'
```

All three containers `healthy`, health answers 200, no error at startup. Then drive the path
the change touched in a browser (Playwright on `https://zapzap.ombivince.synology.me/`), and
record what was checked.

## 4. Roll back

To the commit noted in §1, on a detached HEAD, rebuilt the same way:

```bash
ssh vemore@192.168.1.147 'export PATH=$PATH:/usr/local/bin; cd /home/vemore/workspace/zapzap && \
  git checkout --detach <previous-sha> && docker-compose down && docker-compose build && docker-compose up -d'
```

Verify as in §3. The clone stays detached until the fix is merged; the next deploy starts
with `git checkout master`. A schema change the old code cannot read needs the database
backup of §1 — restoring it loses what players did since: ask the user first.

## 5. After

The fix of whatever broke is a new pull request (`ship-parallel` §6), never a hand edit on
the NAS.
