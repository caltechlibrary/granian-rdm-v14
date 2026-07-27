
# Notes

## 2026-07-27

Repository created, split out from the RDM v14/Granian design work that had
been living as `granian-rdm-v14-design.md` at the `~/WorkLab` root (moved
here as `DESIGN.md`). Kept separate from `gunicorn-rdm-v13` since that
repository's scope (RDM v13, Gunicorn, local Docker Compose dev) is a
different, already-concluded question from this one (RDM v14, Granian,
AWS via `clasm`, free-threaded Python 3.14t).

Next step: resolve DESIGN.md's four open questions (architecture,
AMI/Ubuntu release, Granian tuning model, nothing further to relocate) and
write the implementation plan (PLAN.md).

## 2026-07-27 (later) -- operability follow-on scoped

Bring-up itself is done (see PLAN.md Steps 1-5). Two follow-on problems
scoped and written up (DESIGN.md "Follow-on: operability hardening",
DECISIONS.md, PLAN.md Steps 6-7): a vendored `invenio-cli` `local.py`
patch (Granian dev runner option + labeled process output, test-first
against `invenio-cli`'s own test conventions) and systemd reboot
hardening for the production units (test-first via a `verify_rdm_boot.bash`
acceptance script, since there's no pytest-equivalent for systemd units).
Not yet implemented -- PLAN.md Steps 6/7 are the next work.

## 2026-07-27 (later still) -- Step 6 code/docs done, not yet wired into cloud-init

Vendored `invenio_cli/commands/local.py` and `invenio_cli/cli/cli.py` from
the real `invenio-cli==1.11.0` PyPI release (confirmed byte-identical
before patching), added a `--runner flask|granian` option end-to-end
(`invenio-cli run web`/`run all` -> `LocalCommands.run_web`/`run_all`) plus
`[web]`/`[worker]`/`[beat]` labeled output, all test-first (red confirmed
before each implementation, green after). 12 new/changed tests passing,
14 pre-existing upstream legacy skips untouched. Verified in a throwaway
venv (`pip install invenio-cli==1.11.0` + symlink the vendored files over
the installed package) -- see README.md for the exact recipe. Full
diff-vs-upstream note lives in PLAN.md Step 6.

Explicitly NOT done yet: applying this to `cloud-init.yaml` /
`setup_rdm_granian.bash` so a freshly provisioned instance actually gets
the patch, and trying it against a real EC2 instance. That's the next
piece of Step 6 item 4, deliberately paused for a check-in before editing
the live provisioning script.

## 2026-07-27 (later still) -- Step 6 fully wired into cloud-init.yaml

User confirmed: wire it in, goal is a colleague running `clasm` + this
`cloud-init.yaml` gets the dev-runner patch with zero manual steps.
Added: `apply_invenio_cli_patch.bash` (new `write_files` entry, called
from `install_rdm_toolchain.bash` right after `uv tool install
"invenio-cli==1.11.0"` -- switched from `>=` to an exact pin since the
patch overwrites files by copy, not diff), plus the two patched files
embedded verbatim as `write_files` entries under
`/usr/local/share/invenio-cli-patch/`. Confirmed programmatically that
the embedded copies are byte-identical to the tested
`vendor/invenio_cli/` files (no manual-transcription drift). Ran a full
local simulation of the real deploy path (parsed the actual YAML,
force-reinstalled a clean `invenio-cli==1.11.0` via `uv tool install`,
ran the extracted `apply_invenio_cli_patch.bash` unmodified, confirmed
`invenio-cli run web --help` shows `--runner [flask|granian]` for real)
and ran `shellcheck` against both new/changed scripts (clean). Cleaned up
the local `uv tool`-installed `invenio-cli` afterward so this Mac is left
as found. Also updated `setup_rdm_granian.bash`'s printed instructions to
lead with `invenio-cli run all --runner granian` as the recommended dev
workflow.

Not yet done: a real EC2 boot exercising this path end-to-end (only
verified locally so far). Also separately raised by the user: interest
in a local Multipass variant of this same `cloud-init.yaml` for
day-to-day dev on a Mac Mini instead of AWS -- noted as a candidate
follow-on, not started.
