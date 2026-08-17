
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

## 2026-08-17 -- doc catch-up: reconciling undocumented 07-28 work + v14 GA

Resumed this project after ~3 weeks. Before touching anything for v14 GA,
checked the repo's actual state against `git log` rather than trusting
these docs, since `NOTES.md`/`DESIGN.md`/`DECISIONS.md`/`PLAN.md` all
stopped mid-day on 2026-07-27 while `git log` showed four more commits
that same evening (07-28), none of them written up anywhere:
`release v0.0.2`, `fixed cloud init size issue`, `fixed init size and
cleanup`, `Added path.repo and confirmed /Sites setting`, `prep 0.0.4`.
`codemeta.json` is at `version: "0.0.4"`; every prose doc still describes
a `v0.0.1` proof-of-concept.

What that undocumented work actually did, confirmed via `git log --stat`
and grepping both cloud-init files directly (not assumed from commit
messages):

1. **`cloud-init.yaml` (AWS) hit AWS's 16384-byte user-data limit.**
   Fixed by deleting the vendored `invenio-cli --runner granian` patch's
   `write_files` entries (`apply_invenio_cli_patch.bash` and the two
   patched files under `/usr/local/share/invenio-cli-patch/`) --755 lines
   removed. `cloud-init.yaml` no longer applies that patch at all.
2. **`cloud-init-multipass.yaml` was never touched by the size fix**
   (Multipass has no user-data size limit) -- it still carries the full
   vendored patch, `apply_invenio_cli_patch.bash` and all.
3. Somewhere in the same session, `cloud-init.yaml`'s `RDM_PIN_VERSION`
   default was bumped `14.0.0rc2` -> `14.0.0rc3` and its Node version
   bumped `22` -> `26`. **`cloud-init-multipass.yaml` was not bumped for
   either** -- it's still `14.0.0rc2` / Node `22`.
4. The one change that *did* land in both files identically: the
   OpenSearch `path.repo` fix (`Added path.repo and confirmed /Sites
   setting`) -- confirmed byte-identical between the two files' relevant
   sections.

Net result: `cloud-init.yaml` and `cloud-init-multipass.yaml`, which
`README.md` and prior notes describe as "kept in sync," have silently
diverged on three real axes (RDM pin, Node version, invenio-cli patch
presence) and only stayed in sync on the fourth (path.repo). This wasn't
caught because nothing in the repo checks it -- next up (Phase 3 of the
current plan) is a small acceptance script to make that divergence loud
instead of silent, the same pattern `verify_rdm_boot.bash` already uses
for the systemd-hardening work.

Separately, verified live against GitHub/PyPI today: `invenio-app-rdm`
14.0.0 is now the actual GA release (PyPI `info.version` == `14.0.0`,
classified Production/Stable; GitHub tags run
`rc3 -> rc4 -> rc5 -> rc6 -> v14.0.0`, three RCs past whatever this repo
last pinned to). Upstream has already moved on to v15 betas
(`v15.0.0b0.dev0` through `v15.0.0b3.dev0` all tagged), and
`cookiecutter-invenio-rdm`'s `master` branch -- the template
`setup_rdm_granian.bash` scaffolds from -- now pins
`invenio-app-rdm~=15.0.0b2.dev0` (commit `5707760`, 2026-08-06). That
specific version-target change wasn't true when DESIGN.md's "Grounding
facts" were last checked (2026-07-24/27) -- `master` cleanly tracked v14
pre-releases back then. (`uwsgi`/`uwsgitop`/`uwsgi-tools` being in the
template is *not* new, though -- DESIGN.md's original 2026-07-24
grounding facts already noted that; don't blame the v15 bump for it.)
This is a new open question, not just a version-string bump; see
DECISIONS.md's next entry.

Next: DECISIONS.md entry on which cookiecutter source to scaffold from
for a clean v14 GA instance (Phase 2 of the current plan), then the
sync-fix acceptance script (Phase 3).

## 2026-08-17 (later) -- Phase 2 decided, Phase 3+5 merged and done

Phase 2: confirmed live that a `v14.0` cookiecutter-invenio-rdm branch
now exists (it didn't on 2026-07-27) and pins `~=14.0.0` cleanly --
DECISIONS.md's newest entry switches `TEMPLATE_VERSION`'s default to it.
Also caught and corrected an overstated claim from the first catch-up
pass above: `uwsgi`/`uwsgitop`/`uwsgi-tools` were never "reintroduced" by
the v15 move on `master` -- they've been in the template continuously
since at least `b9.dev0` (2026-04-01), which this repo's own original
2026-07-24 grounding facts already said.

Phase 3+5 (merged -- see below for why): wrote `verify_cloud_init_sync.bash`
first, confirmed a genuine red (Node 26 vs 22, RDM_PIN_VERSION rc3 vs
rc2; TEMPLATE_VERSION happened to already agree at "master"). First
draft used `grep -oP`, which fails on this Mac's BSD `grep` (no `-P`
support) -- rewrote using portable `sed -E` before trusting the red
result. Then fixed both `cloud-init.yaml` and `cloud-init-multipass.yaml`
directly to the final decided values (`TEMPLATE_VERSION=v14.0`,
`RDM_PIN_VERSION=14.0.0`, Node 26) rather than syncing to an
already-known-stale intermediate value first -- merging what the
original plan called Phase 3 (sync) and Phase 5 (GA bump) into one edit,
since splitting them would mean touching the same lines twice for no
benefit. Re-ran `verify_cloud_init_sync.bash` (green), `yq eval '.'` on
both files (parse clean), and `bash -n` against every embedded
`write_files` script in both files individually (all pass; confirmed via
`bash -n`, not just "the YAML parses").

Also checked, since AWS's 16384-byte user-data limit is exactly what
forced last round's removal of the vendored `invenio-cli` patch from
`cloud-init.yaml`: today's comment-text growth brought `cloud-init.yaml`
to 14613 bytes gzip+base64-encoded (clasm's actual encoding pipeline),
up from an unmeasured-but-presumably-smaller prior state, leaving only
~1770 bytes of headroom under the limit. Not a problem today, but tight
enough to watch on any future edit to this file -- flagging here rather
than assuming margin exists.

`shellcheck` isn't installed on this Mac -- skipped it for
`verify_cloud_init_sync.bash`, same as it's unavailable for anything
else in this repo when working locally; `bash -n` was run instead
everywhere shellcheck would normally also run.

Next: Phase 4 -- decide and document (DECISIONS.md) whether the
AWS-vs-Multipass split on the vendored `invenio-cli --runner granian`
patch is the permanent intended state, or worth reworking given how
little headroom `cloud-init.yaml` now has.

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
