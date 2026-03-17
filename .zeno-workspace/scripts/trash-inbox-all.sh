#!/usr/bin/env bash
set -euo pipefail
acct="zeno.wangzeyu@gmail.com"
page=""
total=0

while :; do
  if [ -n "$page" ]; then
    out=$(gog gmail search "in:inbox" --max 200 --page "$page" --account "$acct" --plain)
  else
    out=$(gog gmail search "in:inbox" --max 200 --account "$acct" --plain)
  fi

  next=$(echo "$out" | sed -n 's/^# Next page: --page //p' | head -n1)
  ids=$(echo "$out" | awk 'NR>1 && $1!="#" {print $1}' | grep -E '^[0-9a-f]+' || true)

  if [ -z "$ids" ]; then
    break
  fi

  for id in $ids; do
    gog gmail thread modify "$id" --add TRASH --remove INBOX --account "$acct" --force
  done

  count=$(echo "$ids" | wc -l | tr -d ' ')
  total=$((total+count))

  if [ -z "$next" ]; then
    break
  fi
  page="$next"
done

echo "Moved to trash: $total threads"