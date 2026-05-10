#!/usr/bin/env bash

input=$(cat)

mapfile -t f < <(
  jq -r '
    .workspace.current_dir // "",
    .model.display_name // "",
    .context_window.context_window_size // 0,
    .context_window.used_percentage // "",
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.five_hour.resets_at // "",
    .rate_limits.seven_day.used_percentage // "",
    .rate_limits.seven_day.resets_at // ""
  ' <<<"$input"
)

cwd=${f[0]}
model_name=${f[1]}
ctx_size=${f[2]}
used_pct=${f[3]}
five_pct=${f[4]}
five_resets=${f[5]}
seven_pct=${f[6]}
seven_resets=${f[7]}

basename_cwd=${cwd##*/}

short_model=${model_name#Claude }
short_model=${short_model% (*)}

if [ "$ctx_size" -ge 1000000 ]; then
  model_str="$short_model $((ctx_size / 1000000))M"
elif [ "$ctx_size" -ge 1000 ]; then
  model_str="$short_model $((ctx_size / 1000))K"
else
  model_str="$short_model"
fi

SEP=" | "

out="\033[36m${basename_cwd}"

[ -n "$short_model" ] && out="${out}${SEP}${model_str}"

if [ -n "$used_pct" ]; then
  out="${out}${SEP}ctx: $(printf '%.0f' "$used_pct")%"
fi

if [ -n "$five_pct" ] && [ -n "$five_resets" ]; then
  five_time=$(date -d "@$five_resets" +%H:%M)
  out="${out}${SEP}5h: $(printf '%.0f' "$five_pct")% @ ${five_time}"
fi

if [ -n "$seven_pct" ] && [ -n "$seven_resets" ]; then
  seven_time=$(date -d "@$seven_resets" '+%a %H:%M')
  out="${out}${SEP}7d: $(printf '%.0f' "$seven_pct")% @ ${seven_time}"
fi

printf '%b' "${out}\033[0m"
