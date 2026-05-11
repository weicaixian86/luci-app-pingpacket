module("luci.controller.pingpacket", package.seeall)

local LOG_FILE = "/tmp/pingpacket.log"
local CPU_STATE_FILE = "/tmp/pingpacket_cpu_state"

local function trim(value)
	return (value or ""):gsub("%c", ""):match("^%s*(.-)%s*$") or ""
end

local function normalize_enabled(value)
	return value == "1" and "1" or "0"
end

local function write_json(payload)
	local http = require("luci.http")
	local jsonc = require("luci.jsonc")

	http.prepare_content("application/json")
	http.write(jsonc.stringify(payload))
end

local function read_start_time()
	local start_time_file = io.open("/var/run/pingpacket/start_time", "r")
	if not start_time_file then
		return ""
	end

	local value = trim(start_time_file:read("*a"))
	start_time_file:close()
	return value
end

local function should_require_target(request_source, enabled)
	if request_source == "save" then
		return true
	end

	return enabled == "1"
end

local function has_any_target(uci)
	local domestic_target = trim(uci:get("pingpacket", "config", "domestic_target"))
	local foreign_target = trim(uci:get("pingpacket", "config", "foreign_target"))

	return domestic_target ~= "" or foreign_target ~= ""
end

local function read_file_content(path)
	local file = io.open(path, "r")
	if not file then
		return ""
	end

	local content = file:read("*a") or ""
	file:close()
	return content
end

local function read_log_payload()
	local nixio_fs = require("nixio.fs")
	local stat = nixio_fs.stat(LOG_FILE)

	return {
		content = read_file_content(LOG_FILE),
		updated_at = (stat and stat.mtime) and os.date("%Y-%m-%d %H:%M:%S", stat.mtime) or "",
		size = (stat and stat.size) or 0
	}
end

local function read_cpu_sample()
	local file = io.open("/proc/stat", "r")
	if not file then
		return nil, nil
	end

	local line = file:read("*l") or ""
	file:close()

	local total = 0
	local idle = 0
	local index = 0

	for token in line:gmatch("%S+") do
		if token ~= "cpu" then
			index = index + 1
			if index > 8 then
				break
			end

			local value = tonumber(token) or 0
			total = total + value

			if index == 4 or index == 5 then
				idle = idle + value
			end
		end
	end

	if total <= 0 then
		return nil, nil
	end

	return total, idle
end

local function read_saved_cpu_sample()
	local content = trim(read_file_content(CPU_STATE_FILE))
	local total, idle, timestamp = content:match("^(%d+)%s+(%d+)%s*(%d*)$")

	if not total or not idle then
		return nil, nil, nil
	end

	timestamp = tonumber(timestamp)

	return tonumber(total), tonumber(idle), timestamp
end

local function write_cpu_sample(total, idle)
	local file = io.open(CPU_STATE_FILE, "w")
	if not file then
		return
	end

	file:write(string.format("%d %d %d\n", total, idle, os.time()))
	file:close()
end

local function format_percent(value)
	value = tonumber(value) or 0

	if value < 0 then
		value = 0
	elseif value > 100 then
		value = 100
	end

	return string.format("%.1f", value)
end

local function read_memory_usage()
	local file = io.open("/proc/meminfo", "r")
	if not file then
		return "0.0"
	end

	local mem_total
	local mem_available
	local mem_free = 0
	local buffers = 0
	local cached = 0

	for line in file:lines() do
		local key, value = line:match("^(%w+):%s+(%d+)")
		value = tonumber(value)

		if key == "MemTotal" then
			mem_total = value
		elseif key == "MemAvailable" then
			mem_available = value
		elseif key == "MemFree" then
			mem_free = value or 0
		elseif key == "Buffers" then
			buffers = value or 0
		elseif key == "Cached" then
			cached = value or 0
		end
	end

	file:close()

	if not mem_total or mem_total <= 0 then
		return "0.0"
	end

	if not mem_available then
		mem_available = mem_free + buffers + cached
	end

	return format_percent(((mem_total - mem_available) * 100) / mem_total)
end

local function read_system_metrics()
	local current_total, current_idle = read_cpu_sample()
	local previous_total, previous_idle, previous_timestamp = read_saved_cpu_sample()
	local cpu_usage = "0.0"

	if current_total and current_idle then
		if not previous_timestamp or (os.time() - previous_timestamp) > 10 then
			previous_total = nil
			previous_idle = nil
		end

		if previous_total and previous_idle and current_total > previous_total then
			local total_delta = current_total - previous_total
			local idle_delta = current_idle - previous_idle

			if total_delta > 0 then
				cpu_usage = format_percent(((total_delta - idle_delta) * 100) / total_delta)
			end
		end

		write_cpu_sample(current_total, current_idle)
	end

	return {
		cpu_usage = cpu_usage,
		memory_usage = read_memory_usage()
	}
end

function index()
	if not nixio.fs.access("/etc/config/pingpacket") then
		return
	end

	local page = entry(
		{"admin", "status", "pingpacket"},
		alias("admin", "status", "pingpacket", "monitor"),
		"Ping丢包监控",
		40
	)
	page.dependent = true
	page.acl_depends = { "luci-app-pingpacket" }

	entry({"admin", "status", "pingpacket", "monitor"}, template("pingpacket/status"), "监控", 1).leaf = true
	entry({"admin", "status", "pingpacket", "logs"}, template("pingpacket/logs"), "日志", 2).leaf = true
	entry({"admin", "status", "pingpacket", "status"}, alias("admin", "status", "pingpacket", "monitor")).leaf = true
	entry({"admin", "status", "pingpacket", "get_data"}, call("action_get_data")).leaf = true
	entry({"admin", "status", "pingpacket", "get_logs"}, call("action_get_logs")).leaf = true
	entry({"admin", "status", "pingpacket", "clear_logs"}, call("action_clear_logs")).leaf = true
	entry({"admin", "status", "pingpacket", "save_config"}, call("action_save_config")).leaf = true
	entry({"admin", "status", "pingpacket", "restart_service"}, call("action_restart_service")).leaf = true
end

function action_get_data()
	local uci = require("luci.model.uci").cursor()
	local sys = require("luci.sys")
	local jsonc = require("luci.jsonc")

	local enabled = uci:get("pingpacket", "config", "enabled") or "0"
	local domestic_target = uci:get("pingpacket", "config", "domestic_target") or ""
	local foreign_target = uci:get("pingpacket", "config", "foreign_target") or ""

	local result = {
		enabled = enabled,
		domestic_target = domestic_target,
		foreign_target = foreign_target,
		server_time = os.date("%Y-%m-%d %H:%M:%S"),
		start_time = read_start_time(),
		updated_at = "",
		service_running = (sys.call("[ -s /var/run/pingpacket/start_time ]") == 0),
		system = read_system_metrics(),
		domestic = {
			avg = "0.0",
			min = "0.0",
			max = "0.0",
			loss_rate = "0.0",
			count = 0,
			samples = 0
		},
		foreign = {
			avg = "0.0",
			min = "0.0",
			max = "0.0",
			loss_rate = "0.0",
			count = 0,
			samples = 0
		}
	}

	local status_file = io.open("/tmp/pingpacket_status.json", "r")
	if status_file then
		local content = status_file:read("*a")
		status_file:close()

		local ok, data = pcall(jsonc.parse, content)
		if ok and data then
			if data.start_time then
				result.start_time = data.start_time
			end
			if data.updated_at then
				result.updated_at = data.updated_at
			end
			if data.domestic then
				result.domestic = data.domestic
			end
			if data.foreign then
				result.foreign = data.foreign
			end
		end
	end

	write_json(result)
end

function action_get_logs()
	local payload = read_log_payload()
	payload.server_time = os.date("%Y-%m-%d %H:%M:%S")
	write_json(payload)
end

function action_clear_logs()
	local nixio_fs = require("nixio.fs")
	nixio_fs.remove(LOG_FILE)

	write_json({
		success = true,
		message = ""
	})
end

function action_save_config()
	local uci = require("luci.model.uci").cursor()
	local sys = require("luci.sys")
	local http = require("luci.http")

	local enabled = normalize_enabled(http.formvalue("enabled"))
	local domestic = trim(http.formvalue("domestic_target"))
	local foreign = trim(http.formvalue("foreign_target"))
	local request_source = trim(http.formvalue("request_source"))

	if should_require_target(request_source, enabled) and domestic == "" and foreign == "" then
		write_json({
			success = false,
			message = "请至少配置一个目标。"
		})
		return
	end

	uci:set("pingpacket", "config", "enabled", enabled)
	uci:set("pingpacket", "config", "domestic_target", domestic)
	uci:set("pingpacket", "config", "foreign_target", foreign)
	uci:commit("pingpacket")

	sys.call("rm -f /tmp/luci-indexcache*")

	local rc
	if enabled == "1" then
		rc = sys.call("/bin/sh /etc/init.d/pingpacket restart >/dev/null 2>&1")
	else
		rc = sys.call("/bin/sh /etc/init.d/pingpacket stop >/dev/null 2>&1")
	end

	write_json({
		success = (rc == 0),
		message = (rc == 0) and "" or "服务状态更新失败。"
	})
end

function action_restart_service()
	local uci = require("luci.model.uci").cursor()
	local sys = require("luci.sys")

	local enabled = normalize_enabled(uci:get("pingpacket", "config", "enabled"))

	if enabled ~= "1" then
		write_json({
			success = false,
			message = "当前监控未启用。"
		})
		return
	end

	if not has_any_target(uci) then
		write_json({
			success = false,
			message = "请至少配置一个目标。"
		})
		return
	end

	local rc = sys.call("/bin/sh /etc/init.d/pingpacket restart >/dev/null 2>&1")
	write_json({
		success = (rc == 0),
		message = (rc == 0) and "" or "重启监控服务失败。"
	})
end
