#!/usr/bin/env bats
# R180 (P129; docs/guards.md): while a loop is on in the project, the Bash
# guard denies for every caller, the main session included: git push in any
# form, gh release, gh pr create, npm publish, cargo publish, twine upload, gem
# push, docker push, and the deploy commands of vercel, netlify, fly, heroku
# and wrangler. Each denial says the loop never leaves the project and names
# /vbw:loop stop; every text is pinned here. Outside a loop today's rules stand
# (a plain git push by the user stays allowed). The guard's cost in that case
# is measured by the hook bench (its limit is the release run's verdict). L1.

load helper
load loop-helper

setup() {
  loop_project
  VBW_SESSION_ID=s1 "$VBW" loop start T1 --no-ceiling > /dev/null
}
teardown() { vbw_teardown; }

bash_call() {
  jq -nc --arg c "$1" --arg d "$PROJECT" --argjson x "${2:-null}" '{hook_event_name: "PreToolUse", session_id: "s1", tool_name: "Bash", cwd: $d, tool_input: {command: $c}} + $x' \
    | vbw_hook PreToolUse Bash
}
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }
denied() { [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]; }

# text WHAT VERB: the pinned denial.
text() {
  printf 'VBW guard: the loop never leaves the project: %s is not run while a loop is on\nNext: wait for the loop to end, or stop it with /vbw:loop stop, then %s yourself' "$1" "$2"
}

# denied_as COMMAND WHAT VERB
denied_as() {
  run bash_call "$1"
  denied || { echo "not denied: $1 -> $output"; return 1; }
  [ "$(reason)" = "$(text "$2" "$3")" ] || { printf '%s ->\n%s\nexpected:\n%s\n' "$1" "$(reason)" "$(text "$2" "$3")"; return 1; }
}

@test "R180: under a loop every form of git push is denied for the main session and for agents" {
  denied_as 'git push' 'git push' 'push'
  denied_as 'git push origin main' 'git push' 'push'
  denied_as 'git push --tags' 'git push' 'push'
  denied_as 'git push -u origin feature' 'git push' 'push'
  denied_as 'git -C . push' 'git push' 'push'
  denied_as 'sh -c "git push"' 'git push' 'push'
  denied_as 'echo "$(git push)"' 'git push' 'push'
  run bash_call 'git push' '{"agent_type": "dev"}'
  denied
}

@test "R180: under a loop releases, publishes and deploys are denied with their pinned texts" {
  denied_as 'gh release create v1.0.0' 'gh release' 'release'
  denied_as 'gh pr create --fill' 'gh pr create' 'open the pull request'
  denied_as 'npm publish' 'npm publish' 'publish'
  denied_as 'cargo publish' 'cargo publish' 'publish'
  denied_as 'twine upload dist/*' 'twine upload' 'upload'
  denied_as 'gem push pkg.gem' 'gem push' 'push'
  denied_as 'docker push registry/app:1' 'docker push' 'push'
  denied_as 'vercel' 'vercel deploy' 'deploy'
  denied_as 'vercel --prod' 'vercel deploy' 'deploy'
  denied_as 'vercel deploy' 'vercel deploy' 'deploy'
  denied_as 'netlify deploy --prod' 'netlify deploy' 'deploy'
  denied_as 'fly deploy' 'fly deploy' 'deploy'
  denied_as 'flyctl deploy' 'flyctl deploy' 'deploy'
  denied_as 'heroku container:push web' 'heroku container:push' 'deploy'
  denied_as 'heroku container:release web' 'heroku container:release' 'deploy'
  denied_as 'wrangler deploy' 'wrangler deploy' 'deploy'
  denied_as 'wrangler publish' 'wrangler publish' 'deploy'
  denied_as 'npx wrangler deploy' 'wrangler deploy' 'deploy'
}

@test "R180: the words in text, reads and the project's own commands stay allowed under a loop" {
  local c
  for c in 'git commit -m "docs: never git push during the loop"' 'echo "npm publish later"' 'git log origin/main..HEAD' 'gh pr view 12' 'gh release list' \
           'npm test' 'cargo build' 'docker build .' 'vbw prove' 'git fetch origin' 'git pull --ff-only'; do
    run bash_call "$c"
    [ -z "$output" ] || { echo "denied: $c -> $output"; false; }
  done
}

@test "R180: the denial holds when the guard reads the record instead of the glance, and ends with the loop" {
  rm -f .vbw/runtime/glance.json
  denied_as 'git push' 'git push' 'push'
  edit_record '.loop.ended = {at: "2026-10-12T22:00:00Z", reason: "end of the list"}'
  run bash_call 'git push'
  [ -z "$output" ] || { echo "denied after the loop ended: $output"; false; }
}

@test "R180: outside a loop today's rules stand: a plain git push, a pull request and a publish stay allowed" {
  edit_record 'del(.loop)'
  local c
  for c in 'git push' 'git push origin main' 'gh pr create --fill' 'npm publish' 'vercel --prod'; do
    run bash_call "$c"
    [ -z "$output" ] || { echo "denied without a loop: $c -> $output"; false; }
  done
  run bash_call 'git push --force'
  denied
}

@test "R180: the hook bench measures the guard with a loop on" {
  run env VBW_HOOK_BUDGET_MS=100000 VBW_STATUSLINE_BUDGET_MS=100000 VBW_BENCH_RUNS=1 bash "$REPO_ROOT/tools/bench-hooks.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^guard \(loop\): -?[0-9.]+ ms own CPU per call' || { echo "$output"; false; }
}

@test "R180 (F164): git's global options with their value as the next word hide no push: --git-dir, --work-tree, --namespace" {
  denied_as 'git --git-dir .git push' 'git push' 'push'
  denied_as 'git --work-tree . push origin main' 'git push' 'push'
  denied_as 'git --namespace x push' 'git push' 'push'
  denied_as 'git --git-dir=.git push' 'git push' 'push'
  denied_as 'git -C . --git-dir .git push' 'git push' 'push'
}

@test "R180 (F165): heroku pipelines:promote is denied with its pinned text" {
  denied_as 'heroku pipelines:promote -a app' 'heroku pipelines:promote' 'deploy'
}

@test "R180 (F175): an option's value or a toolchain word before the subcommand hides nothing: cargo +nightly publish, npm --tag next publish, docker --context x push, gh -R a/b release create" {
  denied_as 'cargo +nightly publish' 'cargo publish' 'publish'
  denied_as 'npm --tag next publish' 'npm publish' 'publish'
  denied_as 'docker --context x push img:1' 'docker push' 'push'
  denied_as 'gh -R a/b release create v1' 'gh release' 'release'
  denied_as 'gh --repo a/b pr create --fill' 'gh pr create' 'open the pull request'
  denied_as 'wrangler --env prod deploy' 'wrangler deploy' 'deploy'
}
