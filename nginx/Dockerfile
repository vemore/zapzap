# The production reverse proxy (zapzap-proxy): nginx:alpine with nginx.conf baked in, so
# the NAS runs a registry image and holds no copy of the repository. The root
# docker-compose.yml still mounts nginx.conf for local use. Built by scripts/deploy_nas.sh
# and by the CI `image` job, which runs `nginx -t` in it.
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
