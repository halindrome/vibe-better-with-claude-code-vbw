#!/usr/bin/env bash
set -u

# model-tier-down.sh — return the model one tier below the given model.
#
# Implements the prover-verifier asymmetry used by the optional
# `review_model_downgrade` config flag: a phase's review/QA runs one tier below
# its build model so the verifier is cheaper than the builder. The ladder is:
#
#   opus -> sonnet -> haiku   (haiku is the floor — it never drops further)
#
# Usage: model-tier-down.sh <model>
#   model: opus|sonnet|haiku
# Returns: stdout = the downgraded model; exit 0.
# Errors:  stderr = error message, exit 1 (unknown/empty model).

case "${1:-}" in
  opus)
    echo "sonnet"
    ;;
  sonnet)
    echo "haiku"
    ;;
  haiku)
    echo "haiku"
    ;;
  *)
    echo "Invalid model '${1:-}'. Valid: opus, sonnet, haiku" >&2
    exit 1
    ;;
esac
