#!/bin/bash
# Step 7 acceptance script (see ../PLAN.md "Step 7 -- systemd reboot
# hardening"). Run this manually right after `sudo reboot` -- not just
# after a manual `systemctl start` sequence -- to confirm the instance
# actually comes back up unattended. Exit 0 = every check passed;
# nonzero = something is still broken.
#
# Deliberately standalone from wait_for_rdm_services.bash (the
# production readiness gate baked into the systemd units via
# ExecStartPre): this script is the outside observer confirming the gate
# actually worked, not part of the gate itself. Keep this in the repo as
# a standing regression check for any future edit to cloud-init.yaml's
# systemd unit section.
#
# USAGE: verify_rdm_boot.bash [INSTANCE_NAME]
set -uo pipefail
INSTANCE_NAME="${1:-rdm14-granian}"
FAILURES=0

check() {
  local description="$1"
  shift
  if "$@"; then
    echo "OK   -- ${description}"
  else
    echo "FAIL -- ${description}"
    FAILURES=$((FAILURES + 1))
  fi
}

# shellcheck disable=SC2329  # called indirectly via check()'s "$@"
units_active() {
  systemctl is-active --quiet docker rdm rdm_rest rdm_celery nginx
}

# shellcheck disable=SC2329  # called indirectly via check()'s "$@"
api_responds() {
  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 https://localhost/api/records)"
  [ "$code" = "200" ]
}

# shellcheck disable=SC2329  # called indirectly via check()'s "$@"
celery_responds() {
  (cd "/Sites/${INSTANCE_NAME}" 2>/dev/null && \
    timeout 15 uv run --no-sync celery --app invenio_app.celery inspect ping 2>/dev/null) \
    | grep -q "pong"
}

check "docker/rdm/rdm_rest/rdm_celery/nginx are all systemctl active" units_active
check "https://localhost/api/records responds 200" api_responds
check "celery worker responds to inspect ping" celery_responds

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "${FAILURES} check(s) failed."
  exit 1
fi
