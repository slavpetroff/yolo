#!/usr/bin/env bash
set -e

# Delegate to the Rust CLI
exec yolo token-baseline "$@"
