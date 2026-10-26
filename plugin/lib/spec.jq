# Parse .vbw/spec.md (docs/proof.md). Input: the file as one string (jq -Rs).
# Output: {requirements: [{id, proof, text}], commands, errors: [..], end: N}
# where end is the line after which a new requirement belongs (null: no
# Requirements section), and commands is {name: argv} from the Commands section
# ("- name: words" or "- name: [\"json\", \"array\"]"), or null without one,
# and results is the Test results section's folders of saved test results
# ("- <folder>/": relative, no "." or "..", outside .vbw/, "/" added when
# missing), or null when the spec names none,
# and leave_out is the Clean copy section's [{path, line}] of git-ignored paths
# the proof's clean copy leaves out ("- <path>", kept as written), or null
# without that section,
# and test_files is the Test files section's {run, files} ("- run: <argv>" naming
# {file} exactly once; "- files: <git pathspecs>", any number of lines), or null
# without that section.

def heading: test("^#{1,2}\\s");
# The argv of one command line: a JSON array of strings, or words split on spaces.
def argv_of: if startswith("[") then (try fromjson catch null)
  | if type == "array" and length > 0 and all(.[]; type == "string" and length > 0) then . else null end
  else [splits("\\s+") | select(length > 0)] end;
# The number of times "{file}" appears in an argv.
def file_slots: [.[] | [match("\\{file\\}"; "g")] | length] | add;
# A results folder as given, with its trailing "/", or null when it is unsafe.
# True when a clean copy path is unsafe: absolute, an empty, "." or ".." segment, or under .vbw or .git.
def bad_leave_out: (rtrimstr("/") | split("/")) as $s
  | startswith("/") or any($s[]; . == "" or . == "." or . == "..") or ($s[0] == ".vbw" or $s[0] == ".git");
def folder_of: (if endswith("/") then . else . + "/" end) as $f
  | ($f | rtrimstr("/") | split("/")) as $s
  | if startswith("/") or any($s[]; . == "" or . == "." or . == "..") or $s[0] == ".vbw" then null else $f end;

split("\n") | map(sub("\r$"; ""))
| reduce to_entries[] as $e (
    {in: false, seen: false, comment: false, reqs: [], errors: [], end: null, cmds: false, commands: null, res: false, results: [], tf: false, tfline: null, test_files: null, cc: false, leave_out: null};
    ($e.value) as $l | ($e.key + 1) as $n
    | if .comment then .comment = ($l | test("-->") | not)
      elif $l | test("^\\s*<!--") then .comment = ($l | test("-->") | not)
      elif $l | heading then
        .in = ($l | test("^##\\s+Requirements\\s*$"))
        | .cmds = ($l | test("^##\\s+Commands\\s*$"))
        | .res = ($l | test("^##\\s+Test results\\s*$"; "i"))
        | .tf = ($l | test("^##\\s+Test files\\s*$"; "i"))
        | .cc = ($l | test("^##\\s+Clean copy\\s*$"; "i"))
        | if .cc then .leave_out = (.leave_out // []) else . end
        | if .tf then .tfline = $n | .test_files = (.test_files // {run: null, files: []}) else . end
        | if .cmds and .commands == null then .commands = {} else . end
        | if .in then .seen = true | .end = $n else . end
      elif .cmds and ($l | test("^[-*+]\\s")) then
        ($l | [capture("^- (?<name>[A-Za-z0-9_-]+): +(?<cmd>\\S.*?)\\s*$")] | first) as $m
        | ($m.cmd // "" | argv_of) as $a
        | if $m == null or $a == null then
            .errors += ["line \($n): expected '- name: command' (words, or a JSON array of strings), got: \($l)"]
          elif .commands | has($m.name) then
            .errors += ["line \($n): command \($m.name) is defined twice"]
          else .commands[$m.name] = $a end
      elif .tf and ($l | test("^[-*+]\\s")) then
        ($l | [capture("^- (?<key>run|files): +(?<val>\\S.*?)\\s*$")] | first) as $m
        | if $m == null then
            .errors += ["line \($n): expected '- run: <command with {file}>' or '- files: <git pathspecs>', got: \($l)"]
          elif $m.key == "files" then .test_files.files += [$m.val | splits("\\s+") | select(length > 0)]
          else
            ($m.val | argv_of) as $a
            | if .test_files.run != null then .errors += ["line \($n): the Test files section has two run lines"]
              elif $a == null or ($a | file_slots) != 1 then
                .errors += ["line \($n): the Test files run line must name {file} exactly once (words, or a JSON array of strings), got: \($l)"]
              else .test_files.run = $a end
          end
      elif .cc and ($l | test("^[-*+]\\s")) then
        ($l | [capture("^- +(?<p>\\S+)\\s*$")] | first | .p // null) as $p
        | if $p == null or ($p | bad_leave_out) then
            .errors += ["line \($n): expected \"- <path>\" (a git-ignored path relative to the project root, no \".\" or \"..\", outside .vbw/ and .git/), got: \($l)"]
          elif any(.leave_out[]; (.path | rtrimstr("/")) == ($p | rtrimstr("/"))) then
            .errors += ["line \($n): clean copy path \($p) is named twice"]
          else .leave_out += [{path: $p, line: $n}] end
      elif .res and ($l | test("^[-*+]\\s")) then
        ($l | [capture("^- +(?<p>\\S+)\\s*$")] | first | .p // null | if . == null then null else folder_of end) as $f
        | if $f == null then
            .errors += ["line \($n): expected '- <folder>/' (a relative folder, no '.' or '..', outside .vbw/), got: \($l)"]
          elif any(.results[]; . == $f) then
            .errors += ["line \($n): test results folder \($f) is named twice"]
          else .results += [$f] end
      elif (.in | not) then .
      elif $l | test("^[-*+]\\s") then
        ($l | [capture("^- (?<id>R[0-9]+) \\[(?<proof>auto|human)\\] +(?<text>\\S.*?)\\s*$")] | first) as $m
        | if $m == null then
            .errors += ["line \($n): expected '- R<n> [auto|human] statement', got: \($l)"]
          elif any(.reqs[]; .id == $m.id) then
            .errors += ["line \($n): \($m.id) is defined twice"]
          else .reqs += [$m] | .end = $n end
      elif ($l | test("^\\s+\\S")) and .end != null and ($n - 1) == .end then .end = $n
      else . end )
| if .seen then . else .errors += ["no '## Requirements' section"] end
| if .test_files == null or (.errors | length) > 0 then .
  elif .test_files.run == null then
    .errors += ["line \(.tfline): the Test files section needs a '- run: <command with {file}>' line"]
  elif (.test_files.files | length) == 0 then
    .errors += ["line \(.tfline): the Test files section needs a '- files: <git pathspecs>' line"]
  else . end
| {requirements: .reqs, commands: .commands, results: (if .results == [] then null else .results end), leave_out: (if .leave_out == [] then null else .leave_out end), test_files: .test_files, errors: .errors, end: .end}
