#!/bin/bash
# Absolute tokens, not percent: on a 1M window 369k shows 37% yet every turn re-reads all of it.
# The 80% rule catches 200k-window models, which auto-compact before 300k.

jq -r '
  def paint($code; $s): "\u001b[\($code)m\($s)\u001b[0m";
  (.context_window.total_input_tokens // 0) as $t
  | .context_window.used_percentage as $pct
  | "\($t / 1000 | floor)k" as $k
  | paint("2"; .model.display_name // "?") + "  "
    + if $t >= 300000 or $pct >= 80 then paint("31"; "\($k) /clear?")
      elif $t >= 150000 then paint("2;33"; $k)
      else paint("2;32"; $k) end
    + if $pct then " " + paint("2"; "\($pct | floor)%") else "" end
'
