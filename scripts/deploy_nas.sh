#!/bin/bash

# ZapZap - build, push and deploy production to the NAS through the LAN registry.
#
# Usage: scripts/deploy_nas.sh                   build HEAD, push it, deploy it
#        scripts/deploy_nas.sh --rollback <sha>  redeploy the images of an earlier deploy
#
# Runs on the dev machine, from a clean checkout of the commit to deploy. It builds four
# images from HEAD — zapzap-backend (CARGO_FEATURES=bedrock), zapzap-frontend,
# zapzap-frontend-flutter and zapzap-proxy (nginx/Dockerfile) —, tags each <short sha> and
# latest, pushes them to $REGISTRY, writes docker-compose.prod.yml to
# $NAS_DEPLOY_DIR/compose.yaml with the registry and the sha written in, and has the NAS
# pull and start them. The NAS holds no clone and builds nothing.
#
# Configuration: scripts/deploy.env (gitignored; copy scripts/deploy.env.example), or the
# same variables in the environment: REGISTRY, NAS_SSH, NAS_DEPLOY_DIR, PUBLIC_URL, and
# VITE_GOOGLE_OAUTH_CLIENT_ID (else read from the repository's .env).
#
# The part that runs on the NAS is this same file, sent over ssh and run as
# `deploy_nas.sh --remote <check|deploy|rollback> <dir> [tag]`. Its order is what makes a
# failed deploy a no-op rather than an outage: every refusal and the `pull` happen while
# the old containers serve; only then the database backup, `down`, `up -d`, and a health
# wait that does not call a deploy done until the site answers.
#
# Exit status: 0 deployed, every container healthy; 1 refused (nothing stopped) or an
# outage (the message says which); 2 deployed and serving, but a non-essential service —
# frontend-flutter — is not healthy.
#
# Procedure and why: .claude/skills/deploy/SKILL.md, .llmwiki/Deployment.md
# Self-test: scripts/deploy_nas_selftest.sh

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Which services serve the site, and which one is the reverse proxy. Both are tied to two
# other files: `nginx` is the proxy service of docker-compose.prod.yml, whose published port
# the health wait asks for and whose health decides the site; `backend` and `frontend` are
# its `depends_on: condition: service_healthy` entries, what nginx/nginx.conf proxies `/`,
# `/api/` and `/suscribeupdate` to. Everything else is NOT essential, deliberately:
# nginx resolves `frontend-flutter` per request, so an unhealthy PWA costs `/app/` a 502
# and nothing else (#36). Renaming or adding a service means changing
# docker-compose.prod.yml, nginx/nginx.conf and this line together.
PROXY_SERVICE=nginx
ESSENTIAL_SERVICES="backend frontend $PROXY_SERVICE"

# The images, by compose service: <service>:<image name>:<build context>
IMAGES="backend:zapzap-backend:zapzap-rust frontend:zapzap-frontend:frontend frontend-flutter:zapzap-frontend-flutter:frontend-flutter nginx:zapzap-proxy:nginx"

# The uid the backend image runs as (zapzap-rust/Dockerfile). DEPLOY_DATA_UID exists for
# the self-test only, whose sandbox files belong to whoever runs it.
DATA_UID="${DEPLOY_DATA_UID:-1000}"

die() { printf '%s\n' "$@" >&2; exit 1; }

# ================================================================ on the NAS

# Milliseconds since the epoch, so the reported downtime does not truncate to seconds.
now_ms() {
    local t
    if [ -n "${EPOCHREALTIME:-}" ]; then
        t=${EPOCHREALTIME/,/.}
        printf '%s%s\n' "${t%%.*}" "$(printf '%s' "${t#*.}000" | cut -c1-3)"
        return 0
    fi
    t=$(date +%s%3N 2>/dev/null || true)
    case "$t" in
        ''|*[!0-9]*) printf '%s000\n' "$(date +%s)" ;;
        *) printf '%s\n' "$t" ;;
    esac
}

seconds_of() { printf '%d.%ds' "$(( $1 / 1000 ))" "$(( ($1 % 1000) / 100 ))"; }

is_essential() { case " $ESSENTIAL_SERVICES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

dc() { docker-compose -f compose.yaml "$@"; }

# Echoes "<service>(<state>)" for every service of $1 that is not healthy or running.
not_healthy() {
    local service cid state out=""
    for service in $1; do
        cid=$(dc ps -q "$service" 2>/dev/null | head -1)
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

log_tails() {
    local entry service
    for entry in $1; do
        service=${entry%%(*}
        echo ""
        echo "  --- last 30 lines of $service ---"
        dc logs --tail 30 "$service" 2>/dev/null || true
    done
}

# What every mode checks first, before anything is pulled, built or stopped.
remote_preflight() {
    [ -f .env ] || die "✗ REFUSING TO DEPLOY: $PWD/.env is missing." \
        "  It holds the production secrets (JWT_SECRET, Google, AWS) and is placed there by" \
        "  hand, never by this script: .claude/skills/deploy/SKILL.md, first deploy."
    [ -f data/zapzap.db ] || die "✗ REFUSING TO DEPLOY: $PWD/data/zapzap.db is missing." \
        "  The backend would start on an empty database, which reads as every account lost." \
        "  Copy the production database there first (.claude/skills/deploy/SKILL.md)."
    local wrong
    wrong=$(find data -maxdepth 2 \( -path data -o -name 'zapzap.db*' -o -path 'data/bot-strategies*' \) \
        ! -name '*.bak-*' ! -uid "$DATA_UID" 2>&1)
    if [ -n "$wrong" ]; then
        printf '%s\n' "✗ REFUSING TO DEPLOY: not owned by uid $DATA_UID, the user the backend runs as:" >&2
        printf '%s\n' "$wrong" | sed 's/^/    /' >&2
        die "  SQLite would fail to write the database or its journal, or the LLM bots their" \
            "  memory. Nothing was pulled or stopped. Fix it (a container can chown, you cannot):" \
            "    docker run --rm -v \"$PWD/data:/data\" alpine sh -c \\" \
            "      \"chown $DATA_UID:$DATA_UID /data && chown -R $DATA_UID:$DATA_UID /data/bot-strategies /data/zapzap.db*\""
    fi
    command -v docker-compose >/dev/null 2>&1 || die "✗ REFUSING TO DEPLOY: docker-compose is not on PATH."
}

remote() {  # mode, deploy dir, [tag]
    local mode="$1" dir="$2" tag="${3:-}"
    export PATH="$PATH:/usr/local/bin"
    # The project the clone ran as (its directory was named zapzap): the first deploy from
    # the deploy directory then replaces those containers instead of clashing with them.
    export COMPOSE_PROJECT_NAME=zapzap
    cd "$dir" 2>/dev/null || die "✗ REFUSING TO DEPLOY: no deploy directory $dir on the NAS."

    remote_preflight
    if [ "$mode" = check ]; then
        echo "✓ NAS ready: $dir has .env and data/zapzap.db, owned by uid $DATA_UID"
        return 0
    fi

    # compose.yaml.next is what is about to run; compose.yaml stays what runs now until
    # the pull has succeeded.
    if [ "$mode" = rollback ]; then
        [ -f compose.yaml ] || die "✗ REFUSING TO ROLL BACK: no compose.yaml in $dir — nothing was ever deployed here."
        sed -E "s#^([[:space:]]*image:[[:space:]]*[^[:space:]]*/zapzap-[a-z-]+):[^[:space:]]+[[:space:]]*\$#\\1:$tag#" \
            compose.yaml > compose.yaml.next
    fi
    [ -f compose.yaml.next ] || die "✗ REFUSING TO DEPLOY: no compose.yaml.next in $dir."
    local pinned
    pinned=$(grep -cE "^[[:space:]]*image:[[:space:]]*[^[:space:]]*/zapzap-[a-z-]+:$tag[[:space:]]*\$" compose.yaml.next)
    if [ "$pinned" -eq 0 ] || grep -E '^[[:space:]]*image:' compose.yaml.next | grep -vqE ":$tag[[:space:]]*\$"; then
        rm -f compose.yaml.next
        die "✗ REFUSING TO DEPLOY: not every image of the compose file is pinned to $tag." \
            "  Nothing was pulled or stopped."
    fi

    # A compose file docker-compose cannot read — a .env without JWT_SECRET, which the Rust
    # backend has no default for — or one missing an essential service is refused here.
    local declared service
    if ! declared=$(docker-compose -f compose.yaml.next config --services); then
        rm -f compose.yaml.next
        die "" "✗ REFUSING TO DEPLOY: docker-compose cannot read the compose file — its reason is above." \
            "  Nothing was pulled or stopped. The usual cause: a variable the compose file" \
            "  requires is missing from .env — JWT_SECRET. Fix .env (never print it), then retry."
    fi
    for service in $ESSENTIAL_SERVICES; do
        case " $(printf '%s\n' "$declared" | tr '\n' ' ') " in
            *" $service "*) ;;
            *)
                rm -f compose.yaml.next
                printf '%s\n' "" "✗ REFUSING TO DEPLOY: deploy_nas.sh expects a service named '$service'," \
                    "  which this compose file does not declare. It declares:" >&2
                printf '%s\n' "$declared" | sed 's/^/    /' >&2
                die "  Nothing was pulled or stopped. ESSENTIAL_SERVICES and PROXY_SERVICE in" \
                    "  scripts/deploy_nas.sh, docker-compose.prod.yml and nginx/nginx.conf" \
                    "  have to be changed together." ;;
        esac
    done

    echo "📥 Pulling the $tag images (production is still serving the old ones)..."
    if ! docker-compose -f compose.yaml.next pull; then
        rm -f compose.yaml.next
        die "" "✗ PULL FAILED — nothing was stopped; production still serves what it served." \
            "  compose.yaml is unchanged. Usual causes: the tag $tag was never pushed (a rollback" \
            "  to a commit no deploy built), the NAS is not logged in to the registry" \
            "  (\`docker login\`), or the registry is not in its insecure-registries."
    fi
    echo "✓ Images pulled"

    local backup
    backup="data/zapzap.db.bak-$(date +%F-%H%M)"
    echo "💾 Backing up the database to $backup..."
    if ! cp -p data/zapzap.db "$backup" || ! cmp -s data/zapzap.db "$backup"; then
        rm -f compose.yaml.next
        die "✗ BACKUP FAILED — nothing was stopped. Free space on the NAS (df -h $dir), then retry."
    fi
    echo "✓ Database backed up"

    local previous=""
    if [ -f compose.yaml ]; then
        previous=$(sed -nE 's#^[[:space:]]*image:[[:space:]]*[^[:space:]]*/zapzap-backend:([^[:space:]]+).*#\1#p' compose.yaml | head -1)
        mv -f compose.yaml compose.yaml.prev
    fi
    mv -f compose.yaml.next compose.yaml
    echo "📝 compose.yaml now pins $tag${previous:+ (it pinned $previous: the rollback target)}"
    echo ""

    # The downtime starts here and ends when the site answers again. --remove-orphans: a
    # container the compose file no longer declares otherwise survives the `down`, which
    # then fails to remove the network; docker-compose v1 only warns about it.
    echo "🛑 Stopping containers (downtime starts now)..."
    local downtime_start_ms
    downtime_start_ms=$(now_ms)
    if ! dc down --remove-orphans; then
        echo "" >&2
        echo "✗ \`docker-compose down\` FAILED — the stack may be half stopped, so" >&2
        echo "  production may be DOWN. Trying to start it again immediately..." >&2
        dc up -d >&2 || true
        die "" "  Check what is running (\`docker ps -a\`) before anything else. A \`down\` that" \
            "  fails on \"network has active endpoints\" usually leaves a container the compose" \
            "  file no longer declares: \`docker rm -f <name>\`, then deploy again. Otherwise" \
            "  roll back: .claude/skills/deploy/SKILL.md §4."
    fi
    echo "✓ Containers stopped"

    echo "🚀 Starting containers..."
    if ! dc up -d; then
        die "" "✗ START FAILED — production is DOWN. Act now:" \
            "  - \`docker ps -a\`: if zapzap-proxy sits in Created, \`docker start zapzap-proxy\`" \
            "    restores / and /api/ at once." \
            "  - Otherwise roll back: .claude/skills/deploy/SKILL.md §4."
    fi
    echo "✓ Containers started"
    echo ""

    # `up -d` returning 0 means the containers were created, not that anything works: a
    # container crash-looping under `restart: unless-stopped` satisfies it. Poll the real
    # state, and split the verdict: an essential service, or /api/health, is an outage
    # (exit 1); any other service is a degraded deploy (exit 2), never "production is DOWN".
    local proxy_port health_url optional_services unhealthy degraded="" tries entry
    proxy_port=$(dc port "$PROXY_SERVICE" 80 2>/dev/null | sed 's/.*://' || true)
    case "$proxy_port" in ''|*[!0-9]*) proxy_port=80 ;; esac
    health_url="http://localhost:$proxy_port/api/health"
    optional_services=$(dc config --services | while read -r s; do
        is_essential "$s" || printf '%s ' "$s"
    done)

    echo "⏳ Waiting for $ESSENTIAL_SERVICES to be healthy and $health_url to answer..."
    tries=45          # x 2 s = 90 s, more than the start_period of any service
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
            die "" "  Roll back: scripts/deploy_nas.sh --rollback ${previous:-<previous sha>}" \
                "  (.claude/skills/deploy/SKILL.md §4). If zapzap-proxy sits in Created," \
                "  \`docker start zapzap-proxy\` restores / and /api/ at once."
        fi
        sleep 2
    done
    echo "✓ Site answering again — downtime was $(seconds_of "$(( $(now_ms) - downtime_start_ms ))")"
    echo ""

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

    echo "📊 Container status:"
    dc ps
    echo ""
    echo "🩺 API health ($health_url):"
    curl -fsS -m 10 "$health_url" | jq . || echo "(could not print the health payload)"
    echo ""
    if [ -n "$degraded" ]; then
        echo "⚠  Deployed $tag, DEGRADED:$degraded"
        return 2
    fi
    echo "✨ Deployed $tag"
    return 0
}

if [ "${1:-}" = --remote ]; then
    remote "${2:?mode}" "${3:?deploy dir}" "${4:-}"
    exit $?
fi

# ================================================================ on the dev machine

usage() { sed -n '3,5p' "$SELF" | sed 's/^# \{0,1\}//'; }

rollback=""
case "${1:-}" in
    "") ;;
    --rollback)
        [ -n "${2:-}" ] || { usage >&2; die "✗ --rollback needs the sha of an earlier deploy."; }
        rollback="$2" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "✗ Unknown argument: $1" ;;
esac

REPO="$(cd "$(dirname "$SELF")/.." && pwd)"
cd "$REPO" || exit 1

CONFIG="$REPO/scripts/deploy.env"
if [ -f "$CONFIG" ]; then
    # The environment wins over the file: remember what is set before sourcing it.
    declare -A preset=()
    for v in REGISTRY NAS_SSH NAS_DEPLOY_DIR PUBLIC_URL VITE_GOOGLE_OAUTH_CLIENT_ID; do
        [ -n "${!v+x}" ] && preset[$v]="${!v}"
    done
    # shellcheck source=/dev/null
    . "$CONFIG"
    for v in "${!preset[@]}"; do printf -v "$v" '%s' "${preset[$v]}"; done
fi

# Fail by name rather than deploy somewhere unintended.
for v in REGISTRY NAS_SSH NAS_DEPLOY_DIR; do
    [ -n "${!v:-}" ] || die "✗ $v is not set: set it in scripts/deploy.env (copy scripts/deploy.env.example)" \
        "  or in the environment. Nothing was built."
done
# They are written into remote commands and sed expressions: plain values only.
[[ "$REGISTRY" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || die "✗ REGISTRY must be host[:port], got: $REGISTRY"
[[ "$NAS_SSH" =~ ^[A-Za-z0-9._@-]+$ ]] || die "✗ NAS_SSH must be user@host or an ssh alias, got: $NAS_SSH"
[[ "$NAS_DEPLOY_DIR" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "✗ NAS_DEPLOY_DIR must be an absolute path, got: $NAS_DEPLOY_DIR"
PUBLIC_URL="${PUBLIC_URL:-https://zapzap.ombivince.synology.me}"

# Runs this file on the NAS: copied whole to a temporary file first, so nothing the remote
# side starts can read the rest of the script from stdin.
on_nas() {  # mode, [tag]
    ssh "$NAS_SSH" "f=\$(mktemp) && cat > \"\$f\" && bash \"\$f\" --remote $1 $NAS_DEPLOY_DIR ${2:-}; rc=\$?; rm -f \"\$f\"; exit \$rc" < "$SELF"
}

# The short sha is the tag, computed one way for a deploy and a rollback alike.
short_sha() { git rev-parse --short=7 "$1^{commit}" 2>/dev/null; }

finish() {  # exit status of the remote deploy
    case "$1" in
        0|2) echo ""
             echo "Checks: .claude/skills/deploy/SKILL.md §3, against $PUBLIC_URL" ;;
        255) echo "✗ ssh to $NAS_SSH failed mid-deploy: what production runs is unknown." >&2
             echo "  Look before anything else: ssh $NAS_SSH 'docker ps -a'" >&2
             exit 1 ;;
    esac
    exit "$1"
}

if [ -n "$rollback" ]; then
    [[ "$rollback" =~ ^[0-9a-f]{7,40}$ ]] || die "✗ --rollback wants a commit sha (hex), got: $rollback"
    tag=$(short_sha "$rollback") || die "✗ $rollback is no commit of this repository." \
        "  \`git fetch origin\`, or check the sha: \`ssh $NAS_SSH cat $NAS_DEPLOY_DIR/compose.yaml.prev\`" \
        "  names the images of the deploy before the current one."
    echo "⏪ Rolling production back to $tag (images $REGISTRY/zapzap-*:$tag)"
    on_nas rollback "$tag"
    finish $?
fi

# A deploy is of HEAD, exactly: a modified tracked file anywhere, or an untracked one in a
# build context, would ship code that no commit holds.
dirty=$(git status --porcelain --untracked-files=no)
dirty="$dirty$(git status --porcelain -- zapzap-rust frontend frontend-flutter nginx docker-compose.prod.yml | grep '^??')"
if [ -n "$dirty" ]; then
    printf '%s\n' "✗ REFUSING TO DEPLOY: the working tree is not clean, so the images would not be HEAD's:" >&2
    printf '%s\n' "$dirty" | sed 's/^/    /' >&2
    die "  Nothing was built. Deploy from a clean checkout of the merged commit" \
        "  (git switch master && git pull --ff-only)."
fi

if [ -z "${VITE_GOOGLE_OAUTH_CLIENT_ID:-}" ] && [ -f "$REPO/.env" ]; then
    VITE_GOOGLE_OAUTH_CLIENT_ID=$(sed -nE 's/^VITE_GOOGLE_OAUTH_CLIENT_ID=["'\'']?([^"'\'']*)["'\'']?[[:space:]]*$/\1/p' "$REPO/.env" | tail -1)
fi
[ -n "${VITE_GOOGLE_OAUTH_CLIENT_ID:-}" ] || die "✗ VITE_GOOGLE_OAUTH_CLIENT_ID is not set: the React and Flutter images would" \
    "  have no Google sign-in. Set it in scripts/deploy.env or the repository's .env. Nothing was built."

tag=$(short_sha HEAD) || die "✗ cannot read HEAD."
revision=$(git rev-parse HEAD)
echo "======================================"
echo "🃏 ZapZap deploy of $tag to $NAS_SSH:$NAS_DEPLOY_DIR"
echo "======================================"

echo "🔎 Checking the NAS before building..."
on_nas check || die "✗ The NAS is not ready (above). Nothing was built."

for entry in $IMAGES; do
    image="${entry#*:}"; context="${image#*:}"; image="${image%%:*}"
    args=()
    case "$image" in
        zapzap-backend) args=(--build-arg CARGO_FEATURES=bedrock) ;;
        zapzap-frontend) args=(--build-arg "VITE_GOOGLE_OAUTH_CLIENT_ID=$VITE_GOOGLE_OAUTH_CLIENT_ID") ;;
        zapzap-frontend-flutter) args=(--build-arg "GOOGLE_CLIENT_ID=$VITE_GOOGLE_OAUTH_CLIENT_ID") ;;
    esac
    echo "🔨 Building $REGISTRY/$image:$tag from $context/"
    docker build "${args[@]}" \
        --label "org.opencontainers.image.revision=$revision" \
        -t "$REGISTRY/$image:$tag" -t "$REGISTRY/$image:latest" "$context" \
        || die "✗ BUILD FAILED ($image) — nothing was pushed and production was not touched."
done

for entry in $IMAGES; do
    image="${entry#*:}"; image="${image%%:*}"
    for t in "$tag" latest; do
        docker push "$REGISTRY/$image:$t" \
            || die "✗ PUSH FAILED ($REGISTRY/$image:$t) — production was not touched." \
                   "  Logged in? \`docker login $REGISTRY\`. Then run this script again."
    done
done
echo "✓ Images pushed"

# The registry and the tag are written in, so compose.yaml on the NAS names what runs.
echo "📤 Writing $NAS_DEPLOY_DIR/compose.yaml.next on the NAS"
sed -e "s#\${ZAPZAP_REGISTRY:-192.168.1.25:5050}#$REGISTRY#g" -e "s#\${ZAPZAP_TAG:-latest}#$tag#g" \
    docker-compose.prod.yml | ssh "$NAS_SSH" "cat > $NAS_DEPLOY_DIR/compose.yaml.next" \
    || die "✗ Could not write compose.yaml.next on the NAS — production was not touched."

on_nas deploy "$tag"
finish $?
