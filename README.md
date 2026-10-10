# 🚀 ImmortalWrt 京东云百里 AX6000 固件（云编译 · 25.12 稳定分支）

OpenWrt / ImmortalWrt / AX6000 / MT7986A / JDCloud RE-CP-03 / WED / 云编译
> 基于 ImmortalWrt **openwrt-25.12 稳定分支**的定制固件，适配京东云无线宝百里 AX6000（RE-CP-03），每 6 小时自动检测上游修复并编译发布

> 🔀 **本仓库为 25.12 稳定分支版**：内核 6.12 LTS，只做修复性回填，适合养老日常使用。
> 想要最新内核与特性？👉 **[master 滚动快照版 → Openwrt-AX6000](https://github.com/li5135580/Openwrt-AX6000)**

[👉 进入 Releases 下载固件](../../releases)

---

## 📋 设备信息

| 参数 | 规格 |
|------|------|
| 型号 | 京东云无线宝百里 AX6000（RE-CP-03） |
| SoC | MediaTek MT7986A（Filogic 830，4× Cortex-A53） |
| RAM | 1GB DDR4 |
| Flash | 128GB eMMC |
| 以太网 | 4× 1GbE + 1× 2.5GbE |
| 无线 | 双频 WiFi 6：2.4GHz 4×4（1148Mbps）+ 5GHz 4×4（4804Mbps @160MHz） |
| Target | `mediatek/filogic` |
| Profile | `jdcloud_re-cp-03` |

## ⭐ 项目特点

- 🔥 **云编译构建** - 基于 GitHub Actions 完全自动化编译
- 🔄 **稳定分支跟进** - 跟踪 ImmortalWrt openwrt-25.12 稳定分支，上游修复自动编译发布
- ⚡ **硬件卸载** - 支持 MT7986 的 WED（Wireless Ethernet Dispatch）无线硬件卸载
- 🌐 **2.5G 网口** - RTL8221B 2.5GbE 支持
- 📦 **双版本** - PURE 纯净版 / PLUS 全量版，按需选择
- ⬆️ **在线升级** - LuCI 内置 GitHub Releases 更新检测，一键下载校验并升级
- 🧩 **灵活定制** - 支持自定义编译配置和插件

> ⚠️ **包管理器变更提醒**：OpenWrt / ImmortalWrt 自 25.12 起已从 opkg 切换到 **apk**。系统内安装软件包请使用 `apk add <包名>`，旧教程中的 `opkg install` 命令不再适用；第三方 `.ipk` 文件不能直接用，需对应 apk 格式。

---

## 📥 快速开始

### 1️⃣ 下载固件

| 版本 | 下载入口 | 适合场景 |
|------|----------|----------|
| 🍃 `PURE` 纯净版 | [👉 下载最新 PURE 固件](../../releases?q=PURE&expanded=true) | 轻量稳定，日常推荐，插件按需自装 |
| 🚀 `PLUS` 版 | [👉 下载最新 PLUS 固件](../../releases?q=PLUS&expanded=true) | OpenClash / PassWall2 / Docker / AdGuard Home 开箱即用 |
| 👑 `PROMAX` 版 | [👉 下载最新 PROMAX 固件](../../releases?q=PROMAX&expanded=true) | PLUS 全家桶 + SQM 流控 / Argon 主题 / 带宽监控 / 统计图表 |

> 💡 打开后列表**最上方**即为该版本最新固件；也可浏览 [全部 Releases](../../releases)。

### 固件版本

| 版本 | 适合人群 | 预置内容 |
|------|----------|----------|
| `PURE` 纯净版 | 希望系统轻量、稳定，按需自行安装插件的用户 | 完整网络功能栈 + 常用管理插件 |
| `PLUS` 版 | 希望刷完即用常见扩展服务的用户 | 在纯净版基础上增加 OpenClash、PassWall2、Docker / Dockerman、AdGuard Home、DDNS、ttyd 终端、UPnP、WireGuard 管理界面、USB 打印（p910nd），以及分区扩容（partexp）、网络唤醒增强（wolultra）等实用插件 |
| `PROMAX` 版 | 想要最全功能集合的用户 | 在 PLUS 版基础上再增加 SQM 智能流控、Argon 主题及配置面板、实时带宽监控（nlbwmon）、标准网络唤醒（wol）、统计图表（statistics） |

### 文件命名与附件说明

Releases 页面每个版本包含以下文件（PURE / PLUS / PROMAX 分开发布）：

| 文件 | 说明 |
|------|------|
| `源码作者-分支-pure/plus/promax-filogic-jdcloud_re-cp-03-*-sysupgrade.itb` | 固件本体（联发科平台为 `.itb` 格式），用于系统内升级 |
| `*-bl31-uboot.fip` / `*-preloader.bin`（bl2）/ `*-gpt.bin` | 启动链文件，首次刷入或重建分区时使用，详见刷机教程 |
| `Config-配置-版本-作者-分支-时间.txt` | 本次编译使用的完整 `.config`，便于复现构建或二次定制 |
| `Packages-配置-版本-作者-分支-时间.txt` | 外部插件（OpenClash / PassWall2 及依赖 feed）的仓库、分支与 commit 记录，仅 `PLUS`/`PROMAX` 版生成 |
| `sha256sums.txt` | 固件校验文件，刷机前请先校验 |

> ⚠️ 百里**没有 factory 镜像**。联发科平台的首次刷入走 bl2/fip/gpt + U-Boot 路径，与高通平台的 factory 刷法完全不同。

---

## 🛠️ 刷机指南

> ⚠️ **重要提示：** 百里是**联发科 MT7986A** 平台，与雅典娜（高通 IPQ6010）架构完全不同。**雅典娜的不死 U-Boot、GPT 分区表、USB 9008 工具一律不能用于百里，刷错必砖！**

### 详细教程
📖 **[完整刷机救砖教程 →](Docs/刷机救砖教程.md)**

### 刷机前必读

1. **备份所有数据**：SSH 登录后优先整盘备份 eMMC
2. **验证文件完整性**：将 `sha256sums.txt` 与固件下载到同一目录后执行：
   ```bash
   # Linux / macOS
   sha256sum -c sha256sums.txt --ignore-missing
   ```
   ```powershell
   # Windows：计算固件哈希，与 sha256sums.txt 中对应行比对
   certutil -hashfile 固件文件名.itb SHA256
   ```
3. **准备恢复方案**：百里救砖依赖 **TTL 串口**（3.3V 电平，115200），刷机前务必确认可用

### WiFi 推荐设置（刷机后调优）

百里为双频机型：2.4G（4×4）+ 5G（4×4）：

| WiFi | 信道 | 带宽 | 说明 |
|------|------|------|------|
| 2.4G | `11` | `20MHz` | 抗干扰优先，拥挤环境下 20MHz 更稳 |
| 5G | `36-64` | `160MHz` | 4×4 满血 4804Mbps；DFS 信道，遇雷达会跳频 |
| 5G（备选） | `149` | `80MHz` | 非 DFS，功率上限高，稳定优先选这个 |

通用设置：

| 项 | 推荐值 | 说明 |
|----|--------|------|
| 地区 | `US` | 可用信道多、功率上限高 |
| 发射功率 | `24 dBm` | US 法规内的高功率档 |
| 加密 | `WPA2-PSK`，算法 `CCMP` | 兼容性最稳组合，老设备无障碍接入 |

---

## 🧱 构建机制（PURE / PLUS / PROMAX 如何隔离）

- 三个版本由工作流参数 `WRT_PROFILE` 区分：PLUS 在通用配置上叠加 `GENERAL_AX6000_PLUS.txt`，PROMAX 再叠加 `GENERAL_AX6000_PROMAX.txt`，按 kconfig 规则逐层覆盖，**纯净版产物不受 Plus/Promax 版任何改动影响**。
- Plus 版插件来源唯一：LuCI 插件本体由 `Scripts/Packages.sh` 克隆到 `package/`（优先级高于 feeds），依赖包（xray、sing-box 等）由 `passwall_packages` feed 提供，避免同名包双重定义。
- Plus 版配置 `Config/GENERAL_AX6000_PLUS.txt` 追加在通用配置之后，按 kconfig 规则覆盖纯净版关闭的选项（如 Docker 所需内核模块、`dnsmasq-full`）。
- 编译缓存（ccache / 工具链）与版本无关，PURE 与 PLUS 共享同一份，不额外占用缓存配额。

### 版本与验证建议

- `PURE`：推荐作为日常稳定版，保持当前轻量配置。
- `PLUS`：Plus 版会额外集成 OpenClash、PassWall2、Docker / Dockerman、AdGuard Home、DDNS、ttyd、UPnP 等，固件体积和运行资源占用都会明显高于纯净版。
- 手动测试时可在 `WRT-TEST` 工作流选择 `PROFILE=PURE` 或 `PROFILE=PLUS`；建议 Plus 版发布前至少先用 `TEST=true` 生成最终 `.config`，再用完整编译确认上游插件依赖没有变化。
- Release 会额外上传 `Packages-*.txt` 记录 Plus 版外部插件仓库、分支和 commit，方便排查 OpenClash / PassWall2 上游变更导致的编译问题。

> ⚠️ Plus 版依赖外部插件仓库和上游 feeds，若上游调整包名或依赖，可能需要同步更新 `Config/GENERAL_AX6000_PLUS.txt`。

### PLUS 版使用提示

- **AdGuard Home 首次启用**：出厂默认关闭。启用服务后访问 `http://路由器IP:3000` 完成安装向导，向导中 **DNS 监听端口请填 `5553`**（`53` 已被系统 dnsmasq 占用，填 53 会报错）；完成后在 LuCI「网络 → DHCP/DNS」的「DNS 转发」中填入 `127.0.0.1#5553` 并勾选「忽略解析文件」，广告过滤即对全局生效。
- **代理插件二选一**：OpenClash 与 PassWall2 工作机制相同（接管 DNS + 透明代理规则），同时启用会互相抢占，轻则其中一个失效、分流错乱，重则断网，请只启用其中一个，切换前先停用当前插件。
- **Docker 存储去向**：Docker 数据默认写入系统分区。百里 eMMC 有 128GB，建议先用「分区扩容（partexp）」将空闲 eMMC 挂载为独立分区，再在 Docker 设置中把存储路径指向该分区。

---

## 📂 项目结构

| 目录/文件 | 用途 | 说明 |
|----------|------|------|
| `.github/workflows/MTK-ALL.yml` | 主编译入口 | 每日定时（经 Auto-Clean 触发）或手动，构建 PURE + PLUS |
| `.github/workflows/WRT-CORE.yml` | 公用编译核心 | 被 MTK-ALL / WRT-TEST 调用，不直接运行 |
| `.github/workflows/WRT-TEST.yml` | 配置验证 | 只生成最终 `.config` 不编译，几分钟出结果 |
| `.github/workflows/Auto-Clean.yml` | 清理+定时触发 | 每天 06:00（北京时间）清理旧产物并触发编译 |
| `Config/MT798X-WIFI-YES.txt` | 平台配置 | 目标平台与设备型号（mediatek/filogic + RE-CP-03） |
| `Config/GENERAL_AX6000.txt` | 通用配置 | PURE / PLUS 两个版本共用 |
| `Config/GENERAL_AX6000_PLUS.txt` | Plus 版增量配置 | 仅 PLUS 生效 |
| `Scripts/Packages.sh` | 插件拉取 | 克隆 OpenClash / PassWall2 等第三方插件源码 |
| `Scripts/Settings.sh` | 自定义设置 | 默认 IP/主机名/WiFi 名称、内存水位线调优等 |
| `Docs/` | 文档 | 刷机救砖教程 |

---

## 🔗 上游源码与致谢

本项目站在以下开源项目的肩膀上，在此致谢：

### 项目来源

| 项目 | 说明 |
|------|------|
| [ones20250/Openwrt-AX6600](https://github.com/ones20250/Openwrt-AX6600) | **本仓库改造自该项目**（京东云雅典娜 AX6600 固件 CI），PURE/PLUS 双版本机制、编译核心工作流、脚本框架均源自于此 |
| [VIKINGYFY/OpenWrt-CI](https://github.com/VIKINGYFY/OpenWrt-CI) | 编译缓存机制代码出处（MIT, Copyright 2026 VIKINGYFY） |

### 固件源码

| 项目 | 说明 |
|------|------|
| [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt)（`openwrt-25.12` 分支） | 本项目唯一固件源码，百里 RE-CP-03 已获官方支持，无需私有 fork |
| [openwrt/openwrt](https://github.com/openwrt/openwrt) | ImmortalWrt 的上游，mt76 无线驱动与 WED 硬件卸载的源头 |

### 插件来源（PLUS 版）

| 项目 | 说明 |
|------|------|
| [vernesong/OpenClash](https://github.com/vernesong/OpenClash) | OpenClash 插件源码 |
| [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) | PassWall2 插件源码 |
| [Openwrt-Passwall/openwrt-passwall-packages](https://github.com/Openwrt-Passwall/openwrt-passwall-packages) | xray / sing-box 等依赖包 feed |
| [sirpdboy/luci-app-partexp](https://github.com/sirpdboy/luci-app-partexp) | 分区扩容插件 |
| [ones20250/packages](https://github.com/ones20250/packages) | wolultra 网络唤醒增强插件 |

### GitHub Actions 组件

[softprops/action-gh-release](https://github.com/softprops/action-gh-release) · [ophub/delete-releases-workflows](https://github.com/ophub/delete-releases-workflows) · [P3TERX/ssh2actions](https://github.com/P3TERX/ssh2actions)

> 若原作者认为本仓库的引用方式有不妥之处，请提 Issue 联系处理。

## 🚀 自定义编译

### 修改编译配置

| 配置文件 | 作用范围 |
|----------|----------|
| `Config/MT798X-WIFI-YES.txt` | 目标平台与设备型号 |
| `Config/GENERAL_AX6000.txt` | 通用配置，PURE / PLUS 两个版本共用 |
| `Config/GENERAL_AX6000_PLUS.txt` | Plus 版增量配置，仅 PLUS 生效 |

### 触发编译

- **本仓库变更即编译**：main 分支有任何推送（改配置、加插件）立即触发编译，不等定时检测。
- **每 6 小时检测上游更新**：每 6 小时自动比对 immortalwrt openwrt-25.12 分支与插件仓库（PLUS 版含 OpenClash / PassWall2 等）相对上次 Release 是否有新 commit——**有变化立即编译**，均无变化则跳过不重复出包，上游修复最迟 6 小时内跟进。发布时 Release 正文会自动附带**本次相对上次的上游提交列表**，一眼看清更新了什么。
- **每日清理**：每天早上 6 点（北京时间）`Auto-Clean` 清理旧 Release（保留最近 100 个）与旧运行记录，完成后也会触发一次检测。
- **手动编译**：Actions → `MTK-ALL` → Run workflow，同时构建 PURE 与 PLUS，手动触发跳过上游比对、永远直接编译。
- **配置验证**：Actions → `WRT-TEST`，仅生成最终 `.config` 不编译固件，几分钟出结果。

---

## ⚠️ 免责声明

刷机有风险，操作需谨慎。

本项目固件仅供学习与研究使用，请确认设备型号匹配（**仅适用于京东云百里 AX6000 / RE-CP-03**）并提前备份数据。
因刷机造成的设备损坏或数据丢失，作者不承担任何责任。
