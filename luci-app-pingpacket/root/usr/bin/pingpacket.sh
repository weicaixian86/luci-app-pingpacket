#!/bin/sh

STATUS_FILE="/tmp/pingpacket_status.json"
STATUS_TMP="${STATUS_FILE}.tmp"
LOG_FILE="/tmp/pingpacket.log"
LOG_MAX_LINES=500
RUN_DIR="/var/run/pingpacket"
START_TIME_FILE="$RUN_DIR/start_time"
child_pids=""
domestic_fail_count=0
foreign_fail_count=0
domestic_fault_open=0
foreign_fault_open=0
domestic_total_samples=0
foreign_total_samples=0
domestic_success_count=0
foreign_success_count=0
domestic_loss_count=0
foreign_loss_count=0
domestic_rtt_sum="0"
foreign_rtt_sum="0"
domestic_min_rtt=""
foreign_min_rtt=""
domestic_max_rtt=""
foreign_max_rtt=""

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
	local result_file="$RUN_DIR/${name}_last_result"
	local result
	local rtt

	result="$(ping -c 1 -W 2 "$target" 2>/dev/null)"
	if echo "$result" | grep -q "bytes from"; then
		rtt="$(echo "$result" | sed -n 's/.*time=\([0-9.]*\).*/\1/p')"
		printf '1\n%s\n' "$rtt" > "$result_file"
	else
		printf '0\n\n' > "$result_file"
	fi
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
	log_event "丢包" "$label" "目标 ${target} 本次探测失败（连续第 ${fail_count} 次）"
	fault_open=1

	set_target_state "$name" "$fail_count" "$fault_open"
}

calc_stats() {
	local name="$1"
	local total_samples=0
	local success_count=0
	local loss_count=0
	local rtt_sum="0"
	local min_rtt=""
	local max_rtt=""
	local avg="0.0"
	local min="0.0"
	local max="0.0"
	local loss_rate="0.0"

	case "$name" in
		domestic)
			total_samples="$domestic_total_samples"
			success_count="$domestic_success_count"
			loss_count="$domestic_loss_count"
			rtt_sum="$domestic_rtt_sum"
			min_rtt="$domestic_min_rtt"
			max_rtt="$domestic_max_rtt"
			;;
		foreign)
			total_samples="$foreign_total_samples"
			success_count="$foreign_success_count"
			loss_count="$foreign_loss_count"
			rtt_sum="$foreign_rtt_sum"
			min_rtt="$foreign_min_rtt"
			max_rtt="$foreign_max_rtt"
			;;
	esac

	if [ "$success_count" -gt 0 ]; then
		avg="$(awk -v sum="$rtt_sum" -v count="$success_count" 'BEGIN { printf "%.1f", (sum + 0) / count }')"
		min="$(awk -v value="${min_rtt:-0}" 'BEGIN { printf "%.1f", value + 0 }')"
		max="$(awk -v value="${max_rtt:-0}" 'BEGIN { printf "%.1f", value + 0 }')"
	fi

	if [ "$total_samples" -gt 0 ]; then
		loss_rate="$(awk -v loss="$loss_count" -v total="$total_samples" 'BEGIN { printf "%.1f", loss * 100.0 / total }')"
	fi

	printf '{"avg":"%s","min":"%s","max":"%s","loss_rate":"%s","count":%d,"samples":%d}' \
		"$avg" "$min" "$max" "$loss_rate" "$success_count" "$total_samples"
}

update_cumulative_stats() {
	local name="$1"
	local target="$2"
	local result_file="$RUN_DIR/${name}_last_result"
	local success="0"
	local rtt=""
	local total_samples=0
	local success_count=0
	local loss_count=0
	local rtt_sum="0"
	local min_rtt=""
	local max_rtt=""

	[ -n "$target" ] || return 0

	case "$name" in
		domestic)
			total_samples="$domestic_total_samples"
			success_count="$domestic_success_count"
			loss_count="$domestic_loss_count"
			rtt_sum="$domestic_rtt_sum"
			min_rtt="$domestic_min_rtt"
			max_rtt="$domestic_max_rtt"
			;;
		foreign)
			total_samples="$foreign_total_samples"
			success_count="$foreign_success_count"
			loss_count="$foreign_loss_count"
			rtt_sum="$foreign_rtt_sum"
			min_rtt="$foreign_min_rtt"
			max_rtt="$foreign_max_rtt"
			;;
	esac

	total_samples=$((total_samples + 1))

	if [ -f "$result_file" ]; then
		success="$(sed -n '1p' "$result_file" 2>/dev/null)"
		rtt="$(sed -n '2p' "$result_file" 2>/dev/null)"
	fi

	if [ "$success" = "1" ]; then
		rtt="${rtt:-0}"
		success_count=$((success_count + 1))
		rtt_sum="$(awk -v sum="$rtt_sum" -v value="$rtt" 'BEGIN { printf "%.3f", (sum + 0) + (value + 0) }')"

		if [ -z "$min_rtt" ]; then
			min_rtt="$rtt"
		else
			min_rtt="$(awk -v current="$min_rtt" -v value="$rtt" 'BEGIN { printf "%.3f", ((value + 0) < (current + 0)) ? (value + 0) : (current + 0) }')"
		fi

		if [ -z "$max_rtt" ]; then
			max_rtt="$rtt"
		else
			max_rtt="$(awk -v current="$max_rtt" -v value="$rtt" 'BEGIN { printf "%.3f", ((value + 0) > (current + 0)) ? (value + 0) : (current + 0) }')"
		fi
	else
		loss_count=$((loss_count + 1))
	fi

	case "$name" in
		domestic)
			domestic_total_samples="$total_samples"
			domestic_success_count="$success_count"
			domestic_loss_count="$loss_count"
			domestic_rtt_sum="$rtt_sum"
			domestic_min_rtt="$min_rtt"
			domestic_max_rtt="$max_rtt"
			;;
		foreign)
			foreign_total_samples="$total_samples"
			foreign_success_count="$success_count"
			foreign_loss_count="$loss_count"
			foreign_rtt_sum="$rtt_sum"
			foreign_min_rtt="$min_rtt"
			foreign_max_rtt="$max_rtt"
			;;
	esac
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
	update_cumulative_stats "domestic" "$DOMESTIC_TARGET"
	update_cumulative_stats "foreign" "$FOREIGN_TARGET"

	DOMESTIC_STATS="$(calc_stats "domestic")"
	FOREIGN_STATS="$(calc_stats "foreign")"

	printf '{"start_time":"%s","updated_at":"%s","domestic":%s,"foreign":%s}\n' \
		"$START_TIME" "$UPDATED_AT" "$DOMESTIC_STATS" "$FOREIGN_STATS" > "$STATUS_TMP" && \
		mv -f "$STATUS_TMP" "$STATUS_FILE"

	sleep 1
done
