#!/bin/bash

# ZapZap - self-test of scripts/deploy_nas.sh, offline, in seconds.
#
# The deploy is the production path: the order of its steps is what makes a failed deploy
# a no-op instead of an outage, and only a sandbox can assert it. A sandbox git repository
# holds a copy of the script and of docker-compose.prod.yml; `ssh` is a stub that runs the
# remote command locally, so the NAS half of the script really runs, in a sandbox deploy
# directory holding a real SQLite database, against stubbed `docker`, `docker-compose`,
# `curl`, `jq` and `sleep` that log their arguments. The logs' order is the assertion.
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
FAILS="$SANDBOX/fails"       # one file per failing step: build, push, pull, down, up, config,
                             # wget (the backend image has none), backup; and the switches
                             # present (every image already on the NAS), fixeddate
mkdir -p "$REPO/scripts" "$REPO/zapzap-rust" "$REPO/frontend" "$REPO/frontend-flutter" "$REPO/nginx" \
    "$NAS/data" "$TOOLS" "$STATES" "$FAILS"
REAL_PYTHON=$(command -v python3)
REAL_DATE=$(command -v date)

cp "$ROOT/scripts/deploy_nas.sh" "$REPO/scripts/"
cp "$ROOT/docker-compose.prod.yml" "$REPO/"
for d in zapzap-rust frontend frontend-flutter nginx; do echo "FROM scratch" > "$REPO/$d/Dockerfile"; done
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t
git -C "$REPO" add -A
git -C "$REPO" commit -qm first
tag_of() { git -C "$REPO" rev-parse HEAD | cut -c1-12; }
FIRST=$(tag_of)
git -C "$REPO" commit -q --allow-empty -m second
SECOND=$(tag_of)

echo "JWT_SECRET=not-a-real-one" > "$NAS/.env"
"$REAL_PYTHON" -c 'import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE users(name)"); c.execute("INSERT INTO users VALUES (?)", ("a player",)); c.commit()' "$NAS/data/zapzap.db"

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
    run)                                    # the wget probe of the backend image
        echo "docker \$*" >> "$LOG"
        [ -f "$FAILS/wget" ] && exit 1
        echo /usr/bin/wget ;;
    image)                                  # image inspect: is it already on the NAS?
        echo "docker \$*" >> "$LOG"
        [ -f "$FAILS/present" ] || exit 1 ;;
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
cat > "$TOOLS/python3" <<EOF
#!/bin/sh
if [ -f "$FAILS/backup" ]; then echo "sqlite3.OperationalError: database is locked" >&2; exit 1; fi
exec "$REAL_PYTHON" "\$@"
EOF
cat > "$TOOLS/date" <<EOF
#!/bin/sh
# The backup's timestamp: a fresh second per call (the tests run many deploys a second),
# or always the same one with the fixeddate switch.
if [ "\$1" = "+%F-%H%M%S" ]; then
    if [ -f "$FAILS/fixeddate" ]; then echo 2026-01-01-000000; exit 0; fi
    n=\$(( \$(cat "$SANDBOX/date.n" 2>/dev/null || echo 0) + 1 )); echo \$n > "$SANDBOX/date.n"
    printf '2026-01-02-%06d\\n' \$n; exit 0
fi
exec "$REAL_DATE" "\$@"
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
rollback() { run "${CONF[@]}" -- --rollback "$@"; }
# The steps that change what is running, as "pull|down --remove-orphans|up -d".
steps() { sed -nE 's/^compose\[[^]]*\] (pull|down.*|up.*)$/\1/p' "$LOG" | tr '\n' '|' | sed 's/|$//'; }
builds() { grep -c '^docker build' "$LOG"; }
pushes() { grep -c '^docker push' "$LOG"; }
image_tags() { sed -nE 's#^[[:space:]]*image:[[:space:]]*(.*)$#\1#p' "$NAS/compose.yaml" | tr '\n' ' ' | sed 's/ $//'; }
backups() { find "$NAS/data" -name 'zapzap.db.bak-*' | wc -l | tr -d ' '; }
pinned() { printf 'reg.test:5050/zapzap-backend:%s reg.test:5050/zapzap-frontend:%s reg.test:5050/zapzap-frontend-flutter:%s reg.test:5050/zapzap-proxy:%s' "$1" "$1" "$1" "$1"; }
commit_compose() {  # message, marker: a commit whose docker-compose.prod.yml carries the marker
    sed -i '/^# marker-/d' "$REPO/docker-compose.prod.yml"
    [ -z "$2" ] || echo "# marker-$2" >> "$REPO/docker-compose.prod.yml"
    git -C "$REPO" commit -qam "$1"
}

reset

echo "== configuration and usage ===================================="
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
run -- --help; rc=$?
report "--help exits 0"                          0 "$rc"
has "--help names --rollback"                    "--rollback <sha>"
has "--help names --build-only"                  "--build-only"
has "--help names --help"                        "deploy_nas.sh --help"
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
rm -rf "$NAS"/compose.yaml* "$NAS/composes"
find "$NAS/data" -name '*.bak-*' -delete
deploy; rc=$?
report "the happy path exits 0"                 0 "$rc"
report "the tag is the first 12 characters of the sha" 12 "${#SECOND}"
report "builds the four images"                 4 "$(builds)"
report "the backend with the bedrock feature"   1 "$(grep -c "^docker build --build-arg CARGO_FEATURES=bedrock .*-t reg.test:5050/zapzap-backend:$SECOND -t reg.test:5050/zapzap-backend:latest zapzap-rust$" "$LOG")"
report "the proxy from nginx/"                  1 "$(grep -c "^docker build .*-t reg.test:5050/zapzap-proxy:$SECOND .* nginx$" "$LOG")"
report "probes the backend image for wget before any push" \
    "docker run --rm --entrypoint sh reg.test:5050/zapzap-backend:$SECOND -c command -v wget" \
    "$(grep -m1 -E '^docker (run|push)' "$LOG")"
report "pushes each as <sha> and latest"        8 "$(pushes)"
report "the NAS compose pins every image to the sha" "$(pinned "$SECOND")" "$(image_tags)"
report "and keeps it as composes/compose.<tag>.yaml" same \
    "$(cmp -s "$NAS/compose.yaml" "$NAS/composes/compose.$SECOND.yaml" && echo same || echo differs)"
report "pulls before it stops anything"         "pull|down --remove-orphans|up -d" "$(steps)"
report "pulls with the new file, before it replaces compose.yaml" 1 "$(grep -c '^compose\[compose.yaml.next\] pull' "$LOG")"
report "backs the database up once"             1 "$(backups)"
bak=$(find "$NAS/data" -name 'zapzap.db.bak-*' | head -1)
case "$bak" in *.bak-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-"$SECOND") got=named ;; *) got="$bak" ;; esac
report "a backup named with seconds and the tag" named "$got"
report "the backup is a readable SQLite copy holding the players" 1 \
    "$("$REAL_PYTHON" -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("SELECT COUNT(*) FROM users").fetchone()[0])' "$bak" 2>&1)"
has "prints the downtime it caused"             "downtime was "
has "and a success banner"                      "✨ Deployed $SECOND"
report "the NAS check runs before the first build" "ssh nas" "$(head -1 "$LOG")"
report "and leaves no candidate file behind"    gone \
    "$([ -e "$NAS/compose.yaml.next" ] || [ -e "$NAS/compose.yaml.rendered" ] && echo kept || echo gone)"

echo "== build only ================================================="
git -C "$REPO" commit -q --allow-empty -m build-only
before=$(cat "$NAS/compose.yaml")
run REGISTRY=reg.test:5050 VITE_GOOGLE_OAUTH_CLIENT_ID=client-id -- --build-only; rc=$?
report "--build-only needs only REGISTRY, and exits 0" 0 "$rc"
report "builds and pushes"                      "4 8" "$(builds) $(pushes)"
report "and never reaches the NAS"              0 "$(grep -c '^ssh' "$LOG")"
report "whose compose.yaml is unchanged"        "$before" "$(cat "$NAS/compose.yaml")"
mv "$NAS/data/zapzap.db" "$NAS/data/zapzap.db.away"
run REGISTRY=reg.test:5050 VITE_GOOGLE_OAUTH_CLIENT_ID=client-id -- --build-only; rc=$?
report "--build-only works without a database on the NAS" 0 "$rc"
mv "$NAS/data/zapzap.db.away" "$NAS/data/zapzap.db"
echo "edited" >> "$REPO/docker-compose.prod.yml"
run REGISTRY=reg.test:5050 VITE_GOOGLE_OAUTH_CLIENT_ID=client-id -- --build-only; rc=$?
report "--build-only refuses a dirty tree too"  1 "$rc"
git -C "$REPO" checkout -q docker-compose.prod.yml

echo "== failures before the stop ==================================="
deploy >/dev/null
before=$(cat "$NAS/compose.yaml")
git -C "$REPO" commit -q --allow-empty -m third
failing build
deploy; rc=$?
report "a failed build exits 1"                 1 "$rc"
report "and pushes nothing"                     0 "$(pushes)"
report "and touches no container"               "" "$(steps)"
report "and leaves compose.yaml alone"          "$before" "$(cat "$NAS/compose.yaml")"
failing wget
deploy; rc=$?
report "a backend image without wget is refused" 1 "$rc"
report "before any push"                        0 "$(pushes)"
report "and touches no container"               "" "$(steps)"
has "naming wget and #106"                      "#106"
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
nbak=$(backups)
failing backup
deploy; rc=$?
report "a failed backup exits 1"                1 "$rc"
report "after the pull, before any stop"        "pull" "$(steps)"
report "and leaves no partial backup"           "$nbak" "$(backups)"
report "and leaves compose.yaml alone"          "$before" "$(cat "$NAS/compose.yaml")"
has "printing python's reason"                  "database is locked"
hasnt "without pretending it is disk space on the NAS" "Free space on the NAS"
failing fixeddate
THIRD=$(tag_of)
echo "an older backup" > "$NAS/data/zapzap.db.bak-2026-01-01-000000-$THIRD"
deploy; rc=$?
report "an existing backup is never overwritten: exit 1" 1 "$rc"
report "the older backup is intact"             "an older backup" "$(cat "$NAS/data/zapzap.db.bak-2026-01-01-000000-$THIRD")"
report "and nothing was stopped"                "pull" "$(steps)"
rm -f "$NAS/data/zapzap.db.bak-2026-01-01-000000-$THIRD"
failing
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

echo "== stop, start, health ========================================"
failing
deploy; rc=$?
report "a deploy after the failures works"      0 "$rc"
running=$(cat "$NAS/compose.yaml")
git -C "$REPO" commit -q --allow-empty -m fourth
FOURTH=$(tag_of)
failing down
deploy; rc=$?
report "a failing down exits 1"                 1 "$rc"
report "the down ran with the running compose file" 1 "$(grep -c '^compose\[compose.yaml\] down --remove-orphans' "$LOG")"
report "and the recovery restarts that same file, not the new images" "pull|down --remove-orphans|up -d" "$(steps)"
report "compose.yaml still pins what ran before" "$running" "$(cat "$NAS/compose.yaml")"
report "and no compose is stored for the failed tag" gone "$([ -e "$NAS/composes/compose.$FOURTH.yaml" ] && echo kept || echo gone)"
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
has "and naming the rollback command"           "deploy_nas.sh --rollback $FOURTH"
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
commit_compose "compose A" A
TAG_A=$(tag_of)
deploy; rc=$?
report "a deploy of compose A"                  0 "$rc"
commit_compose "compose B" B
TAG_B=$(tag_of)
deploy; rc=$?
report "a deploy of compose B"                  0 "$rc"
: > "$REPO/zapzap-rust/dirty.rs"                 # a rollback builds nothing: a dirty tree is fine
nbak=$(find "$NAS/data" -name "zapzap.db.bak-*-$TAG_A" | wc -l | tr -d ' ')
rollback "$TAG_A"; rc=$?
report "--rollback exits 0 when healthy"        0 "$rc"
report "and builds and pushes nothing"          0 "$(( $(builds) + $(pushes) ))"
report "restores the compose file A was deployed with" 1 "$(grep -c '^# marker-A$' "$NAS/compose.yaml")"
report "not B's with its tags swapped"          0 "$(grep -c '^# marker-B$' "$NAS/compose.yaml")"
has "saying which file it restored"             "composes/compose.$TAG_A.yaml"
report "every image pinned to A"                "$(pinned "$TAG_A")" "$(image_tags)"
report "pulls, then down, then up"              "pull|down --remove-orphans|up -d" "$(steps)"
has "and waits for the site"                    "downtime was "
report "backs the database up first"            $((nbak + 1)) "$(find "$NAS/data" -name "zapzap.db.bak-*-$TAG_A" | wc -l | tr -d ' ')"
rm -f "$REPO/zapzap-rust/dirty.rs"

# Every image already on the NAS: no registry needed.
failing present pull
rollback "$TAG_B"; rc=$?
report "a rollback whose images are on the NAS works with the registry down" 0 "$rc"
report "and does not pull"                      "down --remove-orphans|up -d" "$(steps)"
report "after checking every image"             4 "$(grep -c '^docker image inspect' "$LOG")"
failing

# No compose stored for the tag: rendered from that commit's docker-compose.prod.yml.
rm -f "$NAS/composes/compose.$TAG_A.yaml"
rollback "$TAG_A"; rc=$?
report "a tag with no stored compose is rendered from git" 0 "$rc"
report "from that commit's compose file"        1 "$(grep -c '^# marker-A$' "$NAS/compose.yaml")"
has "saying so"                                 "rendered from git"
report "and leaves no rendered file behind"     gone "$([ -e "$NAS/compose.yaml.rendered" ] && echo kept || echo gone)"

# A full sha is shortened to the tag; a 12-character tag git does not know is taken verbatim.
rollback "$(git -C "$REPO" rev-parse "$TAG_B")"; rc=$?
report "a full sha is shortened to the tag"     "$TAG_B" "$(sed -nE 's#.*/zapzap-backend:(.*)#\1#p' "$NAS/compose.yaml")"
cp "$NAS/composes/compose.$TAG_A.yaml" "$NAS/composes/compose.abcdef123456.yaml"
sed -i "s/:$TAG_A\$/:abcdef123456/" "$NAS/composes/compose.abcdef123456.yaml"
rollback abcdef123456; rc=$?
report "a stored tag git does not know is taken verbatim" 0 "$rc"
report "and restored"                           "$(pinned abcdef123456)" "$(image_tags)"

before=$(cat "$NAS/compose.yaml")
rollback 0123456789ab; rc=$?
report "a tag neither stored nor known to git is refused" 1 "$rc"
has "clearly"                                   "keeps no compose file for it"
report "and stops nothing"                      "" "$(steps)"
report "and leaves compose.yaml alone"          "$before" "$(cat "$NAS/compose.yaml")"

unhealthy backend unhealthy
rollback "$TAG_A"; rc=$?
report "a rollback gets the same health wait: exit 1" 1 "$rc"
has "naming the container"                      "backend(unhealthy)"
unhealthy
before=$(cat "$NAS/compose.yaml")
failing pull
rollback "$SECOND"; rc=$?
report "a rollback whose images must be pulled and cannot exits 1" 1 "$rc"
report "and stops nothing"                      "pull" "$(steps)"
report "and leaves compose.yaml alone"          "$before" "$(cat "$NAS/compose.yaml")"
failing
rollback 'abc1234;rm'; rc=$?
report "a rollback target that is not a sha is refused" 1 "$rc"
report "without reaching the NAS"               "" "$(cat "$LOG")"
rollback deadbee; rc=$?
report "a short sha this repository does not know is refused" 1 "$rc"
report "without reaching the NAS either"        "" "$(cat "$LOG")"
run "${CONF[@]}" -- --rollback; rc=$?
report "--rollback without a sha is refused"    1 "$rc"
run "${CONF[@]}" -- --bogus; rc=$?
report "an unknown argument is refused"         1 "$rc"

echo "== stored composes ============================================"
for i in $(seq 1 12); do
    printf 'x\n' > "$NAS/composes/compose.old$i.yaml"
    touch -d "2020-01-$(printf %02d "$i")" "$NAS/composes/compose.old$i.yaml"
done
deploy; rc=$?
report "a deploy with many stored composes"     0 "$rc"
report "keeps the last 10"                      10 "$(find "$NAS/composes" -name 'compose.*.yaml' | wc -l | tr -d ' ')"
report "the one just deployed among them"       kept "$([ -e "$NAS/composes/compose.$(tag_of).yaml" ] && echo kept || echo gone)"
report "and drops the oldest"                   gone "$([ -e "$NAS/composes/compose.old1.yaml" ] && echo kept || echo gone)"

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
