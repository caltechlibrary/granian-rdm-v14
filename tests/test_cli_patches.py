# -*- coding: utf-8 -*-
#
# Copyright (C) 2026 California Institute of Technology.
#
# Invenio-Cli is free software; you can redistribute it and/or modify it
# under the terms of the MIT License; see LICENSE file for more details.

"""Tests for the vendored --runner CLI wiring (granian-rdm-v14 PLAN.md Step 6).

Upstream invenio-cli has no working unit-level tests for the `run` command
group as of v1.11.0 (tests/test_cli.py's own tests are skip-marked and
reference a `cli` name that doesn't exist in this module -- confirmed dead).
These tests are written fresh against the vendored `cli.py`, following the
same CliRunner + mock-the-collaborators style click itself recommends,
since there's no existing working pattern here to match.
"""

from unittest.mock import MagicMock, patch

import pytest
from click.testing import CliRunner

from invenio_cli.cli import invenio_cli
from invenio_cli.helpers.cli_config import CLIConfig


class FakeCLIConfig(CLIConfig):
    """A CLIConfig stand-in that skips real `.invenio` file I/O."""

    def __init__(self):
        """Constructor -- deliberately skips CLIConfig.__init__'s file reads."""

    def get_web_host(self):
        """Return a fixed dev host."""
        return "127.0.0.1"

    def get_web_port(self):
        """Return a fixed dev port."""
        return 5000


@pytest.fixture()
def cli_runner():
    """Click CLI runner."""
    return CliRunner()


@patch("invenio_cli.cli.cli.ServicesCommands")
@patch("invenio_cli.cli.cli.LocalCommands")
def test_run_web_default_runner_is_flask(p_local_commands, p_services, cli_runner):
    """No --runner given -> defaults to "flask" (backward compatible)."""
    mock_commands = MagicMock()
    mock_commands.run_web.return_value = []
    p_local_commands.return_value = mock_commands

    result = cli_runner.invoke(
        invenio_cli, ["run", "web", "--no-services"], obj=FakeCLIConfig()
    )

    assert result.exit_code == 0, result.output
    mock_commands.run_web.assert_called_once_with(
        host="127.0.0.1", port="5000", debug=True, runner="flask"
    )


@patch("invenio_cli.cli.cli.ServicesCommands")
@patch("invenio_cli.cli.cli.LocalCommands")
def test_run_web_granian_runner_option(p_local_commands, p_services, cli_runner):
    """--runner granian reaches LocalCommands.run_web."""
    mock_commands = MagicMock()
    mock_commands.run_web.return_value = []
    p_local_commands.return_value = mock_commands

    result = cli_runner.invoke(
        invenio_cli,
        ["run", "web", "--no-services", "--runner", "granian"],
        obj=FakeCLIConfig(),
    )

    assert result.exit_code == 0, result.output
    mock_commands.run_web.assert_called_once_with(
        host="127.0.0.1", port="5000", debug=True, runner="granian"
    )


@patch("invenio_cli.cli.cli.ServicesCommands")
@patch("invenio_cli.cli.cli.LocalCommands")
def test_run_all_forwards_runner_option(p_local_commands, p_services, cli_runner):
    """`run all --runner granian` forwards runner to LocalCommands.run_all."""
    mock_commands = MagicMock()
    mock_commands.run_all.return_value = []
    p_local_commands.return_value = mock_commands

    result = cli_runner.invoke(
        invenio_cli,
        ["run", "all", "--no-services", "--runner", "granian"],
        obj=FakeCLIConfig(),
    )

    assert result.exit_code == 0, result.output
    _, kwargs = mock_commands.run_all.call_args
    assert kwargs["runner"] == "granian"


def test_run_web_rejects_unknown_runner(cli_runner):
    """An unrecognized --runner value is a click UsageError, not a crash."""
    result = cli_runner.invoke(
        invenio_cli,
        ["run", "web", "--no-services", "--runner", "uwsgi"],
        obj=FakeCLIConfig(),
    )
    assert result.exit_code != 0
