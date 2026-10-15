module("luci.controller.github-updater", package.seeall)

local sys  = require "luci.sys"
local http = require "luci.http"
local json = require "luci.jsonc"
local nfs  = require "nixio.fs"

local TAG_PREFIX = "MT798X-WIFI-YES-"
local DATE_PAT   = "(%d%d%.%d%d%.%d%d%-%d%d%.%d%d%.%d%d)$"
local FW_FILE    = "/tmp/github-fw.itb"
local OK_MARK    = "/tmp/github-fw.verified"
local STATE_FILE = "/tmp/github-fw.state"
local RC_FILE    = "/tmp/github-fw.rc"
local PID_FILE   = "/tmp/github-fw.pid"

function index()
	local page = entry({"admin", "system", "github-updater"},
		template("github-updater/main"), _("GitHub 在线升级"), 90)
	page.dependent = false
	entry({"admin", "system", "github-updater", "check"},    call("action_check")).leaf = true
	entry({"admin", "system", "github-updater", "download"}, call("action_download")).leaf = true
	entry({"admin", "system", "github-updater", "progress"}, call("action_progress")).leaf = true
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

local function state_read()
	local st = {}
	local s = read_all(STATE_FILE)
	if s then
		for line in s:gmatch("[^\n]+") do
			-- 键名含下划线（sum_url/first_url），%w 之外须加 _
			local k, v = line:match("^([%w_]+)=(.*)$")
			if k then st[k] = v end
		end
	end
	return st
end

local function state_write(st)
	local f = io.open(STATE_FILE, "w")
	if not f then return end
	for _, k in ipairs({"tag", "url", "name", "hash", "sum_url", "total", "first_url"}) do
		if st[k] then f:write(k .. "=" .. tostring(st[k]) .. "\n") end
	end
	f:close()
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

-- 从 Release 正文中提取「本次上游更新」一节（纯文本）
function extract_changelog(body)
	if type(body) ~= "string" or body == "" then return "" end
	local a = body:find("本次上游更新", 1, true)
	if not a then return "" end
	local rest = body:match("\n(.*)", a) or ""
	local b = rest:find("━━━", 1, true)
	if b then rest = rest:sub(1, b - 1) end
	return rest:gsub("%s+$", "")
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
	-- API 通道找到了版本但没解析到固件资产时，同样回退 atom 通道
	if rel and rel.url then return rel end
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
		ret.fw_url      = rel.url
		ret.channel     = rel.channel
		ret.page        = rel.page
		ret.changelog   = rel.changelog
		ret.has_update  = (rel.date ~= "" and rel.date > info.FW_DATE)

		-- 已下载并校验通过、且与最新版本一致的固件可直接复用，无需重复下载
		if nfs.access(OK_MARK) and nfs.access(FW_FILE) then
			local st = state_read()
			if st.tag == rel.tag then
				ret.pending = rel.tag
				local sz = sys.exec("wc -c < " .. FW_FILE ..
					" 2>/dev/null"):gsub("%s+", "")
				ret.pending_size = sz
			end
		end
	end
	jret(ret)
end

-- 启动后台下载（立即返回，进度由 progress 接口轮询）
-- 多源自动回退：GitHub release 资产经 302 跳转到 release-assets.githubusercontent.com，
-- 该 CDN 在国内高干扰（表现为挂起 0 字节）；公共加速代理在服务端跟随 302，可绕开封锁
function action_download()
	local info = build_info()
	local rel, err = find_latest(info)
	if not rel or not rel.url then
		return jret({ ok = false, error = err or "未找到固件下载地址" })
	end
	local mirror = get_mirror()

	-- 已下载并校验通过的固件存在时，本次调用视为"重新下载"：
	-- 清理临时固件与全部状态，find_latest 已在上方重新读取最新版本
	if nfs.access(OK_MARK) and nfs.access(FW_FILE) then
		os.execute("rm -f " .. FW_FILE .. " " .. OK_MARK .. " " ..
			STATE_FILE .. " " .. RC_FILE .. " " .. PID_FILE)
	end

	-- 下载源列表：手动代理前缀优先，其次直连，再依次回退公共加速代理
	local urls = {}
	if mirror ~= "" then table.insert(urls, mirror .. rel.url) end
	table.insert(urls, rel.url)
	for _, m in ipairs({ "https://ghfast.top/", "https://gh-proxy.com/",
	                     "https://gh.llkk.cc/", "https://ghproxy.net/" }) do
		table.insert(urls, m .. rel.url)
	end

	-- 补文件总大小（atom 通道没有 size，用 HEAD 逐个源拿 Content-Length）
	local total = tonumber(rel.size)
	if not total then
		for _, u in ipairs(urls) do
			local clen = sys.exec("curl -sIL --connect-timeout 8 -m 20 " .. shq(u) ..
				" 2>/dev/null | grep -i '^content-length:' | tail -1 | tr -dc '0-9'")
			if clen ~= "" then total = tonumber(clen); break end
		end
	end

	-- 断点续传：仅当首选源与上次一致时续传，避免跨源续传污染
	local st = state_read()
	local resume = ""
	if st.first_url == urls[1] and nfs.access(FW_FILE) then
		resume = "-C -"
	else
		os.execute("rm -f " .. FW_FILE .. " " .. OK_MARK)
	end

	-- 已在下载中则不重复启动；但 PID 已死（上次异常残留）则清理后重新启动
	if nfs.access(PID_FILE) and not nfs.access(RC_FILE) then
		local oldpid = (read_all(PID_FILE) or ""):gsub("%s+", "")
		if oldpid ~= "" and sys.call("kill -0 " .. oldpid .. " 2>/dev/null") == 0 then
			return jret({ ok = true, started = false, already = true,
			              total = total, url = rel.url, sources = #urls })
		end
		-- 僵尸 PID：清理残留标记，继续走下面的正常启动流程
		os.execute("rm -f " .. PID_FILE .. " " .. RC_FILE)
	end

	-- 生成下载启动脚本：逐源尝试，换源删残片；
	-- --speed-limit/--speed-time 让"挂起 0 字节"在 20 秒内失败换源，不再永久卡死
	local lf = io.open("/tmp/github-fw.sh", "w")
	if not lf then
		return jret({ ok = false, error = "无法创建下载启动脚本" })
	end
	lf:write("#!/bin/sh\nrm -f " .. RC_FILE .. "\nfirst=1\n")
	for i, u in ipairs(urls) do
		local rf = (i == 1) and resume or ""
		lf:write("[ $first -eq 0 ] && rm -f " .. FW_FILE .. "\nfirst=0\n")
		lf:write("echo " .. shq("trying: " .. u) .. " > /tmp/github-fw.trying\n")
		lf:write("curl -fL " .. rf .. " --connect-timeout 8 --speed-limit 2048 --speed-time 20 --max-time 1800 -o " ..
			FW_FILE .. " " .. shq(u) ..
			" && { echo " .. shq("used=" .. u) .. " >> " .. STATE_FILE ..
			"; echo 0 > " .. RC_FILE .. ".tmp && mv " .. RC_FILE .. ".tmp " .. RC_FILE .. "; exit 0; }\n")
	end
	lf:write("echo 1 > " .. RC_FILE .. ".tmp && mv " .. RC_FILE .. ".tmp " .. RC_FILE .. "\nexit 1\n")
	lf:close()

	sys.call("chmod +x /tmp/github-fw.sh")
	os.remove(PID_FILE)
	local launcher = "setsid"
	if sys.call("command -v setsid >/dev/null 2>&1") ~= 0 then launcher = "" end
	sys.call(launcher .. " /tmp/github-fw.sh </dev/null >/dev/null 2>&1 & echo $! > " .. PID_FILE)

	-- 验证确实启动（1 秒后进程存活或固件文件已开始写入）
	sys.call("sleep 1")
	local pid = (read_all(PID_FILE) or ""):gsub("%s+", "")
	local alive = pid ~= "" and sys.call("kill -0 " .. pid .. " 2>/dev/null") == 0
	if not alive and not nfs.access(FW_FILE) then
		return jret({ ok = false, error = "后台下载启动失败，请重试或检查系统日志" })
	end

	state_write({ tag = rel.tag, url = rel.url, name = rel.name,
	              hash = rel.hash, sum_url = rel.sum_url,
	              total = total and tostring(total) or "",
	              first_url = urls[1] })
	jret({ ok = true, started = true, total = total, url = rel.url,
	       resumed = resume ~= "", sources = #urls })
end

-- 进度轮询：下载中报字节数；下载完成后执行校验并给最终结论
function action_progress()
	-- busybox 无 stat 命令，用 wc -c 读文件大小（多返回值需括号截断）
	local size = 0
	if nfs.access(FW_FILE) then
		size = tonumber((sys.exec("wc -c < " .. FW_FILE ..
			" 2>/dev/null"):gsub("%s+", ""))) or 0
	end
	local st = state_read()
	local ret = { ok = true, done = false, size = size,
	              total = tonumber(st.total) }

	if not nfs.access(RC_FILE) then
		return jret(ret)  -- 仍在下载中
	end

	-- 下载结束，开始校验
	local rc = tonumber(((read_all(RC_FILE) or "1"):gsub("%s+", ""))) or 1
	os.execute("rm -f " .. RC_FILE .. " " .. PID_FILE)
	if rc ~= 0 then
		return jret({ ok = false, done = true, size = size,
			error = "下载失败（curl 错误码 " .. rc .. "）；进度已保留，重试自动续传" })
	end

	local expected = st.hash
	if (not expected or expected == "") and st.sum_url and st.sum_url ~= "" then
		http_get(get_mirror() .. st.sum_url, 60, "/tmp/ghu-sum.txt")
		expected = sys.exec("grep -F " .. shq(st.name or "") ..
			" /tmp/ghu-sum.txt 2>/dev/null | awk '{print $1}'"):gsub("%s+", "")
		if expected == "" then expected = nil end
	end

	if expected and expected ~= "" then
		local actual = sys.exec("sha256sum " .. FW_FILE ..
			" | awk '{print $1}'"):gsub("%s+", "")
		if actual ~= expected then
			-- 校验失败：state 有原始 url 才重下，缺失则直接报错（拼接 nil 会 500）
			if st.url and st.url ~= "" then
				os.execute("rm -f " .. FW_FILE)
				sys.call("curl -sL --connect-timeout 10 --speed-limit 2048 --speed-time 20 -m 300 -o " ..
					FW_FILE .. " " .. shq(get_mirror() .. st.url))
				actual = sys.exec("sha256sum " .. FW_FILE ..
					" | awk '{print $1}'"):gsub("%s+", "")
			end
			if actual ~= expected then
				os.remove(FW_FILE)
				return jret({ ok = false, done = true, size = 0,
					error = "SHA256 校验失败，已删除文件" })
			end
		end
		local mf = io.open(OK_MARK, "w")
		if mf then mf:close() end
		ret.verified = true
	end

	ret.done = true
	ret.size = size
	ret.verified = ret.verified or false
	return jret(ret)
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
