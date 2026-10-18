# The one rule for a holder's display name (R192): who holds the run, shown in
# messages, the status line and the panel. Names come from Claude Code's list of
# chats and are untrusted text: cleaned before they are stored or shown. Only
# defs, no program: hooks and the status line `include "holder" {search:
# "../lib"}`; kernel commands put this text in front of their jq programs.

# clean_name: drops CSI and OSC escape sequences, then every control character
# (U+0000-U+001F, U+007F, U+0080-U+009F).
def clean_name:
  if type != "string" then ""
  else gsub("\u001b\\][^\u0007\u001b]*(\u0007|\u001b\\\\)"; "")
    | gsub("\u001b\\[[0-?]*[ -/]*[@-~]"; "")
    | gsub("[\u0000-\u001f\u007f-\u009f]"; "")
  end;

# cut_name($n): a name longer than $n becomes its first $n-1 characters plus …
def cut_name($n): if length > $n then .[0:($n - 1)] + "…" else . end;

# holder_name($lease; $stored; $live): the list's live name, else the stored
# name, else the first 8 characters of the lease's session id, else a fixed
# sentence; cleaned, then cut to 40.
def holder_name($lease; $stored; $live):
  ( [($live, $stored) | clean_name | select(length > 0)][0]
    // (($lease | if type == "object" then .session else null end) | if type == "string" and length > 0 then .[0:8] else null end)
    // "a session VBW cannot name" )
  | clean_name | cut_name(40);
