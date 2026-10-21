#!/usr/bin/env bats
# R149, as an engineering rule: no shipped shell code (plugin/bin, plugin/lib,
# plugin/hooks, plugin/scripts) passes record-sized data to jq as a
# command-line argument. tools/check-record-args.sh DIR... reads every
# non-comment line of the shell files under DIR and fails, naming FILE:LINE,
# when jq gets, through --arg, --argjson or --args/--jsonargs:
# - the record: record_read, a cat or git show of record.json, or a variable
#   named record;
# - a value derived from the whole record: qa_combined, qa_digests, qa_state
#   or qa_cache_read, or a variable named digests or results;
# - a list that grows with the project: a variable named units, causes or
#   TF_REUSE (Linux caps one argument at 128 KB, about 3,000 test files);
# - a positional parameter that the function's header comment
#   ("# name ARG...: ...") names RECORD, RECORD_JSON, DIGESTS, RESULTS or UNITS.
# A here-string (<<<) of such data is refused too: bash writes it to a file in
# the system's temporary folder. A pipe (printf '%s' "$record" | jq), --slurpfile
# and --rawfile from a file inside the project are the ways in; a process
# substitution handed to --slurpfile or --rawfile is one when nothing inside it
# (a jq --arg..., a here-string) takes the data as an argument. The self-tests
# plant each violation in a copy and show the rule catches it. L1.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

rule() { bash "$REPO_ROOT/tools/check-record-args.sh" "$@"; }

# planted LINE...: a directory holding one shell file with LINES, after a
# header comment; prints the directory.
planted() {
  local d
  d=$(mktemp -d "$TEST_ROOT/plant.XXXXXX")
  {
    printf '#!/usr/bin/env bash\n# A planted file.\n\n'
    printf '%s\n' "$@"
  } > "$d/cmd-plant.sh"
  printf '%s\n' "$d"
}

@test "R149: no shipped shell line passes record-sized data to jq as a command-line argument" {
  run rule "$PLUGIN_ROOT/bin" "$PLUGIN_ROOT/lib" "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/scripts"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R149 self-test: the rule catches the record passed with --argjson or --arg" {
  local line
  for line in \
    'out=$(jq -n --argjson r "$record" '"'"'$r.phases'"'"')' \
    'jq -n --arg r "$(record_read)" '"'"'$r'"'"'' \
    'jq -nr --arg r "$(cat "$VBW_RECORD")" '"'"'$r'"'"'' \
    'jq -n --argjson r "$(git show HEAD:.vbw/record.json)" '"'"'$r'"'"'' \
    'record_update '"'"'.x = $c'"'"' --argjson c "$record"' \
    'jq -n '"'"'$ARGS.positional'"'"' --jsonargs "$record"' \
    '    --arg at "$at" --argjson r "${record}" \' \
    'jq -c '"'"'.phases'"'"' <<< "$record"'; do
    run rule "$(planted "$line")"
    [ "$status" -ne 0 ] || { echo "not caught: $line"; false; }
    [[ "$output" == *"cmd-plant.sh:4"* ]] || { echo "not named with its line: $line"; echo "$output"; false; }
  done
}

@test "R149 self-test: the rule catches values derived from the whole record" {
  local line
  for line in \
    'jq -n --argjson cur "$(qa_combined "$record")" '"'"'$cur'"'"'' \
    '  --arg at "$(vbw_now)" --argjson cur "$(qa_combined "$record" "$digests" | jq -c .)"' \
    'jq -n --argjson d "$(qa_digests "$record")" '"'"'$d'"'"'' \
    'jq -n --argjson s "$(qa_state "$record")" '"'"'$s'"'"'' \
    'jq -n --argjson c "$(qa_cache_read)" '"'"'$c'"'"'' \
    'jq -n --argjson d "$digests" '"'"'$d'"'"'' \
    'jq -n --argjson r "$results" '"'"'$r'"'"'' \
    'jq -c . <<< "$(qa_digests "$record")"'; do
    run rule "$(planted "$line")"
    [ "$status" -ne 0 ] || { echo "not caught: $line"; false; }
    [[ "$output" == *"cmd-plant.sh:4"* ]] || { echo "not named with its line: $line"; echo "$output"; false; }
  done
}

@test "R149 self-test: the rule catches the lists that grow with the project: units, causes and TF_REUSE" {
  local line
  for line in \
    'jq -nc --arg h "$head" --argjson u "$units" '"'"'{units: $u}'"'"'' \
    'size=$(jq -nc --argjson u "${units}" '"'"'{units: $u}'"'"')' \
    'jq -n --arg c "$causes" '"'"'$c | split("\n")'"'"'' \
    'jq -n --argjson r "$TF_REUSE" '"'"'$r | length'"'"'' \
    '    --argjson own "$own" --arg causes "$causes" \' \
    'jq -c '"'"'map_values(.at)'"'"' <<< "$TF_REUSE"' \
    'done <<< "$causes"'; do
    run rule "$(planted "$line")"
    [ "$status" -ne 0 ] || { echo "not caught: $line"; false; }
    [[ "$output" == *"cmd-plant.sh:4"* ]] || { echo "not named with its line: $line"; echo "$output"; false; }
  done
  local d
  d=$(planted \
    'printf '"'"'%s'"'"' "$units" | jq -c --arg h "$head" '"'"'{units: .}'"'"'' \
    'printf '"'"'%s'"'"' "$TF_REUSE" | jq -c '"'"'map_values(.at)'"'"'' \
    'jq -n --rawfile causes <(printf '"'"'%s'"'"' "$causes") '"'"'$causes'"'"'' \
    'done < <(printf '"'"'%s\n'"'"' "$causes")' \
    'jq -n --argjson unitsize 3 --arg causes_file "$f" '"'"'$unitsize'"'"'')
  run rule "$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R149 self-test: the rule catches a function's UNITS parameter passed to jq" {
  local d
  d=$(planted \
    '# plant_begin TOTAL [UNITS]: a planted helper.' \
    'plant_begin() {' \
    '  jq -nc --argjson n "${2:-null}" --argjson t "$1" '"'"'{units: $n}'"'"'' \
    '}')
  run rule "$d"
  [ "$status" -ne 0 ] || { echo "not caught"; false; }
  [[ "$output" == *"cmd-plant.sh:6"* ]] || { echo "$output"; false; }
}

@test "R149 self-test: the rule catches a function's record parameter passed to jq or in a here-string" {
  local d
  d=$(planted \
    '# plant_combined RECORD [DIGESTS]: a planted helper.' \
    'plant_combined() {' \
    '  jq -c --argjson r "$1" '"'"'$r.phases'"'"' <<< "{}"' \
    '}' \
    '# plant_pass RECORD RESULTS HASH: another.' \
    'plant_pass() {' \
    '  jq -n --argjson x "$2" --arg h "$3" '"'"'$x'"'"'' \
    '}' \
    '# plant_state RECORD_JSON: a third.' \
    'plant_state() {' \
    '  jq -c -f "$VBW_LIB/qa.jq" <<< "$1"' \
    '}')
  run rule "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cmd-plant.sh:6"* ]] || { echo "$output"; false; }
  [[ "$output" == *"cmd-plant.sh:10"* ]] || { echo "$output"; false; }
  [[ "$output" == *"cmd-plant.sh:14"* ]] || { echo "$output"; false; }
  [[ "$output" != *"cmd-plant.sh:4"* && "$output" != *"cmd-plant.sh:8"* ]] || { echo "$output"; false; }
}

@test "R149 self-test: a process substitution handed to --slurpfile or --rawfile passes only when nothing in it takes the data as an argument" {
  local d line
  # printf is the shell's own: the data goes into the pipe, never onto a command line.
  d=$(planted \
    '# plant_fps RECORD KEYS: a planted helper.' \
    'plant_fps() {' \
    '  jq -n -j --argjson d "$VBW_COMMAND_TIMEOUT" --slurpfile rec <(printf '"'"'%s'"'"' "$1") --slurpfile keys <(printf '"'"'%s'"'"' "$2") '"'"'$rec'"'"'' \
    '}' \
    'jq -n --arg id "$id" --rawfile t <(printf '"'"'%s'"'"' "$record") '"'"'$t'"'"'')
  run rule "$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # jq inside the substitution is a program of its own: the record on its command line is caught.
  for line in \
    'jq -n --arg id "$id" --slurpfile r <(jq -n --argjson x "$record" '"'"'$x'"'"') '"'"'$r'"'"'' \
    'jq -n --argjson n 1 --rawfile r <(jq -rn --arg x "$(record_read)" '"'"'$x'"'"') '"'"'$r'"'"'' \
    'jq -n --arg id "$id" --slurpfile r <(jq -c . <<< "$record") '"'"'$r'"'"''; do
    run rule "$(planted "$line")"
    [ "$status" -ne 0 ] || { echo "not caught: $line"; false; }
    [[ "$output" == *"cmd-plant.sh:4"* ]] || { echo "not named with its line: $line"; echo "$output"; false; }
  done
}

@test "R149 self-test: standard input, --slurpfile, --rawfile, small values and comments pass the rule" {
  local d
  d=$(planted \
    'printf '"'"'%s'"'"' "$record" | jq -r '"'"'.milestone.id'"'"'' \
    'jq -n --slurpfile r <(printf '"'"'%s'"'"' "$record") '"'"'$r[0].phases'"'"'' \
    'jq -n --rawfile t "$VBW_RUNTIME/record.copy" '"'"'$t'"'"'' \
    'jq -n --argjson n "$steps" --arg id "$1" --arg at "$(vbw_now)" '"'"'$n'"'"'' \
    'jq -n --arg mode "$(printf '"'"'%s'"'"' "$record" | jq -r '"'"'.settings.rigor // "auto"'"'"')" '"'"'$mode'"'"'' \
    'jq -r '"'"'.id'"'"' <<< "$plan"' \
    '# jq -n --argjson r "$record" is how it must never be done' \
    '# plant_show ID [FLAG]: a helper of small values.' \
    'plant_show() {' \
    '  jq -n --arg id "$1" --arg f "$2" '"'"'$id'"'"'' \
    '}')
  run rule "$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
