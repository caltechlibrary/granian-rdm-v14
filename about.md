---
title: granian-rdm-v14
abstract: |-
  Robert's experiment bringing up Invenio RDM v14 under Granian instead of uWSGI/Gunicorn, provisioned on AWS via clasm and locally via Multipass, managed via uv. Free-threaded Python 3.14t was tried and abandoned (SQLAlchemy's own bundled C extension re-enables the GIL process-wide); runs on standard Python 3.14 instead. v0.0.5: re-pinned to invenio-app-rdm 14.0.0 GA (cookiecutter-invenio-rdm's new v14.0 branch), live-verified end to end -- including reboot-survivable systemd hardening -- on both AWS EC2 and Multipass.
authors:
  - family_name: Doiel
    given_name: R. S.
    id: https://orcid.org/0000-0003-0900-6903



repository_code: https://github.com/caltechlibrary/granian-rdm-v14
version: 0.0.5
license_url: https://caltechlibrary.github.io/granian-rdm-v14/LICENSE


keywords:
  - Invenio RDM
  - AWS
  - Granian
  - clasm
  - free-threaded Python

date_released: 2026-08-17
---

About this software
===================

## granian-rdm-v14 0.0.5

Re-pinned invenio-app-rdm to 14.0.0 GA (was 14.0.0rc2/rc3) via cookiecutter-invenio-rdm's new v14.0 branch, since master has moved on to targeting v15 betas. Fixed a silent drift between cloud-init.yaml and cloud-init-multipass.yaml (RDM pin, Node version) with a new verify_cloud_init_sync.bash regression check, and settled the vendored invenio-cli dev-runner patch's AWS/Multipass split as permanent by design. Live-verified end to end on both AWS EC2 and Multipass, including two reboot cycles on each platform.

## Authors

- [R. S. Doiel](https://orcid.org/0000-0003-0900-6903)






Robert's experiment bringing up Invenio RDM v14 under Granian instead of uWSGI/Gunicorn, provisioned on AWS via clasm and locally via Multipass, managed via uv. Free-threaded Python 3.14t was tried and abandoned (SQLAlchemy's own bundled C extension re-enables the GIL process-wide); runs on standard Python 3.14 instead. v0.0.5: re-pinned to invenio-app-rdm 14.0.0 GA (cookiecutter-invenio-rdm's new v14.0 branch), live-verified end to end -- including reboot-survivable systemd hardening -- on both AWS EC2 and Multipass.

- [License](https://caltechlibrary.github.io/granian-rdm-v14/LICENSE)
- [Code Repository](https://github.com/caltechlibrary/granian-rdm-v14)
  - [Issue Tracker](https://github.com/caltechlibrary/granian-rdm-v14/issues)









