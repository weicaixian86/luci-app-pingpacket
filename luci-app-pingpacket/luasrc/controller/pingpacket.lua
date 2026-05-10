module("luci.controller.pingpacket", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/pingpacket") then
		return
	end

	local page = entry({"admin", "status", "pingpacket"}, alias("admin", "status", "pingpacket", "status"),
	                   _("Ping Packet Loss"), 40)
	page.dependent = true
	page.acl_depends = { "luci-app-pingpacket" }

	entry({"admin", "status", "pingpacket", "status"}, template("pingpacket/status"),
	      _("Status"), 1).leaf = true
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

	result.service_running = (sys.call("[ -f /var/run/pingpacket/start_time ]") == 0)

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

	luci.http.prepare_content("application/json")
	luci.http.write(jsonc.stringify(result))
end

function action_save_config()
	local uci = require("luci.model.uci").cursor()
	local sys = require("luci.sys")
	local jsonc = require("luci.jsonc")

	local enabled = luci.http.formvalue("enabled") or "0"
	local domestic = luci.http.formvalue("domestic_target") or ""
	local foreign = luci.http.formvalue("foreign_target") or ""

	uci:set("pingpacket", "config", "enabled", enabled)
	uci:set("pingpacket", "config", "domestic_target", domestic)
	uci:set("pingpacket", "config", "foreign_target", foreign)
	uci:commit("pingpacket")

	sys.call("rm -f /tmp/luci-indexcache")

	local success = true
	local msg = ""

	if enabled == "1" then
		if domestic == "" and foreign == "" then
			success = false
			msg = "Please configure at least one target."
		else
			sys.call("/etc/init.d/pingpacket restart")
		end
	else
		sys.call("/etc/init.d/pingpacket stop")
	end

	luci.http.prepare_content("application/json")
	luci.http.write(jsonc.stringify({ success = success, message = msg }))
end
