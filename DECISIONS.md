# Decisions

## 2026-07-27 — Architecture: arm64/Graviton

**Context.** DESIGN.md's open question 1: match production's x86_64
(`m7i-flex.2xlarge`) or try arm64/Graviton now that clasm v0.0.5 supports
it.

**Decision.** arm64/Graviton.

**Rationale.**
- clasm v0.0.5 already has arm64 support (curated AMI list + Graviton
  instance-type family, Phase 20.35).
- Checked live against PyPI's JSON API (2026-07-27): lxml, cryptography,
  and sqlalchemy all publish `cp314`/`cp314t` (free-threaded) wheels for
  `aarch64` -- no blocker found for the packages checked.
- This round isn't a controlled comparison against production the way the
  v13 round was (that question is already answered) -- there's no
  requirement to hold architecture constant.

**Consequences.**
- Adds a second new variable (arch) on top of free-threaded Python 3.14t.
  If something breaks, worth checking whether it's arch-specific or
  3.14t-specific before assuming either.
- Instance type: Graviton equivalent of `m7i-flex.2xlarge` is `m6g.2xlarge`
  (same general-purpose family, comparable vCPU/memory ratio) -- not a
  strict requirement, adjustable at launch time.

---

## 2026-07-27 — AMI: Ubuntu 26.04 LTS

**Context.** DESIGN.md's open question 2: Ubuntu 24.04 (matches the v13
round) vs. the newly-clasm-supported 26.04 LTS.

**Decision.** Ubuntu 26.04 LTS ("resolute").

**Rationale.**
- uv manages the Python 3.14t toolchain independent of whatever Python
  26.04 ships -- the OS-provided Python is not load-bearing for the app
  venv, only for whatever `apt` packages assume a system Python (none of
  the packages in `cloud-init.yaml` currently do).
- clasm v0.0.5 already curates 26.04 arm64 AMIs (Phase 20.35).

**Consequences.**
- 26.04 is less field-tested with this team's own scripts than 24.04 --
  worth a deliberate note if boot issues turn out to be OS-version-
  specific rather than v14/Granian/3.14t-specific.

---

## 2026-07-27 — Free-threaded Python 3.14t: proceed, verify empirically

**Context.** DESIGN.md flagged as a real risk (not yet verified against
RDM's actual resolved dependency tree) whether every C-extension
dependency has a free-threaded-compatible wheel. Checked live against
PyPI's JSON API 2026-07-27: `psycopg2-binary` (invenio-db's `postgresql`
extra dependency) publishes only a regular `cp314` wheel, no `cp314t`
wheel. CPython's free-threaded build re-enables the GIL process-wide
the moment it imports a C extension that doesn't declare free-threading
support -- if that's what happens here, the entire reason for choosing
3.14t is silently defeated, not just degraded.

**Decision.** Proceed with 3.14t as planned; verify empirically rather
than assuming either way. `setup_rdm_granian.bash` runs
`python3 -c "import sys; print(sys._is_gil_enabled())"` inside the
project's uv-managed venv right after `invenio-cli install`, logged to
`/var/log/rdm14-gil-check.log`.

**Rationale.**
- The alternative (falling back to standard, non-free-threaded Python
  3.14 for this round) was raised and explicitly not chosen -- the user's
  call was to test the real thing and observe, not assume ahead of time.
- Recompiling `psycopg2` from source (`libpq-dev` is included in
  `cloud-init.yaml` for this) is available as a thing to try if the GIL
  check comes back re-enabled, but isn't assumed to fix it -- CPython's
  GIL fallback is triggered by whether the extension's module-init
  declares free-threading support, not by whether it was freshly compiled
  from source. Recompiling only helps if `psycopg2`'s own C code already
  supports declaring that; not confirmed either way as of this writing.

**Consequences.**
- If the GIL check comes back `False` (re-enabled), the follow-up
  decision (fall back to standard Python 3.14, try recompiling
  `psycopg2`, or try `psycopg` v3 instead -- which currently has no
  Python 3.14 wheels of any kind on PyPI, checked same day, so would also
  need a from-source build) is deferred until that result is in hand.
- Don't treat "it booted" as confirmation that free-threading is
  actually active -- the GIL check log is the thing to look at, not just
  whether the service came up.

---

## 2026-07-27 — Free-threaded Python 3.14t: tried, abandoned this round

**Context.** Continuation of the entry above -- the empirical result is
now in hand. Two real gaps were found and worked around live on the
instance: `psycopg2-binary`/`psycopg-binary` (invenio-db's and
commonmeta-py's DB driver wheels) and `orjson`/`orjsonl`
(commonmeta-py's JSON library) all lack `cp314t` wheels. Worked around
via a config shared by a TU Wien colleague (relayed via Tom, cross-
checked against PyPI live before adopting): `psycopg2`/`psycopg[c]`
added as explicit source-buildable dependencies, `psycopg-binary`/
`psycopg2-binary`/`orjson`/`orjsonl` excluded via `[tool.uv]
exclude-dependencies`, and a small local shim (`orjson_fallback.py` +
`.pth` file, adapted from TU Wien's `invenio-config-tuw` pattern rather
than depending on that package directly) registering `ujson` (which does
have `cp314t` wheels) as a substitute for `orjson` at interpreter
startup. All of this got the app installing and building successfully.

Then the actual, deeper answer surfaced: after `invenio-cli install`
completed, `sys._is_gil_enabled()` inside a fully-loaded app
(`invenio_app.factory.create_app()`) returned `False` -- confirmed live
2026-07-27. The cause, visible directly in `invenio-cli install`'s own
output: SQLAlchemy 2.0.51's bundled `sqlalchemy.cyextension.collections`
re-enables the GIL process-wide the moment it's imported, which happens
as soon as the app (any Flask/SQLAlchemy request) loads. SQLAlchemy does
publish a `cp314t`-tagged wheel (confirmed via PyPI) -- but shipping a
wheel built against the free-threaded ABI is not the same as the C code
declaring itself thread-safe via `Py_mod_gil`. Without that declaration,
CPython conservatively re-enables the GIL regardless of the wheel tag.

**Decision.** Abandon free-threaded Python 3.14t for this round; use
standard (GIL-enabled) Python 3.14 instead. Drop the psycopg2/psycopg[c]
source-build workaround and the orjson fallback shim entirely --
standard 3.14 has normal prebuilt wheels for `psycopg2-binary`,
`psycopg-binary`, and `orjson`, so none of that complexity is needed.
Drop the GIL-check step from `setup_rdm_granian.bash` -- no longer a
meaningful test once we're not attempting free-threading.

**Rationale.**
- The psycopg2/orjson gaps were "no compatible artifact exists yet for
  cp314t" -- fixable by avoiding the artifact. The SQLAlchemy finding is
  a different, deeper category: the artifact exists and loads fine, it
  just hasn't been audited/declared thread-safe. That's an ecosystem-
  maturity question dependent on upstream SQLAlchemy (and likely other
  C-extension dependencies in this stack -- psycopg-c itself,
  cryptography, lxml, etc. were never individually confirmed, since
  SQLAlchemy's cyextension loads first and flips the GIL back on before
  any of them get a chance to matter) doing that work, not something
  fixable through our own dependency configuration.
- Continuing to run 3.14t with the GIL forced back on has no real upside
  over standard 3.14 for this app -- no multi-core parallelism is
  actually achieved, while the free-threading-specific workarounds add
  real fragility (a live install already went through several rounds of
  breakage working through them) for zero realized benefit.
- The current live instance is being kept as-is (already installed and
  working, GIL-enabled-anyway) -- this decision applies to the
  reproducible artifact (`cloud-init.yaml`) for future re-provisions, not
  a mandate to redo the current instance's work.

**Consequences.**
- Revisit 3.14t once SQLAlchemy (and ideally a broader survey of this
  stack's other C-extension dependencies) actually declare free-threading
  safety, not just ship `cp314t`-tagged wheels -- check this fresh each
  time, since wheel-tag presence alone (as this round demonstrated) is
  not a reliable signal of actual thread-safety.
- `cloud-init.yaml`'s `database`/`search` keys (see PLAN.md/DESIGN.md) and
  the npm `legacy-peer-deps`/nvm-`.bashrc`-persistence fixes found during
  this same live-testing pass are unrelated to the free-threading
  question and apply regardless of which Python variant is used.

---

## 2026-07-27 — `invenio-cli` enhancement scope and location

**Context.** DESIGN.md's "Follow-on: operability hardening" identified
two gaps in upstream `invenio-cli`'s `run_all()`: no Granian option for
the dev web process, and no output labeling across the concurrently
running web/worker/beat processes. Needed to settle scope before writing
PLAN.md's steps.

**Decision.** Do both — add a Granian-backed dev runner option *and*
labeled/prefixed process output — in a vendored patched copy of
`local.py` kept inside this repo (`granian-rdm-v14`), not a fresh fork of
`inveniosoftware/invenio-cli`.

**Rationale.**
- Both gaps block the same underlying goal (comfortable single-command
  dev iteration for this project specifically) and touch the same file,
  so splitting them into separate rounds would add process overhead
  without a corresponding benefit.
- Vendoring first lets the change get exercised against this project's
  actual daily use before committing to fork-and-PR ceremony (branch
  naming, CI, review) upstream. If it proves out, extracting it to a real
  fork for a PR is a small follow-up, not a redo.

**Consequences.**
- The vendored copy will drift from upstream `invenio-cli` as that
  project releases new versions; re-diff against upstream `main`
  periodically rather than assuming the vendored copy stays current.
- Because upstreaming is the eventual intent, the implementation and its
  tests should still follow `invenio-cli`'s own contribution conventions
  (test style, docstrings, changelog entry format) from the start, so the
  eventual extraction-to-fork step is a copy, not a rewrite.

---

## 2026-08-17 — Cookiecutter scaffold source: switch `master` → `v14.0` branch

**Context.** DESIGN.md's 2026-08-17 update found that
`cookiecutter-invenio-rdm`'s `master` branch — `setup_rdm_granian.bash`'s
default `TEMPLATE_VERSION` — now pins `invenio-app-rdm~=15.0.0b2.dev0`
(commit `5707760`, 2026-08-06), not the clean v14 target it was on
2026-07-24 when `master` was originally chosen (no version-numbered v14
branch existed then — branches stopped at `v13.0`). Needed to settle a
scaffold source before bumping this repo's own RDM pin to GA `14.0.0`.

**Decision.** Change `TEMPLATE_VERSION`'s default from `"master"` to
`"v14.0"` — a real, version-numbered branch, confirmed live to now exist
(it does not appear in the branch list fetched on 2026-07-24, but does
today).

**Rationale.**
- Checked `v14.0`'s actual template content directly, not assumed: pins
  `invenio-app-rdm~=14.0.0` (a compatible-release match satisfied by GA
  `14.0.0` outright — no forced downgrade needed, unlike scaffolding from
  `master`), `requires-python ~=3.14.0` (matches this project's existing
  standard-Python-3.14 decision, unchanged), and `cookiecutter.json`
  still omits `database`/`search` keys (PLAN.md Step 7's `.invenio`
  sed-patch workaround is unaffected either way).
- `uwsgi`/`uwsgitop`/`uwsgi-tools` are present on `v14.0` too — confirmed
  this is not new or specific to `master`'s v15 move (present
  continuously back through at least commit `67b230cc7c`, 2026-04-01,
  `~=14.0.0b9.dev0`); the existing `sed -i '/"uwsgi/d' pyproject.toml`
  strip step in `setup_rdm_granian.bash` already handles it and needs no
  change. Not a factor in this decision either way.
- Rejected staying on `master`: would scaffold for a different major
  version (v15) and immediately fight it via a forced downgrade, rather
  than matching the template to the target version like `v13.0` did for
  the previous round.
- Rejected pinning to a bare commit SHA (`ffd3d86c22`, the last `master`
  commit before the v15 bump, itself pinning `~=14.0.0rc4`) once `v14.0`
  was confirmed to exist as a real branch: a version-numbered branch is
  more legible, matches this project's own `v13.0` precedent, and is
  more likely to receive any v14.0.x-line fixes upstream backports to it
  than a frozen commit would.

**Consequences.**
- `setup_rdm_granian.bash`'s `TEMPLATE_VERSION` default changes from
  `"master"` to `"v14.0"` in both `cloud-init.yaml` and
  `cloud-init-multipass.yaml` — still overridable via the existing
  second positional argument.
- `v14.0` is a branch, not an immutable tag — it could itself move if
  upstream backports land on it. Re-check it hasn't drifted before
  reusing this decision much later, same "verify live, don't assume"
  discipline as every other grounding fact in this repo.
- Doesn't change the free-threaded-Python decision, the uwsgi-strip
  step, or the `.invenio` database/search patch — all independently
  confirmed unaffected by this switch.
