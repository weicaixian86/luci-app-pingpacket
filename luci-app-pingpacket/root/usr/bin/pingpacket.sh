#!/bin/sh

STATUS_FILE="/tmp/pingpacket_status.json"
STATUS_TMP="${STATUS_FILE}.tmp"
LOG_FILE="/tmp/pingpacket.log"
LOG_MAX_LINES=500
FAIL_THRESHOLD=3
RUN_DIR="/var/run/pingpacket"
START_TIME_FILE="$RUN_DIR/start_time"
child_pids=""
domestic_fail_count=0
foreign_fail_count=0
domestic_fault_open=0
foreign_fault_open=0

log_rotate() {
	[ -f "$LOG_FILE" ] || return 0
	tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && \
		mv -f "${LOG_FILE}.tmp" "$LOG_FILE"
}

log_event() {
	local event_type="$1"
	local scope="$2"
	local message="$3"
	local timestamp

	timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
	if [ -n "$scope" ]; then
		printf '[%s] [%s] [%s] %s\n' "$timestamp" "$event_type" "$scope" "$message" >> "$LOG_FILE"
	else
		printf '[%s] [%s] %s\n' "$timestamp" "$event_type" "$message" >> "$LOG_FILE"
	fi
	log_rotate
}

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
	local result_file="$RUN_DIR/${name}_last_result"
	local result
	local rtt

	result="$(ping -c 1 -W 2 "$target" 2>/dev/null)"
	if echo "$result" | grep -q "bytes from"; then
		rtt="$(echo "$result" | sed -n 's/.*time=\([0-9.]*\).*/\1/p')"
		echo "$rtt" >> "$times_file"
		printf '1\n%s\n' "$rtt" > "$result_file"
	else
		echo "L" >> "$times_file"
		printf '0\n\n' > "$result_file"
	fi

	tail -n 120 "$times_file" > "$times_file.tmp" 2>/dev/null
	mv "$times_file.tmp" "$times_file" 2>/dev/null
}

get_target_state() {
	local name="$1"

	case "$name" in
		domestic)
			fail_count="$domestic_fail_count"
			fault_open="$domestic_fault_open"
			;;
		foreign)
			fail_count="$foreign_fail_count"
			fault_open="$foreign_fault_open"
			;;
		*)
			fail_count=0
			fault_open=0
			;;
	esac
}

set_target_state() {
	local name="$1"
	local next_fail_count="$2"
	local next_fault_open="$3"

	case "$name" in
		domestic)
			domestic_fail_count="$next_fail_count"
			domestic_fault_open="$next_fault_open"
			;;
		foreign)
			foreign_fail_count="$next_fail_count"
			foreign_fault_open="$next_fault_open"
			;;
	esac
}

reset_target_state() {
	local name="$1"

	rm -f "$RUN_DIR/${name}_last_result"
	set_target_state "$name" 0 0
}

update_target_faults() {
	local name="$1"
	local label="$2"
	local target="$3"
	local result_file="$RUN_DIR/${name}_last_result"
	local success="0"
	local rtt=""

	[ -n "$target" ] || {
		reset_target_state "$name"
		return 0
	}

	get_target_state "$name"

	if [ -f "$result_file" ]; then
		success="$(sed -n '1p' "$result_file" 2>/dev/null)"
		rtt="$(sed -n '2p' "$result_file" 2>/dev/null)"
	fi

	if [ "$success" = "1" ]; then
		if [ "$fault_open" = "1" ]; then
			log_event "恢复" "$label" "目标 ${target} 已恢复响应，当前延迟 ${rtt:-0} ms"
		fi

		set_target_state "$name" 0 0
		return 0
	fi

	fail_count=$((fail_count + 1))
	if [ "$fail_count" -ge "$FAIL_THRESHOLD" ] && [ "$fault_open" != "1" ]; then
		log_event "故障" "$label" "目标 ${target} 连续 ${FAIL_THRESHOLD} 次探测失败"
		fault_open=1
	fi

	set_target_state "$name" "$fail_count" "$fault_open"
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

	update_target_faults "domestic" "国内" "$DOMESTIC_TARGET"
	update_target_faults "foreign" "国外" "$FOREIGN_TARGET"

	DOMESTIC_STATS="$(calc_stats "$RUN_DIR/domestic_times")"
	FOREIGN_STATS="$(calc_stats "$RUN_DIR/foreign_times")"

	printf '{"start_time":"%s","updated_at":"%s","domestic":%s,"foreign":%s}\n' \
		"$START_TIME" "$UPDATED_AT" "$DOMESTIC_STATS" "$FOREIGN_STATS" > "$STATUS_TMP" && \
		mv -f "$STATUS_TMP" "$STATUS_FILE"

	sleep 1
done
