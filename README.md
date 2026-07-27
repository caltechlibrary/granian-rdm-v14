
# Granian/RDM v14 experimental repository

Robert's experiment bringing up Invenio RDM v14 (latest release candidate)
under [Granian](https://github.com/emmett-framework/granian) instead of
uWSGI/Gunicorn, provisioned on AWS via
[clasm](https://github.com/caltechlibrary/clasm), running on free-threaded
Python 3.14t via `uv`.

This follows on from
[gunicorn-rdm-v13](https://github.com/caltechlibrary/gunicorn-rdm-v13), a
separate, already-concluded local-dev experiment comparing Gunicorn and
Granian on RDM v13. That question is considered answered; this repository
is scoped to v14, Granian only, on AWS, not a local Docker Compose setup.

See [DESIGN.md](DESIGN.md) for the full problem statement, scope decisions,
and grounding facts. An implementation plan (PLAN.md) follows once the
open questions in DESIGN.md are resolved.
