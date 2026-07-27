# Implementation Plan: provisioning via clasm

Step-by-step walkthrough for using `clasm` to prepare the EC2 instance,
following DESIGN.md's proposed approach and DECISIONS.md's resolved
choices (arm64/Graviton, Ubuntu 26.04 LTS, standard Python 3.14 --
free-threaded 3.14t was tried and abandoned this round, see DECISIONS.md).
`cloud-init.yaml` (this directory) is the file referenced throughout.

**Status (2026-07-27): the first live provision is done and working**
(services started successfully) -- but it took several rounds of manual
live-debugging to get there, all of which are now folded back into
`cloud-init.yaml` so a *fresh* instance shouldn't need them. This plan
reflects the corrected process, not the exact sequence that was actually
typed the first time around.

## Step 1 -- IAM role + instance profile

In clasm's domain picker, choose **IAM**, then:

1. **Create Role from Template** -> **RDM Repository Instance**. This
   template already bundles `AmazonSSMManagedInstanceCore` (required --
   clasm enforces an SSM-capable instance profile at launch, Phase 20.33)
   plus scoped S3 read/write on one backup-bucket ARN.
   - This round's cloud-init uses local file storage, not S3 (see
     DESIGN.md non-goals) -- the S3 grant isn't exercised yet, but this is
     still the right template to use (built for exactly this use case,
     and keeps the door open for adding S3 later without a new role).
   - Supply a bucket ARN when prompted -- reuse an existing snapshot/test
     bucket if one exists, or provide the account's general backup bucket.
     It's unused until S3 storage is wired in.
   - Tag with `Origin` per your team's convention (see clasm's
     Configuration domain if `origin_tag` isn't already set).
2. Confirm the role + instance profile were created (**Show Roles** /
   **Show Instance Profile Detail**).

## Step 2 -- Launch the instance

In **Compute**, choose **Create EC2 instance from cloud-init YAML**:

1. **Cloud-init file**: point at
   `~/WorkLab/granian-rdm-v14/cloud-init.yaml`.
2. **AMI**: pick the curated Ubuntu 26.04 LTS **arm64** entry.
3. **Instance type**: filtered to arm64/Graviton once the AMI is picked
   (Phase 20.35) -- `m6g.2xlarge` is the Graviton equivalent of
   production's `m7i-flex.2xlarge` (not a strict requirement, adjust if
   needed).
4. **EBS root volume size**: this round has no real snapshot data loaded
   (non-goal, see DESIGN.md) -- a modest size (e.g. 60-80GB) covers
   Postgres + OpenSearch Docker volumes for demo-fixture data. Size up
   later if real data gets loaded.
5. **IAM instance profile**: pick the one created in Step 1 -- the picker
   is pre-filtered to SSM-capable profiles only (Phase 20.33).
6. **Security group**: restricted/non-public, matching this project's
   established convention for non-production comparison instances (see
   `[[project-granian-vs-gunicorn-rdm]]`'s v13-round notes) -- this is an
   internal instance, not a public endpoint.
7. Launch, then confirm `cloud-init status --wait` reaches `status: done`
   (via SSM shell, or SSH once the security group allows it) before
   moving on -- `install_rdm_toolchain.bash` runs automatically via
   `runcmd` and must finish (uv install, Python 3.14 install, `invenio-cli`
   install, Node 22 install, nvm `.bashrc` wiring) before Step 3.

## Step 3 -- Scaffold RDM (manual, not automatic)

SSH (or SSM Session Manager) into the instance as `ubuntu` -- a **fresh**
shell session, not a leftover one from before `install_rdm_toolchain.bash`
finished, so `.bashrc`'s nvm loader line is picked up -- then:

```bash
/usr/local/bin/setup_rdm_granian.bash
```

This runs to completion unattended once started -- but run it
interactively rather than backgrounding it the first time, so any
failure is visible immediately rather than needing a log dig afterward.
Defaults to instance name `rdm14-granian`, template `master`, RDM pin
`14.0.0rc2` -- override via positional args if needed.

**Real bugs found via the first live run, now fixed in `cloud-init.yaml`
(watch for these regressing if the script is edited again):**
1. `database`/`search` keys must be supplied in the cookiecutter config
   toml even though `master`'s `cookiecutter.json` no longer prompts for
   them -- `invenio-cli` 1.11.0 (latest release) still does a bare
   `.invenio` config lookup with no default for both, which fails at
   `invenio-cli services start` time (not scaffold time), with a
   `KeyError: 'database'`. See DECISIONS.md and the comment above the
   cookiecutter config heredoc in `cloud-init.yaml`.
2. `invenio-assets`' own `package.json` has an internal peer-dependency
   conflict (`@rspack/core` vs `@rspack/cli`) that fails `npm install`
   under strict-by-default npm 10 unless `npm config set
   legacy-peer-deps true` is set first -- unrelated to anything specific
   to this project. Now set automatically before scaffolding.
3. nvm installed via `git clone` (not its own installer) never wired
   itself into `.bashrc` -- any interactive shell after the one that ran
   `install_rdm_toolchain.bash` wouldn't have `node`/`npm` on `PATH`,
   surfacing as `FileNotFoundError: npm` deep inside `invenio-cli
   install`'s webpack step. Now appended to `.bashrc` automatically.

**Watch for, in order, on a fresh run:**
1. `uv add "invenio-app-rdm[opensearch2]==14.0.0rc2"` and
   `invenio-cli install` completing without dependency-resolution errors
   (the uwsgi-package strip is the one known risk point remaining --
   unrelated packages, unrelated to Python version, see `cloud-init.yaml`'s
   header comment).
2. `invenio-cli install` completing with `Dependencies installed
   successfully.`
3. `invenio-cli services setup` completing (Postgres/OpenSearch/Redis
   containers up, demo data loaded).

## Step 4 -- Start and smoke-test

```bash
cd /Sites/rdm14-granian
invenio-cli services start
sudo systemctl start rdm_celery rdm_rest rdm nginx
```

Since the security group isn't public, reach the instance via an SSH
tunnel (`ssh -L 8443:localhost:443 ubuntu@<instance>`) or SSM port
forwarding, then browse `https://localhost:8443` (self-signed cert --
expect a browser warning, same as the v13 round). Confirm the UI loads,
demo records are present, and the REST API (`/api/records`) responds.

## Step 5 -- After a working baseline

Not part of this initial bring-up, per DESIGN.md's proposed approach:

- Granian worker/thread tuning exploration (`--runtime-threads`/
  `--runtime-blocking-threads` only matter if free-threading is
  reattempted later -- see DECISIONS.md; for standard Python 3.14, the
  v13 uWSGI-matched counts are the more relevant baseline to tune from)
  -- only once the instance boots and smoke-tests cleanly.
- Real snapshot data / S3 storage / production-scale sizing -- explicitly
  deferred (DESIGN.md non-goals).
- Revisiting free-threaded Python 3.14t once SQLAlchemy (and this stack's
  other C-extension dependencies) actually declare free-threading safety
  -- see DECISIONS.md's "tried, abandoned this round" entry for what to
  re-check before trying again.

## Step 6 -- invenio-cli dev runner enhancement (TDD)

**Status (2026-07-27): all of items 1-5 done and verified end-to-end
locally** (red-green: 12 new/changed tests passing, 14 pre-existing
legacy skips untouched; README usage docs done; this diff-vs-upstream
note done). Item 4 ("wire in") is now real, not just planned:
`cloud-init.yaml` embeds the two patched files verbatim (byte-identical
to `vendor/invenio_cli/`, checked programmatically) plus a new
`apply_invenio_cli_patch.bash` that `install_rdm_toolchain.bash` now
calls right after `uv tool install "invenio-cli==1.11.0"`. Verified as a
full simulated deploy -- clean `uv tool install --force
invenio-cli==1.11.0` -> run the exact extracted script -> confirmed
`invenio-cli run web --help` shows `--runner [flask|granian]` for real,
and `shellcheck` passes clean on both new/changed scripts. **Not yet
verified against an actual EC2 instance** -- only against a local `uv
tool install` on this Mac (cleaned up afterward). First real instance
boot is the remaining validation step.

Scope and location per DECISIONS.md's 2026-07-27 entry: vendored patch to
`local.py`, Granian runner option + labeled output, developed test-first
against `invenio-cli`'s own test conventions.

1. **Vendor the target file.** Copy the current
   `invenio_cli/commands/local.py` from the pinned `invenio-cli` release
   into this repo (e.g. `vendor/invenio_cli/commands/local.py`), plus its
   companion test file `tests/commands/test_local.py` ->
   `tests/test_local_patches.py`, matching upstream's fixture
   (`mock_cli_config`) and mocking style (`@patch` on `popen`/`run_cmd`)
   exactly so a later upstream PR is close to a straight copy.
2. **Red: write the failing tests first.**
   - `test_run_web_granian_runner`: call `run_web(..., runner="granian")`,
     patch `local.popen`, assert the command list invokes
     `granian --interface wsgi invenio_app.wsgi_ui:application ...`
     rather than `invenio run`.
   - `test_run_web_flask_runner_default`: no `runner` argument ->
     asserts the existing `invenio run ...` command, unchanged --
     regression guard, since backward compatibility is the whole point of
     staying upstreamable.
   - `test_run_all_labels_output`: refactor the Popen calls behind a
     small seam (e.g. `_labeled_popen(label, cmd)`) *in the test first* by
     asserting it's called with `"web"`/`"worker"`/`"beat"` labels, before
     that helper exists.
   - Run the suite (`pytest tests/test_local_patches.py`) and confirm
     every new test fails for the *expected* reason (missing
     `runner`/`_labeled_popen`), not an import error or fixture typo.
3. **Green: implement against the vendored copy** until the new tests
   pass without breaking any of the copied pre-existing tests (run the
   full copied `test_local_patches.py`, not just the new cases).
4. **Wire in.** `cloud-init.yaml` now embeds both patched files verbatim
   (new `write_files` entries at `/usr/local/share/invenio-cli-patch/`)
   and a new `apply_invenio_cli_patch.bash`
   (`/usr/local/bin/apply_invenio_cli_patch.bash`) that
   `install_rdm_toolchain.bash` runs right after `uv tool install
   "invenio-cli==1.11.0"` -- exact pin, not `>=`, since the patch is a
   file *copy*, not a diff, and only matches the exact release it was
   diffed from. The apply script locates the tool's isolated venv via
   `uv tool dir`, copies the two files over the installed package, then
   fails the provision loudly (not silently at first dev use) if
   `LocalCommands.run_web` doesn't actually gain a `runner` parameter
   afterward. `setup_rdm_granian.bash`'s final instructions now lead with
   `invenio-cli run all --runner granian` as the recommended dev
   workflow, ahead of the systemd/production commands.
5. **Document.** Add usage notes (flag, defaults, output-labeling format)
   to this repo's `README.md` so other developers know what changed vs.
   stock `invenio-cli`, and keep a running diff-vs-upstream note here in
   PLAN.md for whoever eventually extracts this to a fork/PR.

### Diff vs. upstream `invenio-cli==1.11.0` (update as this evolves)

Two files patched, both additive (new optional params/options, defaults
preserve stock behavior exactly):

- **`invenio_cli/commands/local.py`**
  - `run_web(self, host, port, debug=True, runner="flask")` -- new
    `runner` param. `runner="flask"` is byte-for-byte the original
    command; `runner="granian"` builds
    `granian --interface wsgi invenio_app.wsgi_ui:application --host
    <host> --port <port> --ssl-certificate docker/nginx/test.crt
    --ssl-keyfile docker/nginx/test.key` instead. Unrecognized values
    raise `ValueError` (defense in depth -- the CLI layer's
    `click.Choice` should already reject these before this is reached).
  - `run_all(self, ..., runner="flask")` -- forwards `runner` to
    `run_web`; unchanged otherwise.
  - New `_labeled_popen(self, label, command, env=None)` and
    `_echo_labeled_output(self, label, proc)` -- `run_web`, `run_worker`,
    and `run_jobs_scheduler` now go through `_labeled_popen` (label
    `"web"`/`"worker"`/`"beat"` respectively) instead of calling `popen`
    directly, so concurrent output is prefixed instead of interleaved
    unlabeled. Uses a daemon `Thread` per process to read and echo
    `stdout` (merged with `stderr` via `STDOUT`) line-by-line.
- **`invenio_cli/cli/cli.py`**
  - `web_options` gains a `--runner` `click.Choice(["flask", "granian"])`
    option, default `"flask"`.
  - `run web` and `run all` commands now accept and forward `runner` to
    the corresponding `LocalCommands` call. `run worker` is untouched
    (doesn't use `web_options`). The bare `invenio-cli run` (no
    subcommand, backward-compat path via `ctx.forward(run_all)`) picks up
    `--runner` automatically since it shares `web_options`.

Tests: `tests/test_local_patches.py` (vendored `tests/commands/test_local.py`
+ 6 new/changed tests) and `tests/test_cli_patches.py` (new file -- upstream
has no working test coverage at this layer to extend; see that file's
module docstring for why). Run via the venv recipe in README.md.

**Remaining:** the wiring above was verified end-to-end in a *local*
simulation (extract the exact `write_files` content from `cloud-init.yaml`
via a real YAML parse, force-reinstall a clean `invenio-cli==1.11.0` with
`uv tool install`, run the extracted `apply_invenio_cli_patch.bash`
verbatim, confirm `invenio-cli run web --help` really shows `--runner
[flask|granian]`, `shellcheck` clean on both scripts) -- but not yet
against a real EC2 instance. First real boot via `clasm` is the
remaining validation step; watch for it in PLAN.md Step 4's smoke-test.

## Step 7 -- systemd reboot hardening (test-first, adapted for infra)

There's no interpreter to unit-test a systemd unit file or cloud-init
YAML against in isolation the way pytest exercises Python -- the
test-first equivalent here is an executable **acceptance script** that
encodes the boot criteria before any unit file is touched, run against a
real reboot (red), then iterated on until it passes reliably (green).

1. **Red: write `verify_rdm_boot.bash` first**, encoding the acceptance
   criteria as assertions, before editing any systemd unit:
   - `systemctl is-active docker rdm rdm_rest rdm_celery nginx` all
     report `active`.
   - `curl -sk https://localhost/api/records` returns HTTP 200 within a
     bounded timeout.
   - `celery --app invenio_app.celery inspect ping` gets a worker
     response.
   - All of the above hold immediately after `sudo reboot` -- not just
     after a manual `systemctl start` sequence.
   Run it against the current (unhardened) instance right after a reboot
   to confirm it actually fails today -- this documents the real bug
   instead of an assumed one.
2. **Green: harden the units** in `cloud-init.yaml`'s systemd-unit-writing
   section (lines ~369-427):
   - Add `Requires=docker.service` + `After=docker.service` to `rdm`,
     `rdm_rest`, `rdm_celery`.
   - Add an `ExecStartPre` readiness loop (`pg_isready`, plus a TCP check
     for OpenSearch/RabbitMQ) before each unit's `ExecStart` -- a
     container reporting "started" isn't the same as the service
     accepting connections.
   - Order `nginx` `After=rdm.service rdm_rest.service`.
   - Group all four under one new `rdm.target`
     (`Wants=rdm.service rdm_rest.service rdm_celery.service nginx.service`)
     so start/stop/reboot is one unit, not four.
3. **Re-run `verify_rdm_boot.bash` across 2-3 real reboots**, not just
   once -- ordering races are often intermittent, so a single green run
   doesn't prove reliability.
4. **Keep `verify_rdm_boot.bash` in the repo** as a standing regression
   check for any future edit to `cloud-init.yaml`'s unit section.
