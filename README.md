
# Granian/RDM v14 experimental repository

Robert's experiment bringing up Invenio RDM v14 under
[Granian](https://github.com/emmett-framework/granian) instead of
uWSGI/Gunicorn, provisioned on AWS via
[clasm](https://github.com/caltechlibrary/clasm) (and, as of 2026-07-28,
also locally via Multipass), managed via `uv`. Free-threaded Python 3.14t
was tried and abandoned (SQLAlchemy's own bundled C extension re-enables
the GIL process-wide, see DECISIONS.md); runs on standard Python 3.14
instead. Pinned to `invenio-app-rdm` 14.0.0 **GA** as of 2026-08-17 (see
DESIGN.md's update and DECISIONS.md for the re-pin and the
`cookiecutter-invenio-rdm` `v14.0` branch switch that went with it).

**Status: v0.0.5.** Pinned to `invenio-app-rdm` 14.0.0 **GA** (scaffolded
from cookiecutter-invenio-rdm's `v14.0` branch), and live-verified end to
end on **both** AWS EC2 and Multipass, including two full `sudo reboot`
cycles on each platform with the app self-healing correctly both times.
`cloud-init.yaml` and `cloud-init-multipass.yaml` are kept in sync on
`RDM_PIN_VERSION`/Node/`TEMPLATE_VERSION` by a standing regression check
(`verify_cloud_init_sync.bash`) after those drifted apart undetected for
three weeks -- see NOTES.md's 2026-08-17 entries for the full account,
including two real bugs found along the way that turned out to be
environment/tooling issues (a Multipass daemon crash on guest reboot, an
SSM `ssm-user`-vs-`ubuntu` `PATH` gap) rather than anything wrong with
this repo's cloud-init files. See PLAN.md Step 7's "Real bugs found
during Step 7's live verification" for the original (2026-07-27) live
pass's findings (a stale `.invenio` workaround, a broken nginx config,
an `/api` proxy-prefix bug).

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

**This patch is wired into `cloud-init-multipass.yaml` only, by design
(decided 2026-08-17, see DECISIONS.md) -- not a gap to fill in on
AWS.** It was originally dropped from `cloud-init.yaml` on 2026-07-28 to
fit under AWS's 16384-byte user-data limit, but the split turns out to
match how the two platforms are actually used regardless of that limit:
`cloud-init.yaml` provisions a production-shaped topology (systemd
units, nginx TLS proxy) that never calls `invenio-cli run` at all, while
`cloud-init-multipass.yaml` exists specifically as the local dev
iteration loop this patch was written for. A fresh AWS instance from
this repo intentionally does not get `invenio-cli run --runner granian`.

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

## License

This repository's own scripts and documentation are Copyright (c) 2026,
Caltech, under [LICENSE](LICENSE) (BSD-3-Clause). **Invenio RDM itself is
separately licensed and is not covered by that license** -- `invenio-app-rdm`,
`invenio-cli`, and `cookiecutter-invenio-rdm` are MIT-licensed projects of
the [Invenio community](https://github.com/inveniosoftware), installed by
this repo's cloud-init scripts at boot time rather than redistributed
here. The one exception is the vendored `invenio-cli` patch above, which
retains its original MIT license (`vendor/invenio_cli/LICENSE`). See
[NOTICE.md](NOTICE.md) for the full breakdown.
