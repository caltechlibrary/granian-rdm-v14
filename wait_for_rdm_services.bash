#!/bin/bash
# ExecStartPre readiness gate for the rdm/rdm_rest/rdm_celery systemd
# units (see ../cloud-init.yaml). A Docker container reporting "started"
# is not the same as the service inside it actually accepting
# connections -- that gap is the root cause identified in DESIGN.md's
# "Follow-on: operability hardening" for reboot brittleness (PLAN.md
# Step 7). This blocks until Postgres/Redis/RabbitMQ/OpenSearch on
# 127.0.0.1 all respond, or exits non-zero after a bounded timeout so
# systemd's Restart=on-failure retries the whole unit instead of the
# ExecStart racing ahead against services that aren't ready yet.
set -uo pipefail
TIMEOUT_SECONDS=180
INTERVAL_SECONDS=2
DEADLINE=$(($(date +%s) + TIMEOUT_SECONDS))

tcp_ready() {
  local host="$1" port="$2"
  (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null
}

http_ready() {
  curl -fsS -o /dev/null --max-time 5 "$1"
}

wait_for() {
  local description="$1"
  shift
  while ! "$@"; do
    if [ "$(date +%s)" -ge "$DEADLINE" ]; then
      echo "Timed out after ${TIMEOUT_SECONDS}s waiting for ${description}" >&2
      return 1
    fi
    sleep "$INTERVAL_SECONDS"
  done
  echo "${description} is ready"
}

wait_for "Postgres (127.0.0.1:5432)" tcp_ready 127.0.0.1 5432
wait_for "Redis/cache (127.0.0.1:6379)" tcp_ready 127.0.0.1 6379
wait_for "RabbitMQ (127.0.0.1:5672)" tcp_ready 127.0.0.1 5672
wait_for "OpenSearch (127.0.0.1:9200)" http_ready http://127.0.0.1:9200
