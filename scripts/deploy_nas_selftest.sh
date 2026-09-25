#!/bin/bash

# ZapZap - self-test of scripts/deploy_nas.sh, offline, in seconds.
#
# The deploy is the production path: the order of its steps is what makes a failed deploy
# a no-op instead of an outage, and only a sandbox can assert it. A sandbox git repository
# holds a copy of the script and of docker-compose.prod.yml; `ssh` is a stub that runs the
# remote command locally, so the NAS half of the script really runs, in a sandbox deploy
# directory, against stubbed `docker`, `docker-compose`, `curl`, `jq` and `sleep` that log
# their arguments. The logs' order is the assertion.
#
# Usage: scripts/deploy_nas_selftest.sh     (exit 0 = every case behaves; the hooks CI job)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

pass=0
fail=0
report() {  # description, expected, actual
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf '  FAIL  %s\n        expected %s, got %s\n' "$1" "$2" "$3"
    fi
}
has() {  # description, needle -- in $out
    case "$out" in *"$2"*) report "$1" yes yes ;; *) report "$1" "output containing '$2'" "$(printf '%s' "$out" | tail -5)" ;; esac
}
hasnt() {
    case "$out" in *"$2"*) report "$1" "no '$2'" "it was printed" ;; *) report "$1" yes yes ;; esac
}

REPO="$SANDBOX/repo"         # the dev machine's checkout
NAS="$SANDBOX/nas/zapzap"    # the deploy directory
TOOLS="$SANDBOX/tools"
LOG="$SANDBOX/calls.log"     # every docker, docker-compose and ssh call, in order
STATES="$SANDBOX/states"     # one file per service, holding its container state
SERVICES="$SANDBOX/services" # what `docker-compose config --services` answers
FAILS="$SANDBOX/fails"       # one file per failing step: build, push, pull, down, up, config
mkdir -p "$REPO/scripts" "$REPO/zapzap-rust" "$REPO/frontend" "$REPO/frontend-flutter" "$REPO/nginx" \
    "$NAS/data" "$TOOLS" "$STATES" "$FAILS"

cp "$ROOT/scripts/deploy_nas.sh" "$REPO/scripts/"
cp "$ROOT/docker-compose.prod.yml" "$REPO/"
for d in zapzap-rust frontend frontend-flutter nginx; do echo "FROM scratch" > "$REPO/$d/Dockerfile"; done
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
git -C "$REPO" add -A
git -C "$REPO" commit -qm first
FIRST=$(git -C "$REPO" rev-parse --short=7 HEAD)
git -C "$REPO" commit -q --allow-empty -m second
SECOND=$(git -C "$REPO" rev-parse --short=7 HEAD)

echo "JWT_SECRET=not-a-real-one" > "$NAS/.env"
echo "the players" > "$NAS/data/zapzap.db"

# ssh <host> <command>: the command runs here, stdin passed through.
cat > "$TOOLS/ssh" <<EOF
#!/bin/sh
echo "ssh \$1" >> "$LOG"
shift
exec bash -c "\$*"
EOF
cat > "$TOOLS/docker" <<EOF
#!/bin/sh
case "\$1" in
    build|push)
        echo "docker \$*" >> "$LOG"
        [ -f "$FAILS/\$1" ] && exit 1 ;;
    inspect)
        for a in "\$@"; do last=\$a; done
        svc=\${last#cid-}
        if [ -f "$STATES/\$svc" ]; then cat "$STATES/\$svc"; else echo healthy; fi ;;
esac
exit 0
EOF
cat > "$TOOLS/docker-compose" <<EOF
#!/bin/sh
[ "\$1" = -f ] && { file=\$2; shift 2; }
case "\$1" in
    pull|down|up) echo "compose[\$file] \$*" >> "$LOG"
                  [ -f "$FAILS/\$1" ] && exit 1 ;;
    config)
        if [ -f "$FAILS/config" ]; then
            echo 'Missing mandatory value for "environment" option: JWT_SECRET must be set' >&2
            exit 1
        fi
        cat "$SERVICES" ;;
    port) echo 0.0.0.0:80 ;;
    ps)   [ "\$2" = -q ] && echo "cid-\$3" ;;
esac
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' > "$TOOLS/sleep"
printf '#!/bin/sh\ncat >/dev/null 2>&1 || true\nexit 0\n' > "$TOOLS/jq"
chmod +x "$TOOLS"/*

services() { printf '%s\n' "$@" > "$SERVICES"; }
unhealthy() { rm -f "$STATES"/*; [ $# -eq 0 ] || echo "$2" > "$STATES/$1"; }
site() { printf '#!/bin/sh\nexit %s\n' "$1" > "$TOOLS/curl"; chmod +x "$TOOLS/curl"; }
failing() { rm -f "$FAILS"/*; for s in "$@"; do touch "$FAILS/$s"; done; }
reset() { services backend frontend nginx frontend-flutter; unhealthy; site 0; failing; }

# Runs the script with a clean environment of its own: the configuration comes only from
# the variables given (NAME=value ...), never from the caller's deploy.env or shell.
run() {  # [NAME=value ...] [-- script arguments]
    local vars=() args=()
    while [ $# -gt 0 ]; do
        if [ "$1" = -- ]; then shift; args=("$@"); break; fi
        vars+=("$1"); shift
    done
    : > "$LOG"
    out=$(cd "$REPO" && env -u REGISTRY -u NAS_SSH -u NAS_DEPLOY_DIR -u PUBLIC_URL \
        -u VITE_GOOGLE_OAUTH_CLIENT_ID PATH="$TOOLS:$PATH" DEPLOY_DATA_UID="$(id -u)" \
        "${vars[@]}" scripts/deploy_nas.sh "${args[@]}" 2>&1)
    return $?
}
CONF=(REGISTRY=reg.test:5050 NAS_SSH=nas NAS_DEPLOY_DIR="$NAS" VITE_GOOGLE_OAUTH_CLIENT_ID=client-id)
deploy() { run "${CONF[@]}" "$@"; }
# The steps that change what is running, as "pull|down --remove-orphans|up -d".
steps() { sed -nE 's/^compose\[[^]]*\] (pull|down.*|up.*)$/\1/p' "$LOG" | tr '\n' '|' | sed 's/|$//'; }
builds() { grep -c '^docker build' "$LOG"; }
pushes() { grep -c '^docker push' "$LOG"; }
image_tags() { sed -nE 's#^[[:space:]]*image:[[:space:]]*(.*)$#\1#p' "$NAS/compose.yaml" | tr '\n' ' ' | sed 's/ $//'; }
backups() { find "$NAS/data" -name 'zapzap.db.bak-*' | wc -l | tr -d ' '; }

reset

echo "== configuration =============================================="
for v in REGISTRY NAS_SSH NAS_DEPLOY_DIR; do
    conf=()
    for c in "${CONF[@]}"; do [ "${c%%=*}" = "$v" ] || conf+=("$c"); done
    run "${conf[@]}"; rc=$?
    report "a missing $v is refused"                1 "$rc"
    has "and the refusal names $v"                  "$v is not set"
    report "and nothing is built without $v"        "" "$(cat "$LOG")"
done
run "${CONF[@]/#REGISTRY=*/REGISTRY=reg.test:5050;rm -rf}"; rc=$?
report "a REGISTRY that is not host:port is refused" 1 "$rc"
printf 'REGISTRY=from-file:5050\nNAS_SSH=nas\nNAS_DEPLOY_DIR=%s\n' "$NAS" > "$REPO/scripts/deploy.env"
run VITE_GOOGLE_OAUTH_CLIENT_ID=client-id; rc=$?
report "scripts/deploy.env provides the configuration" 0 "$rc"
report "and its REGISTRY names the images"      1 "$(grep -c 'from-file:5050/zapzap-backend:' "$NAS/compose.yaml")"
run REGISTRY=from-env:5050 VITE_GOOGLE_OAUTH_CLIENT_ID=client-id; rc=$?
report "the environment wins over scripts/deploy.env" 1 "$(grep -c 'from-env:5050/zapzap-backend:' "$NAS/compose.yaml")"
rm -f "$REPO/scripts/deploy.env"
run "${CONF[@]:0:3}"; rc=$?
report "no Google client id is refused"         1 "$rc"
has "naming VITE_GOOGLE_OAUTH_CLIENT_ID"        "VITE_GOOGLE_OAUTH_CLIENT_ID is not set"
report "before anything is built"               0 "$(builds)"
echo "VITE_GOOGLE_OAUTH_CLIENT_ID='from-dotenv'" > "$REPO/.env"   # gitignored in the real repo
git -C "$REPO" update-index -q --refresh
printf '.env\n' > "$REPO/.git/info/exclude"
run "${CONF[@]:0:3}"; rc=$?
report "the client id is read from the repository's .env" 0 "$rc"
report "and passed to the React and Flutter builds" 2 "$(grep -cE 'GOOGLE(_OAUTH)?_CLIENT_ID=from-dotenv ' "$LOG")"
rm -f "$REPO/.env"

echo "== clean tree ================================================="
echo "edited" >> "$REPO/docker-compose.prod.yml"
deploy; rc=$?
report "a modified tracked file is refused"     1 "$rc"
has "naming the file"                           "docker-compose.prod.yml"
report "before anything is built, pushed or sent" "" "$(cat "$LOG")"
git -C "$REPO" checkout -q docker-compose.prod.yml
echo "stray" > "$REPO/frontend/untracked.js"
deploy; rc=$?
report "an untracked file in a build context is refused" 1 "$rc"
report "and nothing is built"                   "" "$(cat "$LOG")"
rm -f "$REPO/frontend/untracked.js"
echo "notes" > "$REPO/notes.txt"
deploy; rc=$?
report "an untracked file outside the build contexts is not" 0 "$rc"
rm -f "$REPO/notes.txt"

echo "== deploy ====================================================="
rm -f "$NAS"/compose.yaml*
find "$NAS/data" -name '*.bak-*' -delete
deploy; rc=$?
report "the happy path exits 0"                 0 "$rc"
report "builds the four images"                 4 "$(builds)"
report "the backend with the bedrock feature"   1 "$(grep -c "^docker build --build-arg CARGO_FEATURES=bedrock .*-t reg.test:5050/zapzap-backend:$SECOND -t reg.test:5050/zapzap-backend:latest zapzap-rust$" "$LOG")"
report "the proxy from nginx/"                  1 "$(grep -c "^docker build .*-t reg.test:5050/zapzap-proxy:$SECOND .* nginx$" "$LOG")"
report "pushes each as <sha> and latest"        8 "$(pushes)"
report "the NAS compose pins every image to the sha" \
    "reg.test:5050/zapzap-backend:$SECOND reg.test:5050/zapzap-frontend:$SECOND reg.test:5050/zapzap-frontend-flutter:$SECOND reg.test:5050/zapzap-proxy:$SECOND" \
    "$(image_tags)"
report "pulls before it stops anything"         "pull|down --remove-orphans|up -d" "$(steps)"
report "pulls with the new file, before it replaces compose.yaml" 1 "$(grep -c '^compose\[compose.yaml.next\] pull' "$LOG")"
report "backs the database up"                  1 "$(backups)"
report "a byte-for-byte copy"                   same "$(cmp -s "$NAS/data/zapzap.db" "$(find "$NAS/data" -name 'zapzap.db.bak-*' | head -1)" && echo same || echo differs)"
has "prints the downtime it caused"             "downtime was "
has "and a success banner"                      "✨ Deployed $SECOND"
report "the NAS check runs before the first build" "ssh nas" "$(head -1 "$LOG")"

echo "== failures before the stop ==================================="
before=$(cat "$NAS/compose.yaml")
git -C "$REPO" commit -q --allow-empty -m third
failing build
deploy; rc=$?
report "a failed build exits 1"                 1 "$rc"
report "and pushes nothing"                     0 "$(pushes)"
report "and touches no container"               "" "$(steps)"
report "and leaves compose.yaml alone"          "$before" "$(cat "$NAS/compose.yaml")"
failing push
deploy; rc=$?
report "a failed push exits 1"                  1 "$rc"
report "and touches no container"               "" "$(steps)"
has "naming docker login"                       "docker login"
failing pull
deploy; rc=$?
report "a failed pull exits 1"                  1 "$rc"
report "and stops nothing"                      "pull" "$(steps)"
report "and leaves compose.yaml alone"          "$before" "$(cat "$NAS/compose.yaml")"
report "and leaves no compose.yaml.next"        gone "$([ -e "$NAS/compose.yaml.next" ] && echo kept || echo gone)"
has "saying nothing was stopped"                "nothing was stopped"
failing config
deploy; rc=$?
report "a compose file docker-compose cannot read is refused" 1 "$rc"
report "before the pull"                        "" "$(steps)"
has "printing compose's reason"                 "JWT_SECRET must be set"
failing
services backend nginx frontend-flutter
deploy; rc=$?
report "a compose file missing an essential service is refused" 1 "$rc"
report "before the pull"                        "" "$(steps)"
has "naming the service"                        "expects a service named 'frontend'"
services backend frontend nginx frontend-flutter
mv "$NAS/.env" "$NAS/.env.away"
deploy; rc=$?
report "a deploy directory without .env is refused" 1 "$rc"
report "before anything is built"               0 "$(builds)"
mv "$NAS/.env.away" "$NAS/.env"
mv "$NAS/data/zapzap.db" "$NAS/data/zapzap.db.away"
deploy; rc=$?
report "a deploy directory without the database is refused" 1 "$rc"
report "before anything is built"               0 "$(builds)"
mv "$NAS/data/zapzap.db.away" "$NAS/data/zapzap.db"
deploy DEPLOY_DATA_UID=4242; rc=$?
report "data/ not owned by the backend's uid is refused" 1 "$rc"
has "naming the fix"                            "chown 4242:4242"
report "before anything is built"               0 "$(builds)"

echo "== health ====================================================="
failing
deploy; rc=$?
report "a deploy after the failures works"      0 "$rc"
THIRD=$(git -C "$REPO" rev-parse --short=7 HEAD)
failing down
deploy; rc=$?
report "a failing down exits 1"                 1 "$rc"
report "and tries to start the stack again"     "pull|down --remove-orphans|up -d" "$(steps)"
has "saying production may be down"             "may be DOWN"
failing up
deploy; rc=$?
report "a failing up exits 1"                   1 "$rc"
has "saying production is down"                 "production is DOWN"
failing
unhealthy backend restarting
deploy; rc=$?
report "an unhealthy backend is an outage: exit 1" 1 "$rc"
has "naming the container and its state"        "backend(restarting)"
has "with its logs"                             "last 30 lines of backend"
has "calling it an outage"                      "production is DOWN"
has "and naming the rollback command"           "deploy_nas.sh --rollback $THIRD"
unhealthy frontend-flutter unhealthy
deploy; rc=$?
report "an unhealthy PWA is not an outage: exit 2" 2 "$rc"
hasnt "never saying production is down"         "production is DOWN"
has "naming it in a warning"                    "frontend-flutter(unhealthy)"
has "saying what it costs"                      "answers 502"
has "and that a rollback is optional"           "Rolling back is OPTIONAL"
has "with a banner that is not a success"       "DEGRADED"
unhealthy
site 7
deploy; rc=$?
report "a silent /api/health is an outage: exit 1" 1 "$rc"
has "saying so"                                 "does not answer 200"
site 0

echo "== rollback ==================================================="
deploy; rc=$?
report "a deploy to roll back from"             0 "$rc"
: > "$REPO/zapzap-rust/dirty.rs"                 # a rollback builds nothing: a dirty tree is fine
run "${CONF[@]}" -- --rollback "$FIRST"; rc=$?
report "--rollback exits 0 when healthy"        0 "$rc"
report "and builds and pushes nothing"          0 "$(( $(builds) + $(pushes) ))"
report "pins every image of the deployed compose to the sha" \
    "reg.test:5050/zapzap-backend:$FIRST reg.test:5050/zapzap-frontend:$FIRST reg.test:5050/zapzap-frontend-flutter:$FIRST reg.test:5050/zapzap-proxy:$FIRST" \
    "$(image_tags)"
report "keeps the rest of the compose file"      "$(grep -vc 'image:' "$NAS/compose.yaml.prev")" "$(grep -vc 'image:' "$NAS/compose.yaml")"
report "pulls, then down, then up"              "pull|down --remove-orphans|up -d" "$(steps)"
has "and waits for the site"                    "downtime was "
rm -f "$REPO/zapzap-rust/dirty.rs"
run "${CONF[@]}" -- --rollback "$(git -C "$REPO" rev-parse HEAD)"; rc=$?
report "a full sha is shortened to the tag"     "$THIRD" "$(sed -nE 's#.*/zapzap-backend:(.*)#\1#p' "$NAS/compose.yaml")"
unhealthy backend unhealthy
run "${CONF[@]}" -- --rollback "$FIRST"; rc=$?
report "a rollback gets the same health wait: exit 1" 1 "$rc"
has "naming the container"                      "backend(unhealthy)"
unhealthy
before=$(cat "$NAS/compose.yaml")
failing pull
run "${CONF[@]}" -- --rollback "$SECOND"; rc=$?
report "a rollback to a tag the registry lacks exits 1" 1 "$rc"
report "and stops nothing"                      "pull" "$(steps)"
report "and leaves compose.yaml alone"          "$before" "$(cat "$NAS/compose.yaml")"
failing
run "${CONF[@]}" -- --rollback 'abc1234;rm'; rc=$?
report "a rollback target that is not a sha is refused" 1 "$rc"
report "without reaching the NAS"               "" "$(cat "$LOG")"
run "${CONF[@]}" -- --rollback deadbee; rc=$?
report "a sha this repository does not know is refused" 1 "$rc"
report "without reaching the NAS either"        "" "$(cat "$LOG")"
run "${CONF[@]}" -- --rollback; rc=$?
report "--rollback without a sha is refused"    1 "$rc"
run "${CONF[@]}" -- --bogus; rc=$?
report "an unknown argument is refused"         1 "$rc"

echo "== wiring ====================================================="
report "deploy_nas.sh is executable"            yes "$([ -x "$ROOT/scripts/deploy_nas.sh" ] && echo yes || echo no)"
report "docker-compose.prod.yml builds nothing" 0 "$(grep -cE '^[[:space:]]+build:' "$ROOT/docker-compose.prod.yml")"
report "every service runs a zapzap registry image" \
    "$(grep -cE '^  [a-z-]+:$' <(sed -n '/^services:/,/^networks:/p' "$ROOT/docker-compose.prod.yml"))" \
    "$(grep -cE '^    image: \$\{ZAPZAP_REGISTRY:-192\.168\.1\.25:5050\}/zapzap-[a-z-]+:\$\{ZAPZAP_TAG:-latest\}$' "$ROOT/docker-compose.prod.yml")"
for s in $(sed -nE 's/^ESSENTIAL_SERVICES="(.*)"$/\1/p' "$ROOT/scripts/deploy_nas.sh" | sed 's/\$PROXY_SERVICE/nginx/'); do
    report "docker-compose.prod.yml declares the essential service $s" 1 "$(grep -cE "^  $s:$" "$ROOT/docker-compose.prod.yml")"
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
