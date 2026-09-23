#!/bin/bash

# ZapZap Deployment Script
# Usage: ./deploy.sh        (from the clone root; it also cd's there itself)
#
# Order matters: pull, *build*, then down/up. The build runs against the new compose
# file while the old containers keep serving, so a build that fails — a network
# timeout on a dependency, ENOSPC, the OOM killer taking dart2js — stops nothing.
# The downtime is the down/up window, and it is not over until the site answers
# again: the script waits for the services that serve the site and for /api/health,
# and exits 1 if they never come. A service that does not serve the site — the
# Flutter PWA — is a warning and exit 2, never an outage.
#
# NOTE: bash keeps executing the *old* file after `git pull` replaces this script,
# so the very first deploy after a change to deploy.sh runs the previous version.
# Pull the clone by hand first: .claude/skills/deploy/SKILL.md §0.
#
# Procedure and why: .claude/skills/deploy/SKILL.md, .llmwiki/Deployment.md

set -e           # Exit on error
set -o pipefail  # ... including when the failure is on the left of a pipe

# Everything below is relative to the clone: the database check, the pull and
# docker-compose all read files from here. Without this, `cd data && ../deploy.sh`
# would ask git about a path that does not exist and conclude the database is safe.
cd "$(dirname "$0")" || exit 1

echo "======================================"
echo "🃏 ZapZap Deployment Script"
echo "======================================"
echo "Clone: $(pwd)"
echo ""

# Which services actually serve the site, and which one is the reverse proxy. Both names
# are here, once, because they tie this script to two other files:
#
#   - `nginx` is the proxy service of docker-compose.yml, whose published port this
#     script asks for (`docker-compose port`) and whose health decides the site;
#   - `backend` and `frontend` are what that proxy cannot start without — its
#     `depends_on: condition: service_healthy` entries — and what nginx/nginx.conf
#     proxies `/`, `/api/` and `/suscribeupdate` to.
#
# Everything else the compose file declares is NOT essential, deliberately.
# `frontend-flutter` is the case that matters: nginx resolves it per request
# (nginx/nginx.conf:99-108), so a PWA container that never becomes healthy costs `/app/`
# a 502 and nothing else (#36, .llmwiki/Deployment.md). Renaming or adding a service
# here means updating docker-compose.yml, nginx/nginx.conf and this line together.
PROXY_SERVICE=nginx
ESSENTIAL_SERVICES="backend frontend $PROXY_SERVICE"

is_essential() {  # service name
    case " $ESSENTIAL_SERVICES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# Milliseconds since the epoch, so the reported downtime does not truncate to whole
# seconds. bash 5 has EPOCHREALTIME; GNU date's %3N covers older bash; failing both,
# whole seconds (the figure is then coarse, never wrong).
now_ms() {
    local t
    if [ -n "${EPOCHREALTIME:-}" ]; then
        t=${EPOCHREALTIME/,/.}                       # a comma in some locales
        printf '%s%s\n' "${t%%.*}" "$(printf '%s' "${t#*.}000" | cut -c1-3)"
        return 0
    fi
    t=$(date +%s%3N 2>/dev/null || true)
    case "$t" in
        ''|*[!0-9]*) printf '%s000\n' "$(date +%s)" ;;
        *) printf '%s\n' "$t" ;;
    esac
}

# "3.4s" from a count of milliseconds.
seconds_of() { printf '%d.%ds' "$(( $1 / 1000 ))" "$(( ($1 % 1000) / 100 ))"; }

# The production database must not be tracked: master stopped tracking it (#21), so a
# pull against a clone that still does either stops or — if the file were unmodified —
# deletes every account. Refuse before touching anything, and refuse just as hard when
# git cannot answer at all: an unanswered question is not a clean bill of health.
echo "🔐 Checking the production database is not tracked by git..."
if ! tracked=$(git ls-files -- data/zapzap.db 2>&1); then
    echo "✗ REFUSING TO DEPLOY: cannot ask git whether data/zapzap.db is tracked." >&2
    echo "  git said: $tracked" >&2
    echo "  Nothing was pulled, built or stopped. Usually git is not on PATH:" >&2
    echo "  \`export PATH=\$PATH:/usr/local/bin\` before ./deploy.sh, then retry." >&2
    exit 1
fi
if [ -n "$tracked" ]; then
    cat >&2 <<'EOF'
✗ REFUSING TO DEPLOY: data/zapzap.db is tracked by git in this clone.

  A `git pull` would stop on it, or — were the file unmodified — delete the
  production database. Untrack it once, after a backup, and nothing else first:

      cp -p data/zapzap.db data/zapzap.db.bak-$(date +%F-%H%M)
      git rm --cached data/zapzap.db
      ls -la data/zapzap.db          # `git rm --cached` keeps the file on disk

  Then run ./deploy.sh again. See .claude/skills/deploy/SKILL.md §0.
EOF
    exit 1
fi
echo "✓ Not tracked"
echo ""

# Pull latest code — before the build, so the build is of what we are deploying.
# git's own message is what tells the operator why a refusal happened; guesses below
# it are guesses (a diverged branch, but also DNS, credentials, an untracked file the
# pull would overwrite).
echo "📥 Pulling latest code from git..."
if ! pull_output=$(git pull --ff-only 2>&1); then
    printf '%s\n' "$pull_output" >&2
    echo "" >&2
    echo "✗ REFUSING TO DEPLOY: \`git pull --ff-only\` failed — git's reason is above." >&2
    echo "  Nothing was built and nothing was stopped; production is untouched." >&2
    echo "  Read that reason before assuming a cause. Frequent ones: local commits or" >&2
    echo "  local modifications (\`git status --short\`), a detached HEAD left by a" >&2
    echo "  rollback (\`git checkout master\`), an untracked file the pull would" >&2
    echo "  overwrite, or the network/credentials. Fix it by hand, then retry." >&2
    exit 1
fi
printf '%s\n' "$pull_output"
echo "✓ Code updated"
echo ""

# The pull may have renamed or dropped a service, and ESSENTIAL_SERVICES above would then
# quietly treat a service that serves the site as optional — the health gate would pass
# over an outage. Check the two lists agree now, while nothing has been built or stopped.
declared=$(docker-compose config --services)
for service in $ESSENTIAL_SERVICES; do
    case " $(printf '%s\n' "$declared" | tr '\n' ' ') " in
        *" $service "*) ;;
        *)
            echo "" >&2
            echo "✗ REFUSING TO DEPLOY: deploy.sh expects a service named '$service'," >&2
            echo "  which this compose file does not declare. It declares:" >&2
            printf '%s\n' "$declared" | sed 's/^/    /' >&2
            echo "  Nothing was built and nothing was stopped. ESSENTIAL_SERVICES and" >&2
            echo "  PROXY_SERVICE at the top of deploy.sh, docker-compose.yml and" >&2
            echo "  nginx/nginx.conf have to be changed together." >&2
            exit 1 ;;
    esac
done

# Build images — the old containers are still up and still serving while this runs.
echo "🔨 Building Docker images (production is still serving the old ones)..."
if ! docker-compose build; then
    echo "" >&2
    echo "✗ BUILD FAILED — nothing was stopped." >&2
    echo "  Production is still serving the previous images, so there is no outage and" >&2
    echo "  nothing to roll back. The clone *is* now at the new commit, though: HEAD no" >&2
    echo "  longer tells you what production runs (\`docker ps\` and the image ages do)." >&2
    echo "  Fix the cause (disk, RAM, network — the preflight in" >&2
    echo "  .claude/skills/deploy/SKILL.md §1) and run ./deploy.sh again." >&2
    exit 1
fi
echo "✓ Images built"
echo ""

# Everything is built: the downtime starts here and ends when the site answers again.
#
# --remove-orphans: a compose file that no longer declares a service — a rollback to
# any commit before the Flutter PWA — otherwise leaves the container running, and the
# `down` then fails to remove the network ("Resource is still in use"); docker-compose
# v1, which the NAS runs, only warns about it.
echo "🛑 Stopping containers (downtime starts now)..."
downtime_start_ms=$(now_ms)
if ! docker-compose down --remove-orphans; then
    echo "" >&2
    echo "✗ \`docker-compose down\` FAILED — the stack may be half stopped, so" >&2
    echo "  production may be DOWN. Trying to start it again immediately..." >&2
    docker-compose up -d >&2 || true
    echo "" >&2
    echo "  Check what is running (\`docker ps -a\`) before anything else. A \`down\`" >&2
    echo "  that fails on \"network has active endpoints\" usually leaves a container" >&2
    echo "  the compose file no longer declares: \`docker rm -f <name>\`, then" >&2
    echo "  ./deploy.sh again. Otherwise roll back: .claude/skills/deploy/SKILL.md §4." >&2
    exit 1
fi
echo "✓ Containers stopped"
echo ""

# Start containers
echo "🚀 Starting containers..."
if ! docker-compose up -d; then
    echo "" >&2
    echo "✗ START FAILED — production is DOWN. Act now:" >&2
    echo "  - \`docker ps -a\`: if zapzap-proxy sits in Created, \`docker start" >&2
    echo "    zapzap-proxy\` restores / and /api/ at once." >&2
    echo "  - Otherwise roll back: .claude/skills/deploy/SKILL.md §4." >&2
    exit 1
fi
echo "✓ Containers started"
echo ""

# `up -d` returning 0 means the containers were created, not that anything works: a
# container that crash-loops under `restart: unless-stopped` satisfies it. So poll the
# containers' real state, and split the verdict in two, because the compose file's
# services are not equally load-bearing:
#
#   ESSENTIAL_SERVICES not healthy, or /api/health not answering 200  -> outage, exit 1
#   any other service not healthy, with the site answering            -> degraded, exit 2
#
# Collapsing the two would make an unhealthy `frontend-flutter` — the newest container
# and the likeliest to misbehave — read as "production is DOWN" and push the operator
# into a rollback the site does not need.
proxy_port=$(docker-compose port "$PROXY_SERVICE" 80 2>/dev/null | sed 's/.*://' || true)
case "$proxy_port" in ''|*[!0-9]*) proxy_port=80 ;; esac
health_url="http://localhost:$proxy_port/api/health"

# Echoes "<service>(<state>)" for every service of $1 that is not healthy or running.
not_healthy() {  # space-separated service names
    local service cid state out=""
    for service in $1; do
        cid=$(docker-compose ps -q "$service" 2>/dev/null | head -1)
        if [ -z "$cid" ]; then
            out="$out $service(no container)"
            continue
        fi
        state=$(docker inspect -f \
            '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
            "$cid" 2>/dev/null || true)
        case "$state" in
            healthy|running) ;;
            *) out="$out $service(${state:-unknown})" ;;
        esac
    done
    printf '%s' "$out"
}

# The last 30 log lines of each "<service>(<state>)" in $1, on the given stream.
log_tails() {  # entries
    local entry service
    for entry in $1; do
        service=${entry%%(*}
        echo ""
        echo "  --- last 30 lines of $service ---"
        docker-compose logs --tail 30 "$service" 2>/dev/null || true
    done
}

optional_services=$(docker-compose config --services | while read -r s; do
    is_essential "$s" || printf '%s ' "$s"
done)

echo "⏳ Waiting for $ESSENTIAL_SERVICES to be healthy and $health_url to answer..."
tries=45          # x 2 s = 90 s, more than the compose start_period of any service
while :; do
    unhealthy=$(not_healthy "$ESSENTIAL_SERVICES")
    if [ -z "$unhealthy" ] && curl -fsS -m 5 -o /dev/null "$health_url" 2>/dev/null; then
        break
    fi
    tries=$((tries - 1))
    if [ "$tries" -le 0 ]; then
        echo "" >&2
        echo "✗ DEPLOY FAILED — production is DOWN after $(seconds_of \
            "$(( $(now_ms) - downtime_start_ms ))") and is not coming back:" >&2
        if [ -n "$unhealthy" ]; then
            echo "  containers not healthy:$unhealthy" >&2
            log_tails "$unhealthy" >&2
        else
            echo "  every essential container is up, but $health_url does not answer 200" >&2
            log_tails "$ESSENTIAL_SERVICES" >&2
        fi
        echo "" >&2
        echo "  Roll back: .claude/skills/deploy/SKILL.md §4. If zapzap-proxy sits in" >&2
        echo "  Created, \`docker start zapzap-proxy\` restores / and /api/ at once." >&2
        exit 1
    fi
    sleep 2
done
echo "✓ Site answering again — downtime was $(seconds_of "$(( $(now_ms) - downtime_start_ms ))")"
echo ""

# The site is up. Give the non-essential services their own, shorter grace period: they
# cost nothing while they start, and their failure is a warning, not an outage.
degraded=""
if [ -n "$optional_services" ]; then
    tries=30      # x 2 s = 60 s
    while :; do
        degraded=$(not_healthy "$optional_services")
        [ -z "$degraded" ] && break
        tries=$((tries - 1))
        [ "$tries" -le 0 ] && break
        sleep 2
    done
fi
if [ -n "$degraded" ]; then
    echo "⚠  WARNING — the site is up, but a non-essential service is not:$degraded" >&2
    echo "   Serving normally: $ESSENTIAL_SERVICES are healthy and $health_url" >&2
    echo "   answered 200, so \`/\` (the React client), \`/api/\` and \`/suscribeupdate\`" >&2
    echo "   are unaffected." >&2
    for entry in $degraded; do
        case "${entry%%(*}" in
            frontend-flutter)
                echo "   Cost: \`/app/\` — the Flutter PWA — answers 502 until that container is" >&2
                echo "   healthy. nginx resolves it per request (nginx/nginx.conf), which is why" >&2
                echo "   it cannot take the rest of the site with it." >&2 ;;
            *)
                echo "   Cost: whatever ${entry%%(*} serves. It is not on the path to \`/\` or" >&2
                echo "   \`/api/\`, so those keep working." >&2 ;;
        esac
    done
    log_tails "$degraded" >&2
    echo "" >&2
    echo "   Rolling back is OPTIONAL here (.claude/skills/deploy/SKILL.md §4): the site is" >&2
    echo "   serving, so fixing it in a new pull request and deploying again is usually" >&2
    echo "   better than a rollback. Do not read this as an outage." >&2
    echo "" >&2
fi

# Check status
echo "📊 Container status:"
docker-compose ps
echo ""

# Health check — already known to answer 200 by the loop above; this prints its body.
echo "🩺 API Health check ($health_url):"
curl -fsS -m 10 "$health_url" | jq . || echo "(could not print the health payload)"
echo ""

echo "======================================"
if [ -n "$degraded" ]; then
    echo "⚠  Deployed, DEGRADED:$degraded"
else
    echo "✨ Deployment complete!"
fi
echo "======================================"
echo ""
echo "📝 Useful commands:"
echo "  - View logs:        docker-compose logs -f"
echo "  - Backend logs:     docker-compose logs -f backend"
echo "  - Frontend logs:    docker-compose logs -f frontend"
echo "  - Stop:             docker-compose down --remove-orphans"
echo "  - Restart service:  docker-compose restart [service]"
echo ""

# Exit status, deliberately three-valued so a caller can tell the cases apart:
#   0  deployed, everything healthy
#   1  refused before touching anything, or an outage (see the message)
#   2  deployed and serving, but a non-essential service is not healthy
# Non-zero so no script can miss it; distinct so no script mistakes it for an outage.
[ -z "$degraded" ] || exit 2
