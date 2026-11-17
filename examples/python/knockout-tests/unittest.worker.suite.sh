#!/usr/bin/env bash
# Runs the project's unittest tests with knockout (one process, fork per test).
cd "$(dirname "$0")/.." && exec knockout python3-unittest discover -s tests -t . "$@"
