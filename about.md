---
title: granian-rdm-v14
abstract: |-
  Robert's experiment bringing up Invenio RDM v14 (latest release candidate) under Granian instead of uWSGI/Gunicorn, provisioned on AWS via clasm, managed via uv. Free-threaded Python 3.14t was tried and abandoned (SQLAlchemy's own bundled C extension re-enables the GIL process-wide); runs on standard Python 3.14 instead. v0.0.1: proof of concept live-verified end to end, including reboot-survivable systemd hardening.
authors:
  - family_name: Doiel
    given_name: R. S.
    id: https://orcid.org/0000-0003-0900-6903



repository_code: https://github.com/caltechlibrary/granian-rdm-v14
version: 0.0.3
license_url: https://caltechlibrary.github.io/granian-rdm-v14/LICENSE


keywords:
  - Invenio RDM
  - AWS
  - Granian
  - clasm
  - free-threaded Python

date_released: 2026-07-28
---

About this software
===================

## granian-rdm-v14 0.0.3

Fixed cloud-init.yaml size issue with AWS launch templates

## Authors

- [R. S. Doiel](https://orcid.org/0000-0003-0900-6903)






Robert's experiment bringing up Invenio RDM v14 (latest release candidate) under Granian instead of uWSGI/Gunicorn, provisioned on AWS via clasm, managed via uv. Free-threaded Python 3.14t was tried and abandoned (SQLAlchemy's own bundled C extension re-enables the GIL process-wide); runs on standard Python 3.14 instead. v0.0.1: proof of concept live-verified end to end, including reboot-survivable systemd hardening.

- [License](https://caltechlibrary.github.io/granian-rdm-v14/LICENSE)
- [Code Repository](https://github.com/caltechlibrary/granian-rdm-v14)
  - [Issue Tracker](https://github.com/caltechlibrary/granian-rdm-v14/issues)









