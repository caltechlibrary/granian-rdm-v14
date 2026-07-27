
# Granian/RDM v14 experimental repository

Robert's experiment bringing up Invenio RDM v14 (latest release candidate)
under [Granian](https://github.com/emmett-framework/granian) instead of
uWSGI/Gunicorn, provisioned on AWS via
[clasm](https://github.com/caltechlibrary/clasm), managed via `uv`.
Free-threaded Python 3.14t was tried and abandoned (SQLAlchemy's own
bundled C extension re-enables the GIL process-wide, see DECISIONS.md);
runs on standard Python 3.14 instead.

**Status: v0.0.1, proof of concept.** Bring-up (PLAN.md Steps 1-5), the
vendored `invenio-cli` dev-runner patch (Step 6), and systemd reboot
hardening (Step 7) are all live-verified against a real EC2 instance --
including two full `sudo reboot` cycles with zero manual intervention.
See PLAN.md Step 7's "Real bugs found during Step 7's live verification"
for what that live pass caught and fixed (a stale `.invenio` workaround,
a broken nginx config that meant HTTPS access likely never worked before,
and an `/api` proxy-prefix bug).

This follows on from
[gunicorn-rdm-v13](https://github.com/caltechlibrary/gunicorn-rdm-v13), a
separate, already-concluded local-dev experiment comparing Gunicorn and
Granian on RDM v13. That question is considered answered; this repository
is scoped to v14, Granian only, on AWS, not a local Docker Compose setup.

See [DESIGN.md](DESIGN.md) for the full problem statement, scope decisions,
and grounding facts. See [PLAN.md](PLAN.md) for the implementation plan,
including Step 6/7's operability follow-on work, and [DECISIONS.md](DECISIONS.md)
for the choices made along the way.

## `invenio-cli` dev runner patch (vendored)

`vendor/invenio_cli/` holds a small, additive patch on top of stock
`invenio-cli==1.11.0`, adding a `--runner` option to `invenio-cli run`
(default unchanged: `flask`) plus labeled `[web]`/`[worker]`/`[beat]`
process output. See DESIGN.md's "Follow-on: operability hardening" and
DECISIONS.md's 2026-07-27 entry for why this is vendored rather than
forked, and PLAN.md Step 6 for the full diff-vs-upstream tracking note.

**Usage, once applied over an installed `invenio-cli==1.11.0`:**

```bash
# Default -- unchanged from stock invenio-cli:
invenio-cli run web

# Dev server via Granian instead of Flask's built-in dev server --
# matches this project's production runtime:
invenio-cli run web --runner granian
invenio-cli run all --runner granian   # web + worker + beat, one command
```

Concurrent process output is now prefixed (`[web] ...`, `[worker] ...`,
`[beat] ...`) so `invenio-cli run all`'s previously-interleaved logs are
readable.

**Applying the patch** (until/unless this is upstreamed as a real PR):
copy `vendor/invenio_cli/commands/local.py` and `vendor/invenio_cli/cli/cli.py`
over the corresponding files in the installed `invenio-cli` package (find
its location with `python -c "import invenio_cli, os;
print(os.path.dirname(invenio_cli.__file__))"`).

**Running the vendored test suite:**

```bash
python3 -m venv /tmp/invenio-cli-test-venv
/tmp/invenio-cli-test-venv/bin/pip install "invenio-cli==1.11.0" pytest
# Symlink (or copy) the vendored files over the installed package, then:
cd tests && /tmp/invenio-cli-test-venv/bin/python -m pytest -q \
    test_local_patches.py test_cli_patches.py
```
