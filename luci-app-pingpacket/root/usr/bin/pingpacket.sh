#!/bin/sh

STATUS_FILE="/tmp/pingpacket_status.json"
STATUS_TMP="${STATUS_FILE}.tmp"
RUN_DIR="/var/run/pingpacket"
START_TIME_FILE="$RUN_DIR/start_time"
child_pids=""

kill_children() {
	[ -n "$child_pids" ] || return 0
	kill $child_pids 2>/dev/null
	wait $child_pids 2>/dev/null
	child_pids=""
}

cleanup() {
	kill_children
	rm -f "$STATUS_FILE" "$STATUS_TMP"
	rm -rf "$RUN_DIR"
	exit 0
}
trap cleanup INT TERM

mkdir -p "$RUN_DIR"
date '+%Y-%m-%d %H:%M:%S' > "$START_TIME_FILE"

do_ping() {
	local target="$1" name="$2"
	local times_file="$RUN_DIR/${name}_times"

	result=$(ping -c 1 -W 2 "$target" 2>/dev/null)
	if echo "$result" | grep -q "bytes from"; then
		t=$(echo "$result" | sed -n 's/.*time=\([0-9.]*\).*/\1/p')
		echo "$t" >> "$times_file"
	else
		echo "L" >> "$times_file"
	fi

	tail -n 120 "$times_file" > "$times_file.tmp" 2>/dev/null
	mv "$times_file.tmp" "$times_file" 2>/dev/null
}

calc_stats() {
	local file="$1"
	if [ ! -f "$file" ]; then
		printf '{"avg":"0.0","min":"0.0","max":"0.0","loss_rate":"0.0","count":0}'
		return
	fi

	awk '
	{
		if ($1 == "L") { loss++ }
		else {
			sum += $1; count++
			if (min == "" || $1 < min) min = $1
			if (max == "" || $1 > max) max = $1
		}
	}
	END {
		total = count + loss
		avg = count > 0 ? sum / count : 0
		lr = total > 0 ? loss * 100.0 / total : 0
		printf "{\"avg\":\"%.1f\",\"min\":\"%.1f\",\"max\":\"%.1f\",\"loss_rate\":\"%.1f\",\"count\":%d}\n",
		       avg, (min ? min : 0), (max ? max : 0), lr, count
	}' "$file"
}

while true; do
	START=$(cat "$START_TIME_FILE" 2>/dev/null || echo "")
	dom=""
	frg=""

	if [ -f "$RUN_DIR/config" ]; then
		dom=$(sed -n '1p' "$RUN_DIR/config")
		frg=$(sed -n '2p' "$RUN_DIR/config")
	fi

	child_pids=""
	if [ -n "$dom" ]; then
		do_ping "$dom" "domestic" &
		child_pids="$!"
	fi
	if [ -n "$frg" ]; then
		do_ping "$frg" "foreign" &
		child_pids="${child_pids:+$child_pids }$!"
	fi
	[ -n "$child_pids" ] && wait $child_pids 2>/dev/null
	child_pids=""

	dom_stats=$(calc_stats "$RUN_DIR/domestic_times")
	frg_stats=$(calc_stats "$RUN_DIR/foreign_times")

	printf '{"start_time":"%s","domestic":%s,"foreign":%s}\n' \
		"$START" "$dom_stats" "$frg_stats" > "$STATUS_TMP" && mv -f "$STATUS_TMP" "$STATUS_FILE"

	sleep 1
done
