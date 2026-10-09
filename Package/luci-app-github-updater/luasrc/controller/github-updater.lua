module("luci.controller.github-updater", package.seeall)

local sys  = require "luci.sys"
local http = require "luci.http"
local json = require "luci.jsonc"
local nfs  = require "nixio.fs"

local TAG_PREFIX = "MT798X-WIFI-YES-"
local DATE_PAT   = "(%d%d%.%d%d%.%d%d%-%d%d%.%d%d%.%d%d)$"
local FW_FILE    = "/tmp/github-fw.itb"
local SUM_FILE   = "/tmp/github-fw.sha256sums"
local OK_MARK    = "/tmp/github-fw.verified"

function index()
	local page = entry({"admin", "system", "github-updater"},
		template("github-updater/main"), _("GitHub 在线升级"), 90)
	page.dependent = false
	entry({"admin", "system", "github-updater", "check"},    call("action_check")).leaf = true
	entry({"admin", "system", "github-updater", "download"}, call("action_download")).leaf = true
	entry({"admin", "system", "github-updater", "upgrade"},  call("action_upgrade")).leaf = true
	entry({"admin", "system", "github-updater", "savecfg"},  call("action_savecfg")).leaf = true
end

local function jret(t)
	http.prepare_content("application/json; charset=utf-8")
	http.write(json.stringify(t) or "{}")
end

-- shell 参数安全：去掉单引号后包一层单引号
local function shq(s)
	return "'" .. tostring(s or ""):gsub("'", "") .. "'"
end

local function build_info()
	local info = { FW_REPO = "", FW_PROFILE = "PURE", FW_DATE = "" }
	local f = io.open("/etc/fw-build-info", "r")
	if f then
		for line in f:lines() do
			local k, v = line:match("^(%u[%u_]*)=(.+)$")
			if k then info[k] = v end
		end
		f:close()
	end
	return info
end

local function get_mirror()
	return sys.exec("uci -q get github-updater.main.mirror"):gsub("%s+", "")
end

local function find_latest(info)
	local api = string.format(
		"https://api.github.com/repos/%s/releases?per_page=15", info.FW_REPO)
	local out = sys.exec("curl -sL --connect-timeout 10 -m 40 " ..
		"-H 'Accept: application/vnd.github+json' " .. shq(api))
	local data = json.parse(out)
	if type(data) ~= "table" or #data == 0 then
		return nil, "无法获取 Release 列表（检查网络或稍后再试）"
	end
	local want = TAG_PREFIX .. info.FW_PROFILE .. "-"
	for _, rel in ipairs(data) do
		if type(rel) == "table" and type(rel.tag_name) == "string"
			and rel.tag_name:sub(1, #want) == want then
			local r = { tag = rel.tag_name,
			            date = rel.tag_name:match(DATE_PAT) or "" }
			for _, a in ipairs(rel.assets or {}) do
				if type(a) == "table" and type(a.name) == "string" then
					if a.name:find("sysupgrade") and a.name:match("%.itb$") then
						r.url  = a.browser_download_url
						r.name = a.name
						r.size = a.size
					elseif a.name == "sha256sums.txt" then
						r.sum_url = a.browser_download_url
					end
				end
			end
			return r
		end
	end
	return nil, "最新 Release 中未找到 " .. info.FW_PROFILE .. " 版固件"
end

function action_check()
	local info = build_info()
	local rel, err = find_latest(info)
	local ret = {
		ok      = rel ~= nil,
		error   = err,
		repo    = info.FW_REPO,
		profile = info.FW_PROFILE,
		current = info.FW_DATE,
		mirror  = get_mirror()
	}
	if rel then
		ret.latest      = rel.tag
		ret.latest_date = rel.date
		ret.fw_name     = rel.name
		ret.fw_size     = rel.size
		ret.has_update  = (rel.date ~= "" and rel.date > info.FW_DATE)
	end
	jret(ret)
end

function action_download()
	local info = build_info()
	local rel, err = find_latest(info)
	if not rel or not rel.url then
		return jret({ ok = false, error = err or "未找到固件下载地址" })
	end

	local mirror = get_mirror()
	local dl = rel.url
	if mirror ~= "" then dl = mirror .. rel.url end

	os.execute("rm -f " .. FW_FILE .. " " .. SUM_FILE .. " " .. OK_MARK)

	local rc = sys.call("curl -sL --connect-timeout 15 -m 900 -o " ..
		FW_FILE .. " " .. shq(dl))
	if rc ~= 0 then
		return jret({ ok = false, error = "下载失败（curl 返回码 " .. rc .. "）" })
	end

	local verified = false
	if rel.sum_url then
		sys.call("curl -sL --connect-timeout 10 -m 60 -o " ..
			SUM_FILE .. " " .. shq(rel.sum_url))
		local expected = sys.exec("grep -F " .. shq(rel.name) .. " " ..
			SUM_FILE .. " | awk '{print $1}'"):gsub("%s+", "")
		local actual = sys.exec("sha256sum " .. FW_FILE ..
			" | awk '{print $1}'"):gsub("%s+", "")
		if expected == "" or expected ~= actual then
			os.remove(FW_FILE)
			return jret({ ok = false, error = "SHA256 校验失败，已删除文件" })
		end
		verified = true
	end

	io.open(OK_MARK, "w"):close()
	local sz = sys.exec("ls -l " .. FW_FILE ..
		" | awk '{print $5}'"):gsub("%s+", "")
	jret({ ok = true, file = FW_FILE, name = rel.name,
	       size = sz, verified = verified })
end

function action_upgrade()
	if not nfs.access(OK_MARK) or not nfs.access(FW_FILE) then
		return jret({ ok = false, error = "固件未下载或未通过校验，请先执行下载" })
	end
	local keep = http.formvalue("keep") == "1"
	local flag = keep and "" or "-n"
	sys.call("(sleep 2; sysupgrade -v " .. flag .. " " .. FW_FILE ..
		") >/dev/null 2>&1 &")
	jret({ ok = true, msg = "系统正在升级并自动重启，请勿断电，约 1-2 分钟后重新登录" })
end

function action_savecfg()
	local m = http.formvalue("mirror") or ""
	m = m:gsub("['\"%s]", "")
	sys.call("uci set github-updater.main.mirror=" .. shq(m) ..
		" && uci commit github-updater")
	jret({ ok = true })
end
