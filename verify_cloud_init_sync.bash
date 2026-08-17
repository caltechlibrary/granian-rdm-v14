#!/bin/bash
# Acceptance script for the AWS/Multipass sync problem found 2026-08-17
# (see NOTES.md's 2026-08-17 entry): cloud-init.yaml and
# cloud-init-multipass.yaml are described everywhere in this repo as
# "kept in sync," but nothing actually checked that -- they silently
# diverged on RDM_PIN_VERSION, Node version, and TEMPLATE_VERSION during
# the undocumented 2026-07-28 session. This is the static, no-AWS/no-
# Multipass-instance-needed equivalent of verify_rdm_boot.bash: it reads
# the two YAML files as text and fails loudly if they disagree, instead
# of the disagreement being invisible until something breaks live.
#
# Deliberately does NOT check the vendored invenio-cli --runner granian
# patch's presence/absence -- that divergence (AWS: absent, Multipass:
# present, because of AWS's 16384-byte user-data limit) is a separate,
# explicitly recorded decision (see DECISIONS.md), not a bug this script
# should flag.
#
# USAGE: verify_cloud_init_sync.bash [AWS_FILE] [MULTIPASS_FILE]
set -uo pipefail
AWS_FILE="${1:-cloud-init.yaml}"
MULTIPASS_FILE="${2:-cloud-init-multipass.yaml}"
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

# Extracts a single value all matches of a `sed -E` substitution must
# agree on within one file. `sed_expr` should be a `s/.../\1/p`-style
# expression capturing exactly the value of interest. Uses portable
# POSIX extended regexes (via `sed -E`) rather than PCRE (`grep -P`) --
# macOS's BSD grep doesn't support -P, and this script needs to run on
# both this Mac and the Ubuntu instances it's checking. Echoes the value
# and returns 0 if every match in the file agrees; echoes nothing and
# returns 1 if the file itself is internally inconsistent (a different,
# worse bug than a cross-file mismatch) or if the pattern isn't found.
extract_single_value() {
  local file="$1"
  local sed_expr="$2"
  local values
  values="$(sed -nE "$sed_expr" "$file" | sort -u)"
  if [ -z "$values" ]; then
    return 1
  fi
  if [ "$(wc -l <<< "$values")" -ne 1 ]; then
    return 1
  fi
  echo "$values"
}

# shellcheck disable=SC2329  # called indirectly via check()'s "$@"
node_versions_match() {
  local aws_node multipass_node
  aws_node="$(extract_single_value "$AWS_FILE" 's/.*nvm (install|use) ([0-9]+).*/\2/p')" || {
    echo "    ${AWS_FILE}: nvm install/use versions are not internally consistent" >&2
    return 1
  }
  multipass_node="$(extract_single_value "$MULTIPASS_FILE" 's/.*nvm (install|use) ([0-9]+).*/\2/p')" || {
    echo "    ${MULTIPASS_FILE}: nvm install/use versions are not internally consistent" >&2
    return 1
  }
  if [ "$aws_node" != "$multipass_node" ]; then
    echo "    ${AWS_FILE}: Node ${aws_node}  vs  ${MULTIPASS_FILE}: Node ${multipass_node}" >&2
    return 1
  fi
}

# shellcheck disable=SC2329  # called indirectly via check()'s "$@"
rdm_pin_versions_match() {
  local aws_pin multipass_pin
  aws_pin="$(extract_single_value "$AWS_FILE" 's/.*RDM_PIN_VERSION="\$\{3:-([^}]+)\}".*/\1/p')" || return 1
  multipass_pin="$(extract_single_value "$MULTIPASS_FILE" 's/.*RDM_PIN_VERSION="\$\{3:-([^}]+)\}".*/\1/p')" || return 1
  if [ "$aws_pin" != "$multipass_pin" ]; then
    echo "    ${AWS_FILE}: RDM_PIN_VERSION=${aws_pin}  vs  ${MULTIPASS_FILE}: RDM_PIN_VERSION=${multipass_pin}" >&2
    return 1
  fi
}

# shellcheck disable=SC2329  # called indirectly via check()'s "$@"
template_versions_match() {
  local aws_template multipass_template
  aws_template="$(extract_single_value "$AWS_FILE" 's/.*TEMPLATE_VERSION="\$\{2:-([^}]+)\}".*/\1/p')" || return 1
  multipass_template="$(extract_single_value "$MULTIPASS_FILE" 's/.*TEMPLATE_VERSION="\$\{2:-([^}]+)\}".*/\1/p')" || return 1
  if [ "$aws_template" != "$multipass_template" ]; then
    echo "    ${AWS_FILE}: TEMPLATE_VERSION=${aws_template}  vs  ${MULTIPASS_FILE}: TEMPLATE_VERSION=${multipass_template}" >&2
    return 1
  fi
}

check "Node version matches between ${AWS_FILE} and ${MULTIPASS_FILE}" node_versions_match
check "RDM_PIN_VERSION matches between ${AWS_FILE} and ${MULTIPASS_FILE}" rdm_pin_versions_match
check "TEMPLATE_VERSION matches between ${AWS_FILE} and ${MULTIPASS_FILE}" template_versions_match

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "${FAILURES} check(s) failed."
  exit 1
fi
