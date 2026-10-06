#!/usr/bin/env bash
# Память приложения во время созвона (AC-05, R-25): `footprint` раз в минуту, в конце — максимум.
#   scripts/footprint-monitor.sh [минут=10]
set -euo pipefail
MINUTES="${1:-10}"
PID="$(pgrep -x InterviewCopilot || true)"
[ -z "$PID" ] && { echo "InterviewCopilot не запущен" >&2; exit 1; }
max=0
for ((i = 1; i <= MINUTES; i++)); do
  mb=$(footprint -p "$PID" 2>/dev/null | awk '/phys_footprint:/ {print $2; exit}')
  unit=$(footprint -p "$PID" 2>/dev/null | awk '/phys_footprint:/ {print $3; exit}')
  [ "$unit" = "GB" ] && mb=$(python3 -c "print(int(float('$mb')*1024))")
  echo "$(date +%H:%M:%S) минута $i: ${mb} МБ"
  [ "${mb%.*}" -gt "$max" ] && max="${mb%.*}"
  [ "$i" -lt "$MINUTES" ] && sleep 60
done
echo "Максимум: ${max} МБ (порог AC-05: 1536 МБ) — $([ "$max" -le 1536 ] && echo PASS || echo FAIL)"
