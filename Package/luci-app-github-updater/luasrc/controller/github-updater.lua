module("luci.controller.github-updater", package.seeall)

local sys  = require "luci.sys"
local http = require "luci.http"
local json = require "luci.jsonc"
local nfs  = require "nixio.fs"

local TAG_PREFIX = "MT798X-WIFI-YES-"
local DATE_PAT   = "(%d%d%.%d%d%.%d%d%-%d%d%.%d%d%.%d%d)$"
local FW_FILE    = "/tmp/github-fw.itb"
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

-- 统一的 HTTP 下载：body 写入文件，返回 http_code 与 curl 返回码
local function http_get(url, timeout, outfile)
	os.remove(outfile)
	local codef = outfile .. ".code"
	os.remove(codef)
	local rc = sys.call(string.format(
		"curl -sL --connect-timeout 10 -m %d -o %s -w '%%{http_code}' %s > %s 2>/dev/null",
		timeout or 40, shq(outfile), shq(url), shq(codef)))
	local code = ""
	local f = io.open(codef, "r")
	if f then code = (f:read("*l") or ""):gsub("%s+", ""); f:close() end
	os.remove(codef)
	return code, rc
end

local function read_all(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- 从 Release 正文中提取「本次上游更新」一节（纯文本）
local function extract_changelog(body)
	if type(body) ~= "string" or body == "" then return "" end
	local a = body:find("本次上游更新", 1, true)
	if not a then return "" end
	local rest = body:match("\n(.*)", a) or ""
	local b = rest:find("━━━", 1, true)
	if b then rest = rest:sub(1, b - 1) end
	return rest:gsub("%s+$", "")
end

-- 从 Release 对象数组中挑选固件资产（API 通道）
local function pick_assets(rel)
	local r = { tag = rel.tag_name,
	            date = (rel.tag_name or ""):match(DATE_PAT) or "",
	            page = rel.html_url,
	            changelog = extract_changelog(rel.body) }
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

-- 通道一：GitHub API（信息最全，但 api.github.com 在部分网络下不可达）
local function find_latest_api(info)
	local api = string.format(
		"https://api.github.com/repos/%s/releases?per_page=15", info.FW_REPO)
	local code, rc = http_get(api, 40, "/tmp/ghu-releases.json")
	if rc ~= 0 then
		return nil, "API 通道网络连接失败（curl 错误码 " .. rc .. "）"
	end
	if code ~= "200" then
		return nil, "API 通道返回 HTTP " .. (code ~= "" and code or "无响应")
	end
	local data = json.parse(read_all("/tmp/ghu-releases.json") or "")
	if type(data) ~= "table" or #data == 0 then
		return nil, "API 通道响应无法解析"
	end
	local want = TAG_PREFIX .. info.FW_PROFILE .. "-"
	for _, rel in ipairs(data) do
		if type(rel) == "table" and type(rel.tag_name) == "string"
			and rel.tag_name:sub(1, #want) == want then
			local r = pick_assets(rel)
			r.channel = "api"
			return r
		end
	end
	return nil, "API 通道：最新 Release 中未找到 " .. info.FW_PROFILE .. " 版固件"
end

-- 通道二：releases.atom + sha256sums.txt（只需 github.com，且支持代理前缀）
local function find_latest_atom(info, mirror)
	local page = string.format("https://github.com/%s/releases.atom", info.FW_REPO)
	local code, rc = http_get(mirror .. page, 40, "/tmp/ghu-releases.atom")
	if rc ~= 0 then
		return nil, "Atom 通道网络连接失败（curl 错误码 " .. rc .. "）"
	end
	if code ~= "200" then
		return nil, "Atom 通道返回 HTTP " .. (code ~= "" and code or "无响应")
	end
	local xml = read_all("/tmp/ghu-releases.atom") or ""
	local want = TAG_PREFIX .. info.FW_PROFILE .. "-"
	for tag in xml:gmatch('releases/tag/([^"<]+)') do
		if tag:sub(1, #want) == want then
			local r = { tag = tag, date = tag:match(DATE_PAT) or "",
			            channel = "atom",
			            page = string.format("https://github.com/%s/releases/tag/%s",
			                                 info.FW_REPO, tag) }
			-- atom 里没有资产列表，用固定名的 sha256sums.txt 反推固件文件名与哈希
			local sum_url = string.format(
				"https://github.com/%s/releases/download/%s/sha256sums.txt",
				info.FW_REPO, tag)
			local scode, src = http_get(mirror .. sum_url, 30, "/tmp/ghu-sum.txt")
			if src == 0 and scode == "200" then
				local sf = io.open("/tmp/ghu-sum.txt", "r")
				if sf then
					for line in sf:lines() do
						local hash, name = line:match("^(%x+)%s+(.+)$")
						if name and name:find("sysupgrade")
							and name:match("%.itb$") then
							r.name = name
							r.hash = hash
							r.url  = string.format(
								"https://github.com/%s/releases/download/%s/%s",
								info.FW_REPO, tag, name)
						end
					end
					sf:close()
				end
			end
			if not r.url then
				return nil, "Atom 通道：已找到最新版本 " .. tag ..
					"，但解析 sha256sums.txt 失败"
			end
			return r
		end
	end
	return nil, "Atom 通道：最新 Release 中未找到 " .. info.FW_PROFILE .. " 版固件"
end

local function find_latest(info)
	local rel, api_err = find_latest_api(info)
	if rel then return rel end
	local atom_rel, atom_err = find_latest_atom(info, get_mirror())
	if atom_rel then return atom_rel end
	return nil, api_err .. "；" .. atom_err
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
		ret.channel     = rel.channel
		ret.page        = rel.page
		ret.changelog   = rel.changelog
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
	os.execute("rm -f " .. FW_FILE .. " " .. OK_MARK)

	local rc = sys.call("curl -sL --connect-timeout 15 -m 900 -o " ..
		FW_FILE .. " " .. shq(mirror .. rel.url))
	if rc ~= 0 then
		return jret({ ok = false, error = "下载失败（curl 错误码 " .. rc ..
			(mirror ~= "" and "，当前使用代理前缀" or "，直连）") .. "）" })
	end

	-- 校验：atom 通道已有哈希；api 通道下载 sha256sums.txt
	local expected = rel.hash
	if not expected and rel.sum_url then
		http_get(mirror .. rel.sum_url, 60, "/tmp/ghu-sum.txt")
		expected = sys.exec("grep -F " .. shq(rel.name) ..
			" /tmp/ghu-sum.txt 2>/dev/null | awk '{print $1}'"):gsub("%s+", "")
		if expected == "" then expected = nil end
	end

	local verified = false
	if expected then
		local actual = sys.exec("sha256sum " .. FW_FILE ..
			" | awk '{print $1}'"):gsub("%s+", "")
		if actual ~= expected then
			os.remove(FW_FILE)
			return jret({ ok = false, error = "SHA256 校验失败，已删除文件" })
		end
		verified = true
	end

	io.open(OK_MARK, "w"):close()
	local sz = sys.exec("ls -l " .. FW_FILE ..
		" | awk '{print $5}'"):gsub("%s+", "")
	jret({ ok = true, file = FW_FILE, name = rel.name,
	       size = sz, verified = verified, channel = rel.channel })
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
