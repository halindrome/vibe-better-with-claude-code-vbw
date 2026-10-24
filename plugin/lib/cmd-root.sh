#!/usr/bin/env bash
# vbw root: the project folder, the top folder of the git repository, which every
# VBW path (.vbw/, plan and check files) is relative to. The skills pass it to
# the workflows (args.root), so agents of a session started in a subfolder work
# in the project folder. Needs no VBW project yet and writes nothing.

cmd_root() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw root"
  vbw_git_root
}
