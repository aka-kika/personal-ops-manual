#!/bin/zsh
# ops-lock: lock the Personal Ops Manual pages so no app or agent can write them.
#
# Uses the macOS "locked" flag (chflags uchg, the same as Finder's Locked box) on
# every page and on the documents folder itself, so nothing can edit, create,
# rename, or delete a page. The _inbox folder stays writable, so readers can
# still file reports with report_change. Every process on this Mac hits the same
# wall, whatever agent or app it is: writes fail with "Operation not permitted".
#
#   ops-lock status            locked or unlocked, and how many pages are open
#   ops-lock lock              lock now (and cancel a pending auto-lock)
#   ops-lock unlock [minutes]  unlock for the operator; locks again by itself
#                              after <minutes> (default 30)
#
# Documents folder: $OPS_MANUAL_DIR, else the app's setting
# (defaults read com.kikalab.opsmanual documentsPath), else
# ~/Documents/Personal Ops Manual. Same order as mcp/server.mjs.
set -euo pipefail

docs_dir() {
  if [[ -n "${OPS_MANUAL_DIR:-}" ]]; then print -r -- "$OPS_MANUAL_DIR"; return; fi
  local d
  d=$(defaults read com.kikalab.opsmanual documentsPath 2>/dev/null || true)
  if [[ -n "$d" ]]; then print -r -- "$d"; else print -r -- "$HOME/Documents/Personal Ops Manual"; fi
}

DIR=$(docs_dir)
STATE="$HOME/.local/state/ops-lock"
PIDFILE="$STATE/relock.pid"
SELF="${0:A}"

[[ -d "$DIR" ]] || { print -u2 "ops-lock: no documents folder at $DIR"; exit 1; }

# Everything under the folder except the _inbox subtree.
targets() {
  find "$DIR" -mindepth 1 \( -path "$DIR/_inbox" -prune \) -o -print
}

cancel_relock() {
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
}

is_locked() { [[ "$(stat -f %Sf "$DIR")" == *uchg* ]]; }

# _inbox must exist and stay writable, or report_change cannot file anything:
# a locked folder refuses a new subfolder. Creating it needs the folder unlocked.
open_inbox() {
  if [[ ! -d "$DIR/_inbox" ]]; then
    chflags nouchg "$DIR"
    mkdir -p "$DIR/_inbox"
  fi
  chflags -R nouchg "$DIR/_inbox"
}

case "${1:-status}" in
  lock)
    cancel_relock
    open_inbox
    targets | while IFS= read -r f; do chflags uchg "$f"; done
    chflags uchg "$DIR"
    print "ops-lock: locked $DIR"
    ;;
  unlock)
    minutes="${2:-30}"
    [[ "$minutes" == <-> && "$minutes" -gt 0 ]] || { print -u2 "ops-lock: minutes must be a positive number"; exit 1; }
    cancel_relock
    chflags nouchg "$DIR"
    open_inbox
    targets | while IFS= read -r f; do chflags nouchg "$f"; done
    mkdir -p "$STATE"
    nohup zsh -c "sleep $((minutes * 60)); rm -f '$PIDFILE'; '$SELF' lock" >/dev/null 2>&1 &
    print $! > "$PIDFILE"
    disown
    print "ops-lock: unlocked $DIR, locks again in $minutes min (ops-lock lock to lock now)"
    ;;
  status)
    open=$(targets | while IFS= read -r f; do [[ "$(stat -f %Sf "$f")" == *uchg* ]] || print x; done | wc -l | tr -d ' ')
    if is_locked; then state="locked"; else state="unlocked"; fi
    print "ops-lock: $state · $open unlocked item(s) · $DIR"
    if [[ -f "$PIDFILE" ]]; then print "ops-lock: auto-lock pending (pid $(cat "$PIDFILE"))"; fi
    ;;
  *)
    print -u2 "usage: ops-lock status | lock | unlock [minutes]"
    exit 2
    ;;
esac
