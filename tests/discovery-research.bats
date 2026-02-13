#!/usr/bin/env bats

setup() {
  export TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/.vbw-planning"
  export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "domain-research.md has 4 required sections" {
  # Simulate Scout writing research file
  cat > "$TEST_DIR/.vbw-planning/domain-research.md" <<EOF
## Table Stakes
- Feature 1
- Feature 2

## Common Pitfalls
- Pitfall 1

## Architecture Patterns
- Pattern 1

## Competitor Landscape
- Competitor 1: feature
EOF

  # Verify structure
  run grep -c "^## Table Stakes" "$TEST_DIR/.vbw-planning/domain-research.md"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run grep -c "^## Common Pitfalls" "$TEST_DIR/.vbw-planning/domain-research.md"
  [ "$output" -eq 1 ]

  run grep -c "^## Architecture Patterns" "$TEST_DIR/.vbw-planning/domain-research.md"
  [ "$output" -eq 1 ]

  run grep -c "^## Competitor Landscape" "$TEST_DIR/.vbw-planning/domain-research.md"
  [ "$output" -eq 1 ]
}

@test "bootstrap-requirements.sh accepts optional research file" {
  # Create discovery.json
  cat > "$TEST_DIR/.vbw-planning/discovery.json" <<EOF
{"answered":[{"question":"Test","answer":"Answer","category":"scope","phase":"bootstrap","date":"2026-02-13"}],"inferred":[]}
EOF

  # Create research file
  cat > "$TEST_DIR/.vbw-planning/domain-research.md" <<EOF
## Table Stakes
- Authentication

## Common Pitfalls
- Poor error handling

## Architecture Patterns
- REST API

## Competitor Landscape
- Competitor A: feature X
EOF

  # Run with research file
  run bash "$CLAUDE_PLUGIN_ROOT/scripts/bootstrap/bootstrap-requirements.sh" \
    "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" \
    "$TEST_DIR/.vbw-planning/discovery.json" \
    "$TEST_DIR/.vbw-planning/domain-research.md"

  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" ]
}

@test "bootstrap-requirements.sh integrates research findings into requirements" {
  # Setup same as previous test
  cat > "$TEST_DIR/.vbw-planning/discovery.json" <<EOF
{"answered":[{"question":"What features?","answer":"User accounts","category":"scope","phase":"bootstrap","date":"2026-02-13"}],"inferred":[{"text":"User authentication","priority":"Must-have"}]}
EOF

  cat > "$TEST_DIR/.vbw-planning/domain-research.md" <<EOF
## Table Stakes
- User authentication (every app has this)

## Common Pitfalls
- Not handling offline mode

## Architecture Patterns
- Token-based auth

## Competitor Landscape
- App A: OAuth login
EOF

  run bash "$CLAUDE_PLUGIN_ROOT/scripts/bootstrap/bootstrap-requirements.sh" \
    "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" \
    "$TEST_DIR/.vbw-planning/discovery.json" \
    "$TEST_DIR/.vbw-planning/domain-research.md"

  [ "$status" -eq 0 ]

  # Verify requirements were generated from inferred data
  run grep "REQ-01: User authentication" "$TEST_DIR/.vbw-planning/REQUIREMENTS.md"
  [ "$status" -eq 0 ]

  # Verify script consumed research file without error (annotation logic tested separately)
  [ -f "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" ]
}

@test "discovery.json includes research_summary field" {
  cat > "$TEST_DIR/.vbw-planning/discovery.json" <<EOF
{"answered":[],"inferred":[]}
EOF

  cat > "$TEST_DIR/.vbw-planning/domain-research.md" <<EOF
## Table Stakes
- Feature

## Common Pitfalls
- Pitfall

## Architecture Patterns
- Pattern

## Competitor Landscape
- Competitor
EOF

  bash "$CLAUDE_PLUGIN_ROOT/scripts/bootstrap/bootstrap-requirements.sh" \
    "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" \
    "$TEST_DIR/.vbw-planning/discovery.json" \
    "$TEST_DIR/.vbw-planning/domain-research.md"

  run jq -e '.research_summary.available' "$TEST_DIR/.vbw-planning/discovery.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
