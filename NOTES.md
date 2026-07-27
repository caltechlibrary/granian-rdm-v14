
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

## 2026-07-27 (later still) -- Step 7 systemd hardening, static half done

Checked `aws ec2 describe-instances` first: nothing running for this
project, so there was no live box to run the red/green reboot cycle
against, and launching one is a real-cost action on a shared AWS account
-- didn't do that without asking. User is installing `clasm` themselves
to launch one (confirmed installed as of this note).

Did everything gradeable without a live instance: wrote
`wait_for_rdm_services.bash` (ExecStartPre readiness gate -- TCP checks
on Postgres/Redis/RabbitMQ, HTTP check on OpenSearch, ports confirmed
against cookiecutter-invenio-rdm's real `docker-services.yml`, not
guessed) and `verify_rdm_boot.bash` (the actual acceptance script),
both shellcheck-clean, both embedded verbatim in `cloud-init.yaml` and
confirmed byte-identical to their repo-root source copies. Hardened
`rdm`/`rdm_rest`/`rdm_celery` units with `Requires=`/`After=docker.service`
+ the readiness gate + `Restart=on-failure`, added an nginx systemd
drop-in for ordering (didn't edit the packaged unit file directly), and
added a new `rdm.target` grouping all four for single start/stop.
Re-parsed the full YAML afterward to confirm it's still valid with 7
`write_files` entries.

Not done: the actual reboot test. That needs the live instance the user
is about to bring up via `clasm`.

## 2026-07-27 (later still) -- Step 7 live-verified: two clean reboots

User installed `clasm` and launched a real instance
(`i-04a8e45b85019f0b9`, launch template `granian-rdm-v14-test` v2) --
first real boot of this project's revised cloud-init.yaml. Confirmed via
`aws ssm describe-instance-information` that SSM was online, so all of
this was driven directly through `aws ssm send-command`, no SSH needed.

Getting from "instance launched" to "all three `verify_rdm_boot.bash`
checks green" surfaced four real bugs (full writeup in PLAN.md Step 7's
"Real bugs found" section) -- two of them pre-existing and unrelated to
Step 7 itself, just never hit live before:

1. The documented `.invenio` `database`/`search` fix from the original
   bring-up didn't actually work -- cookiecutter's replay context drops
   any key not in the template's own schema, confirmed by diffing the
   generated `.invenio` against the input TOML. Real fix: patch
   `.invenio` directly with `sed` after scaffolding.
2. nginx's site config had a duplicate `listen 80` block colliding with
   the location-bearing block, and the real TLS/443 block had zero
   locations of its own -- meaning HTTPS access (the intended way to
   reach the instance) likely never actually worked on the original
   bring-up either, just never noticed. Fixed by collapsing to two
   server blocks.
3. Even after that, every `/api/*` request 404'd -- the REST-only
   Granian process mounts its blueprints at root, not under `/api`;
   nginx needed a trailing slash on `proxy_pass` to strip the prefix
   (plus an explicit capture group for the regex upload-content
   location, which can't use the trailing-slash trick).
4. `verify_rdm_boot.bash`'s own celery check was broken two ways: ran as
   the wrong user (root can't see `uv` under `/home/ubuntu`), and piped
   into `grep -q`, which triggered a SIGPIPE-vs-pipefail false failure
   even when celery answered correctly.

After all four fixes: two full `sudo reboot` cycles, both came back with
every systemd unit active and no manual intervention -- the actual Step
7 goal. First reboot needed a 45s settle wait (one transient
connection-refused while `rdm_rest` was still binding, self-healed);
second passed clean at 60s. Stopped at two reboots (not three) since the
pattern was consistent and explainable both times.

All fixes applied to both the live instance and `cloud-init.yaml` (and
`verify_rdm_boot.bash`/`wait_for_rdm_services.bash`'s repo-root copies),
verified byte-identical between embedded and source copies each time,
`shellcheck`-clean throughout.

Not done: a third reboot cycle (judged unnecessary); tearing down or
keeping the test instance is the user's call, not done unilaterally.

## 2026-07-27 (later still) -- v0.0.1: proof of concept

Test instance terminated by the user. Bumped `codemeta.json`'s version
0.0.0 -> 0.0.1 and corrected its (and README.md's) description, which
still claimed free-threaded Python 3.14t -- stale since DECISIONS.md's
"tried, abandoned this round" entry. `developmentStatus: concept` left
as-is; it's still accurate for what this is. README.md gained a short
Status section pointing at PLAN.md Step 7's "Real bugs found" writeup.
No git commit/tag/push done here -- that stays the user's own step
([[feedback-no-commits]]). Separately, the user found a real bug in
`clasm` itself while updating the launch template to v2 (sync worked;
the bug is in some other launch-template-update path) -- deferred to
tomorrow, not this repo's concern.
