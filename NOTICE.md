# Notice

This repository contains software under more than one license. This file
exists because that wasn't documented anywhere before 2026-08-17 -- see
NOTES.md's 2026-08-17 entry.

## This repository's own content

The cloud-init YAML files, shell scripts (`setup_rdm_granian.bash`,
`verify_rdm_boot.bash`, `wait_for_rdm_services.bash`,
`verify_cloud_init_sync.bash`), and documentation (`README.md`,
`DESIGN.md`, `PLAN.md`, `DECISIONS.md`, `NOTES.md`) in this repository are
original work, Copyright (c) 2026, Caltech, licensed under the terms in
[LICENSE](LICENSE) (BSD-3-Clause, "Caltech" variant).

## Invenio RDM itself is separately licensed -- not redistributed here

This repository provisions and configures [Invenio
RDM](https://github.com/inveniosoftware/invenio-app-rdm) --
`invenio-app-rdm`, `invenio-cli`, and the scaffold produced by
`cookiecutter-invenio-rdm` -- but does not vendor or redistribute their
source. The cloud-init scripts install these packages from PyPI/GitHub at
instance boot time, the same as any other dependency `pip`/`uv` would
fetch. Invenio RDM and its component projects are developed by the
[Invenio community](https://github.com/inveniosoftware) (CERN,
Northwestern University, TU Wien, Graz University of Technology, and
others) and are separately licensed under the **MIT License** -- Caltech's
copyright and license terms above do not apply to Invenio RDM itself.

## Exception: vendored `invenio-cli` files

[`vendor/invenio_cli/`](vendor/invenio_cli/) is the one place this
repository does redistribute third-party source: two files
(`commands/local.py`, `cli/cli.py`) copied from `invenio-cli==1.11.0` and
patched to add a `--runner granian` dev-server option (see `DESIGN.md`'s
"Follow-on: operability hardening" and `DECISIONS.md`'s 2026-07-27
entry for why this was vendored rather than forked). Those two files
remain under their original MIT license and copyright (CERN, Northwestern
University, TU Wien, Graz University of Technology, Forschungszentrum
Jülich GmbH) -- see each file's own header comment and
[`vendor/invenio_cli/LICENSE`](vendor/invenio_cli/LICENSE) for the full
text. Caltech's addition is limited to the specific patch (the `runner`
parameter and labeled-output plumbing described in `PLAN.md` Step 6's
diff-vs-upstream note), not the files as a whole.
