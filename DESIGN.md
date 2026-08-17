# Design: RDM v14 + Granian (free-threaded) bring-up via clasm

## Problem statement

Bring up a vanilla InvenioRDM v14 instance for demo/dev purposes, running
under Granian (instead of uWSGI) on free-threaded Python 3.14t, provisioned
entirely through `clasm` — including the IAM roles/instance-profile it now
supports. This continues the Granian evaluation started with the v13
Gunicorn-vs-Granian comparison, but this round is a single Granian instance,
not a paired comparison (that question was already answered in the v13
round).

## Scope decisions (confirmed with user, 2026-07-24)

- **Single Granian instance**, not a paired Granian-vs-Gunicorn comparison.
- **Free-threaded Python 3.14t**, not standard CPython — managed via `uv`,
  so falling back to standard 3.14 is a one-line `uv python pin` change if
  free-threaded compatibility problems surface.
- **Start now, pinned to `invenio-app-rdm==14.0.0rc2`.** No firm v14.0.0 GA
  date exists yet; re-pin to GA once it tags (same "pin the exact patch"
  pattern used for production in the v13 round).

## Grounding facts (verified 2026-07-24 against live GitHub state)

- `v14.0.0rc2` was tagged 2026-06-13 — over a month ago as of this writing.
  No final `v14.0.0` GA tag exists yet. Issue #3499 (i18n tracking for v14)
  is still open. A `maint-14.1.x` branch already exists accumulating
  backports for the *next* release after v14 — GA appears close but has no
  published date.
- **No `v14.0` `cookiecutter-invenio-rdm` branch exists** (branches stop at
  `v13.0`). Scaffolding v14 means using `master`, which — unlike `v13.0` —
  already emits `pyproject.toml` + hatchling + a `uv` workspace natively.
  This *removes* the Pipfile→pyproject.toml conversion hack that
  `setup_rdm_granian.bash` needed for v13.
- `master`'s template pins `invenio-app-rdm~=14.0.0b11.dev1` (a beta) by
  default. Must override this to `==14.0.0rc2` post-scaffold via `uv add`,
  same exact-pin approach as the v13 script.
- `master`'s template now requires `python>=3.14` (v13 required 3.12) — a
  real toolchain change, not just a version bump.
- Every C-extension dependency in RDM's tree (psycopg2/psycopg, lxml, etc.)
  needs a free-threaded-compatible wheel for 3.14t. Not yet verified against
  RDM's actual resolved dependency set — this is a real risk, not a
  footnote, and should be checked early (`uv add` with `--python 3.14t` and
  see what fails to resolve/build) rather than assumed.
- `clasm` v0.0.5 (implemented, real-AWS-verified, not yet released) already
  covers everything needed on the IAM/infra side that the v13 round lacked:
  - SSM-capable instance-profile enforcement at launch (Phase 20.33).
  - EBS root-volume sizing at launch (Phase 20.31) — v13 always inherited
    the AMI's default 8GB.
  - arm64/Graviton + Ubuntu 26.04 LTS support (Phase 20.35).
  - A curated **"RDM Repository Instance"** IAM role/policy template (SSM +
    scoped S3 read/write on one backup-bucket ARN, Phase 20.39) — this
    directly replaces the plain-IAM-user-access-key workaround the
    2026-07-22 v13 detour had to fall back to when a running instance
    needed S3 access with no instance-role option available.

## Open questions -- resolved 2026-07-27, see DECISIONS.md

1. **Architecture**: resolved -- arm64/Graviton. See DECISIONS.md,
   "Architecture: arm64/Graviton."
2. **AMI choice**: resolved -- Ubuntu 26.04 LTS. See DECISIONS.md,
   "AMI: Ubuntu 26.04 LTS."
3. **Granian tuning model**: not yet resolved -- deliberately deferred
   until a working baseline boots (see PLAN.md Step 5). `cloud-init.yaml`
   carries the v13 uWSGI-matched numbers forward as an explicit,
   flagged-unverified placeholder in the meantime.
4. **Where this lives**: resolved -- new repo, `granian-rdm-v14` (this
   repository), not folded into `gunicorn-rdm-v13`.

A fourth risk, not originally listed as an open question but confirmed
live 2026-07-27: `psycopg2-binary` has no free-threaded (`cp314t`) wheel
on PyPI, which risks CPython silently re-enabling the GIL process-wide.
See DECISIONS.md, "Free-threaded Python 3.14t: proceed, verify
empirically."

**Free-threaded Python 3.14t was tried and abandoned this same day**,
after the above risk was confirmed real, worked around (source-built
psycopg2/psycopg[c], excluded orjson/orjsonl with a ujson-based
fallback shim), and the app successfully installed -- only for a deeper,
unfixable-at-our-level gap to surface: SQLAlchemy 2.0.51's own bundled
C extension re-enables the GIL process-wide the moment the app loads,
confirmed via `sys._is_gil_enabled()` returning `False` after
`invenio_app.factory.create_app()`. This round now uses standard
(GIL-enabled) Python 3.14 instead. See DECISIONS.md, "Free-threaded
Python 3.14t: tried, abandoned this round," for the full account and
what to check before reattempting 3.14t later.

Two further real bugs, unrelated to Python version, found during the
same live-testing pass and now fixed in `cloud-init.yaml`: `master`'s
cookiecutter template dropping the `database`/`search` prompts while
`invenio-cli` 1.11.0 still requires them in `.invenio` (see PLAN.md Step
3's "real bugs" list), and `invenio-assets`' own `@rspack/core`/
`@rspack/cli` peer-dependency conflict under npm 10 (fixed via
`legacy-peer-deps`).

## Proposed approach (high-level — detailed steps go in the implementation plan)

1. **IAM via clasm**: create (or verify) a role + instance profile using
   the "RDM Repository Instance" template (SSM + scoped S3 backup bucket),
   tagged per the `Origin` convention.
2. **Launch via clasm**: a single EC2 instance/launch template — EBS sized
   explicitly (no more 8GB-default inheritance), SSM-capable profile
   attached at launch, AMI/arch per the open questions above.
3. **Cloud-init**: adapt `invenio-rdm-13-granian-init.yaml` →
   `invenio-rdm-14-granian-init.yaml`:
   - `uv python install 3.14t` / `uv python pin 3.14t` in place of the
     nvm/Node-and-pip toolchain assumptions tied to 3.12.
   - Scaffold from `cookiecutter-invenio-rdm`'s `master` branch instead of
     `v13.0`.
   - Drop the Pipfile→pyproject.toml conversion step (master already
     scaffolds pyproject.toml/hatchling/uv-workspace).
   - Re-pin `invenio-app-rdm` to `==14.0.0rc2` post-scaffold via `uv add`.
   - Keep the `uv add granian` + systemd-unit pattern from v13, but leave
     `--workers`/thread flags as an open tuning question (item 3 above)
     rather than reusing v13's numbers unexamined.
4. **Boot and smoke-test**: services up, demo data loads, nginx TLS proxy
   works — same acceptance bar as v13's "vanilla instance to demo to
   colleagues."
5. **Only after a working baseline**: begin the Granian tuning exploration
   (worker/thread/runtime-thread permutations under free-threaded Python),
   documenting each configuration tried and what was observed.

## Follow-on: operability hardening (scoped 2026-07-27)

### Problem statement

Running the bring-up procedure end-to-end surfaced two distinct operability
pain points, separate from the bring-up itself:

1. **Dev iteration overhead.** `cloud-init.yaml` wires the instance for a
   production topology (Granian UI/REST split + nginx, all under systemd)
   with no dev-mode path at all. A developer who wants to iterate locally
   is stuck starting/stopping three systemd units by hand. Upstream
   `invenio-cli`'s own `run_all()` (`invenio_cli/commands/local.py`,
   verified against `inveniosoftware/invenio-cli` HEAD 2026-07-27) already
   spawns the dev web process + Celery worker + beat/jobs scheduler
   together with clean SIGINT teardown — but it hardcodes Flask's built-in
   dev server (`invenio run`) as the web process and interleaves all
   processes' stdout with no per-process labeling.
2. **Production reboot brittleness.** The systemd units `cloud-init.yaml`
   writes (`rdm.service`, `rdm_rest.service`, `rdm_celery.service`, plus
   the distro's `nginx.service`) declare no `Requires=`/`After=` on Docker
   or on each other, and there is no readiness gate distinguishing
   "container started" from "Postgres/OpenSearch/RabbitMQ actually
   accepting connections." On reboot the units race, which manifests as
   needing to manually stop and restart everything in the right order.

### Constraints

- The `invenio-cli` change should stay narrow and additive (new optional
  behavior, backward-compatible defaults) so it's plausibly upstreamable
  later — per `inveniosoftware/invenio-cli`'s own `CONTRIBUTING.rst` and
  its existing `tests/commands/test_local.py` conventions (pytest +
  `unittest.mock.patch` around `Popen`/`run_cmd`, a `mock_cli_config`
  fixture). No changes to `invenio-cli`'s public CLI surface beyond new
  optional flags.
- Vendored in this repo for now, not a forked clone of `invenio-cli` —
  decided 2026-07-27 (see DECISIONS.md); revisit once the change is
  proven out.
- The systemd fix stays self-contained to this repo's
  `cloud-init.yaml` — no changes to `invenio-cli` or `clasm`.

### Proposed approach (detailed steps in PLAN.md Step 6/7)

1. **`invenio-cli` dev runner enhancement**: vendor a patched copy of
   `local.py` adding (a) a `runner=granian|flask` option to `run_web` so
   the dev process matches this project's production runtime when
   desired, and (b) per-process output labeling for `run_all`'s
   concurrently running web/worker/beat processes.
2. **systemd reboot hardening**: add `Requires=`/`After=docker.service`
   and an `ExecStartPre` readiness probe to each of the three custom
   units, order `nginx` `After=` the app units, and group all four under
   one `rdm.target` for a single reliable start/stop/reboot path.

## Non-goals this round

- No Gunicorn comparison instance (already answered in v13).
- No S3/production-scale benchmarking (still deferred, per the v13
  rescoping decision on 2026-07-22).
- No CloudFront/container-registry work (out of scope; someday/maybe per
  `clasm`'s own backlog).

## Update -- 2026-08-17: v14 GA, and a new template-drift question

Two things changed since this document was last written (2026-07-27),
verified live rather than assumed:

1. **`invenio-app-rdm` 14.0.0 is now GA.** PyPI's `info.version` is
   `14.0.0` (Production/Stable). GitHub tags show `rc3` (this doc's
   "grounding facts" pin) was followed by `rc4`, `rc5`, `rc6`, then the
   `v14.0.0` GA tag. The exact-pin approach this document already
   committed to ("re-pin to GA once it tags, same pattern used for
   production in the v13 round") now applies -- see the sync-fix and
   pin-bump phases of the current implementation plan.
2. **`cookiecutter-invenio-rdm`'s `master` branch has moved on to v15.**
   It now pins `invenio-app-rdm~=15.0.0b2.dev0` (commit `5707760`,
   2026-08-06) -- not true when `master` was chosen as the scaffold
   source (2026-07-24, back when `master` cleanly tracked v14
   pre-releases, and no version-numbered v14 branch existed yet).
   Scaffolding from `master` today means scaffolding for v15 and
   force-downgrading to `invenio-app-rdm==14.0.0`, not the clean match it
   was originally. (`uwsgi`/`uwsgitop`/`uwsgi-tools` in the template is
   *not* part of what changed -- confirmed present continuously since at
   least `b9.dev0`, already noted in this document's original
   2026-07-24 grounding facts above; the existing strip step in
   `setup_rdm_granian.bash` already handles it regardless.) Resolved in
   DECISIONS.md's newest entry: a real `v14.0` branch now exists (it
   didn't on 2026-07-24) and is the new scaffold source.

Also confirmed (not previously written down anywhere): this project's own
two cloud-init files silently diverged on 2026-07-28 -- `cloud-init.yaml`
(AWS) was bumped to `RDM_PIN_VERSION=14.0.0rc3`/Node 26 and had the
vendored `invenio-cli --runner granian` patch removed entirely (AWS's
16384-byte user-data limit); `cloud-init-multipass.yaml` was never
bumped and still carries the patch. See NOTES.md's 2026-08-17 entry for
the full reconstruction from `git log`, and the current plan's Phase 3/4
for the fix.
