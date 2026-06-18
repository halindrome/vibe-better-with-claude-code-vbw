#!/usr/bin/env bats

load test_helper

run_tier_down() {
  bash "$SCRIPTS_DIR/model-tier-down.sh" "$@"
}

@test "opus downgrades to sonnet" {
  run run_tier_down opus
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "sonnet downgrades to haiku" {
  run run_tier_down sonnet
  [ "$status" -eq 0 ]
  [ "$output" = "haiku" ]
}

@test "haiku is the floor (stays haiku)" {
  run run_tier_down haiku
  [ "$status" -eq 0 ]
  [ "$output" = "haiku" ]
}

@test "rejects an unknown model" {
  run run_tier_down gpt5
  [ "$status" -eq 1 ]
}

@test "rejects a missing argument" {
  run run_tier_down
  [ "$status" -eq 1 ]
}
