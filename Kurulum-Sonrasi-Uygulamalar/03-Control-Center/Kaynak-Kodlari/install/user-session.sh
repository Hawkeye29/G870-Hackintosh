#!/bin/bash
set -eu
PACKAGE_DIR="/Library/Application Support/G870ControlCenter"
CLI="$PACKAGE_DIR/g870ctl"
DATA_DIR="$HOME/Library/Application Support/G870ControlCenter"
mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR"
LIVE="$DATA_DIR/telemetry-live.json"
REQUEST="$DATA_DIR/control-request.txt"
REPORT="$DATA_DIR/kontrol-oturumu.txt"
SESSION_DIR="$(mktemp -d "$DATA_DIR/.session.XXXXXX")"
chmod 700 "$SESSION_DIR"
mkfifo "$SESSION_DIR/input" "$SESSION_DIR/output"
rm -f "$REQUEST"
HELPER_PID=''
PIPE_OPEN=0
cleanup() {
 if [ "$PIPE_OPEN" = 1 ]; then
  printf 'quit\n' >&3 2>/dev/null || true
  exec 3>&-
  exec 4<&-
 fi
 if [ -n "$HELPER_PID" ]; then
  wait "$HELPER_PID" 2>/dev/null || true
  printf '\nAFTER SESSION CLOSE: mode and driver restoration state\n' >> "$REPORT"
  /usr/sbin/ioreg -r -c G870Bridge -l -w0 >> "$REPORT" 2>&1 || true
 fi
 rm -f "$SESSION_DIR/input" "$SESSION_DIR/output" "$SESSION_DIR/snapshot" "$REQUEST"
 rmdir "$SESSION_DIR" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
trap '' PIPE
"$CLI" connect < "$SESSION_DIR/input" > "$SESSION_DIR/output" 2> "$REPORT" &
HELPER_PID=$!
exec 3>"$SESSION_DIR/input"
exec 4<"$SESSION_DIR/output"
PIPE_OPEN=1
sample() {
 local LINE
 printf 'sample\n' >&3 || return 1
 IFS= read -r -t 10 LINE <&4 || return 1
 case "$LINE" in *'"timestamp":'*) ;; *) return 1 ;; esac
 printf '%s\n' "$LINE" > "$SESSION_DIR/snapshot"
 /bin/mv -f "$SESSION_DIR/snapshot" "$LIVE"
}
if ! sample; then
 echo 'Oturum acilamadi.'; cat "$REPORT"
 exit 1
fi
/bin/cp "$LIVE" "$DATA_DIR/session-before.json"
/usr/bin/open "/Applications/G870ControlCenter.app"
sleep 2
while /usr/bin/pgrep -x G870Monitor >/dev/null; do
 if [ -f "$REQUEST" ]; then
  ACTION=''
  IFS= read -r ACTION < "$REQUEST" || true
  rm -f "$REQUEST"
  printf '%s\n' "$ACTION" >&3
  if ! IFS= read -r -t 10 RESULT <&4; then echo 'Komut yaniti alinamadi.'; break; fi
  printf '%s\n' "$RESULT" >> "$REPORT"
 fi
 if ! sample; then echo 'Veri akisi durdu.'; cat "$REPORT"; break; fi
 sleep 3
done
