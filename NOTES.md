
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
