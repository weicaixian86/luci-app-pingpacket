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
	local target="$1"
	local name="$2"
	local times_file="$RUN_DIR/${name}_times"
	local result
	local rtt

	result="$(ping -c 1 -W 2 "$target" 2>/dev/null)"
	if echo "$result" | grep -q "bytes from"; then
		rtt="$(echo "$result" | sed -n 's/.*time=\([0-9.]*\).*/\1/p')"
		echo "$rtt" >> "$times_file"
	else
		echo "L" >> "$times_file"
	fi

	tail -n 120 "$times_file" > "$times_file.tmp" 2>/dev/null
	mv "$times_file.tmp" "$times_file" 2>/dev/null
}

calc_stats() {
	local file="$1"

	if [ ! -f "$file" ]; then
		printf '{"avg":"0.0","min":"0.0","max":"0.0","loss_rate":"0.0","count":0,"samples":0}'
		return
	fi

	awk '
	{
		total++
		if ($1 == "L") {
			loss++
			next
		}

		sum += $1
		count++
		if (min == "" || ($1 + 0) < (min + 0)) min = $1
		if (max == "" || ($1 + 0) > (max + 0)) max = $1
	}
	END {
		avg = count > 0 ? sum / count : 0
		lr = total > 0 ? loss * 100.0 / total : 0
		if (min == "") min = 0
		if (max == "") max = 0

		printf "{\"avg\":\"%.1f\",\"min\":\"%.1f\",\"max\":\"%.1f\",\"loss_rate\":\"%.1f\",\"count\":%d,\"samples\":%d}\n",
			avg, min, max, lr, count, total
	}' "$file"
}

while true; do
	START_TIME="$(cat "$START_TIME_FILE" 2>/dev/null || echo "")"
	UPDATED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
	DOMESTIC_TARGET=""
	FOREIGN_TARGET=""

	if [ -f "$RUN_DIR/config" ]; then
		DOMESTIC_TARGET="$(sed -n '1p' "$RUN_DIR/config")"
		FOREIGN_TARGET="$(sed -n '2p' "$RUN_DIR/config")"
	fi

	child_pids=""
	if [ -n "$DOMESTIC_TARGET" ]; then
		do_ping "$DOMESTIC_TARGET" "domestic" &
		child_pids="$!"
	fi

	if [ -n "$FOREIGN_TARGET" ]; then
		do_ping "$FOREIGN_TARGET" "foreign" &
		child_pids="${child_pids:+$child_pids }$!"
	fi

	[ -n "$child_pids" ] && wait $child_pids 2>/dev/null
	child_pids=""

	DOMESTIC_STATS="$(calc_stats "$RUN_DIR/domestic_times")"
	FOREIGN_STATS="$(calc_stats "$RUN_DIR/foreign_times")"

	printf '{"start_time":"%s","updated_at":"%s","domestic":%s,"foreign":%s}\n' \
		"$START_TIME" "$UPDATED_AT" "$DOMESTIC_STATS" "$FOREIGN_STATS" > "$STATUS_TMP" && \
		mv -f "$STATUS_TMP" "$STATUS_FILE"

	sleep 1
done
