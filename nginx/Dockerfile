# The production reverse proxy (zapzap-proxy): nginx:alpine with nginx.conf baked in, so
# the NAS runs a registry image and holds no copy of the repository. The root
# docker-compose.yml still mounts nginx.conf for local use. Built by scripts/deploy_nas.sh
# and by the CI `image` job, which runs `nginx -t` in it.
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
# The privacy policy Google Play links to, served at /privacy by nginx.conf. Generated from
# the root privacy_policy.md by scripts/build_privacy_page.py: edit that, never this copy.
COPY privacy.html /usr/share/nginx/zapzap/privacy.html
