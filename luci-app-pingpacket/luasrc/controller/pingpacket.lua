module("luci.controller.pingpacket", package.seeall)

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

function index()
	if not nixio.fs.access("/etc/config/pingpacket") then
		return
	end

	local page = entry({"admin", "status", "pingpacket"}, alias("admin", "status", "pingpacket", "status"),
	                   "Pingpacket", 40)
	page.dependent = true
	page.acl_depends = { "luci-app-pingpacket" }

	entry({"admin", "status", "pingpacket", "status"}, template("pingpacket/status"),
	      "状态", 1).leaf = true
	entry({"admin", "status", "pingpacket", "get_data"}, call("action_get_data"))
	entry({"admin", "status", "pingpacket", "save_config"}, call("action_save_config"))
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
		domestic = { avg = "0.0", min = "0.0", max = "0.0", loss_rate = "0.0", count = 0 },
		foreign = { avg = "0.0", min = "0.0", max = "0.0", loss_rate = "0.0", count = 0 },
		start_time = "",
		service_running = false
	}

	result.service_running = (sys.call("[ -s /var/run/pingpacket/start_time ]") == 0)

	local f = io.open("/tmp/pingpacket_status.json", "r")
	if f then
		local content = f:read("*a")
		f:close()
		local ok, data = pcall(jsonc.parse, content)
		if ok and data then
			if data.start_time then
				result.start_time = data.start_time
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

function action_save_config()
	local uci = require("luci.model.uci").cursor()
	local sys = require("luci.sys")
	local http = require("luci.http")

	local enabled = normalize_enabled(http.formvalue("enabled"))
	local domestic = trim(http.formvalue("domestic_target"))
	local foreign = trim(http.formvalue("foreign_target"))
	local request_source = trim(http.formvalue("request_source"))

	local require_target = false
	if request_source == "save" then
		require_target = true
	elseif request_source == "toggle" then
		require_target = (enabled == "1")
	else
		require_target = (enabled == "1")
	end

	if require_target and domestic == "" and foreign == "" then
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
