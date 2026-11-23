# 剩余工作清单

来源：2026-11-22 的整树审查（10 个问题 + 6 个低优先级事项）与分批方案。
本文件是进度的唯一可信来源：每完成一项就更新状态，避免会话中断后丢失进度。

状态标记：`[x]` 已完成　`[~]` 进行中　`[ ]` 未开始

## 第 1 批：WebUI 与脚本（2026-11-22 完成）

- [x] 高2 WebUI 写文件改为 base64 传参，内容不再经过 shell 解析（`webui/src/utils/bridge.ts`）
- [x] 高3 日志页先转义再高亮，杜绝 `v-html` 注入（`webui/src/views/LogViewerView.vue`）
- [x] 高4 读取/解析失败直接报错并禁止回写，rules.yaml 不再被空对象覆盖（`bridge.ts`、`ConfigEditorView.vue`）
- [x] 中8 卸载脚本不再擅自打开 Oiface / Joyose（`module/uninstall.sh`）
- [x] 低 QQ 群号修正为 1036909137（`HomeView.vue`）

产物：`/sdcard/cccodroid/yumi-2.0.2-238-20261122-2344.zip`（本机编译，含上述改动）

## 第 2 批：Rust 核心（2026-11-23 完成）

- [x] 高1 异常退出不恢复 CPU 状态：接管前把原始 governor / 频率区间落盘（`cpufreq_baseline.conf`），启动时先恢复；补 SIGTERM / SIGINT 处理，卸载脚本也会按快照恢复
- [x] 中5 温度封顶：按 `core_temp_threshold` / `core_temp_throttle_perf` 真正生效（带回差 2℃），默认 0 = 关闭
- [x] 中6 监控线程失败后按 1s→30s 退避重试，不再一次错误就永久停摆
- [x] 中7 rules.yaml 改为监听所在目录，兼容"写临时文件再改名"的原子替换
- [x] 中9 config.yaml 解析失败时记录错误日志，不再静默使用默认参数

验证：本机编译通过（Rust 1.100 + 稳定版解锁 build-std），单元测试 15 项全过（新增基线解析、温度回差共 3 项）。

产物：`/sdcard/cccodroid/yumi-2.0.2-238-20261123-0027.zip`
SHA256：`5df6ee207a8946b72c992fee0265f7196097da690ae637fe882d27e9d933516e`

### 真机测试记录（2026-11-23 00:37，一加 13T）

自动化脚本 `/sdcard/cccodroid/batch2-selftest.sh` 通过 Shizuku(root) 执行，结果：**18 PASS / 3 FAIL / 0 SKIP**。
3 个 FAIL 均为同一原因：快照在开机瞬间记录的 governor 是 `performance`，恢复后系统自身把 governor 改回 `walt`。
频率上下限全部精确恢复；governor 差异属于设备系统行为（系统服务持续使用 walt），不影响恢复功能。

| 测项 | 结果 | 证据 |
|---|---|---|
| 基线快照生成 | PASS | `cpufreq_baseline.conf` 含 policy0/6 原始 governor 与频率 |
| 正常停止恢复 | PASS | 停止后频率恢复 384000-3532800 / 1017600-4320000，快照删除 |
| kill -9 强杀恢复 | PASS | 启动日志 `已恢复上次异常退出前的 CPU 原始状态`，新快照与原值一致 |
| uninstall.sh 恢复 | PASS | 强杀后执行卸载脚本，两个 policy 均恢复原始区间 |
| rules.yaml 原子替换热重载 | PASS | 干净复测：`reload_ok=1 parse_error=0` |
| 配置损坏日志 | PASS | `Failed to read config ... Starting with defaults`，进程仍正常启动 |
| 温度封顶 | PASS | 阈值改 20℃ 后真实日志 `capping perf at 0.30`；恢复阈值后 `removing thermal cap` |
| 监控重试 | 观察项 | 正常使用期间 0 次重试；未做故障注入（无法安全制造 eBPF 故障） |

另注：当时刷入模块会用包内默认值覆盖 `config.yaml` / `rules.yaml`。该问题已在工程化补强中修复
（`customize.sh` 升级时保留旧配置），默认日志语言也已改为 `zh`。

## 第 3 批：清理（2026-11-23 完成）

- [x] 删除 `webui/src/stores/counter.ts`、未调用的 `getAvailableFreqs`（bridge + mock）、未使用的 lodash 依赖
- [x] 清理 Fluent 中 24 个无人使用的键（中英各剩 79 个，Fluent 语法解析 0 错误）
- [x] u32 乘法溢出防护：`jank_cooldown_frames * 3`、`upgrade_cooldown_after_downgrade * backoff` 改 `saturating_mul`
- [x] 路径转 UTF-8 的 `unwrap` 改容错（`logger.rs`、`utils.rs`、`scheduler/mod.rs`）
- [x] eBPF panic handler 改为 `loop { spin_loop() }`，去掉 `unreachable_unchecked`
- [x] 附带加固：配置目录监视补上 CREATE / MOVED_TO，原子替换保存也能触发热重载

验证：Rust 编译通过、当时 15 项测试全过（加入温度防抖后为 16 项）；WebUI `npm run build` 与 `npm run type-check` 均通过。

## 当时漏归批的两项（2026-11-23 完成）

- [x] 中10 `disable_boost.sh` 默认拒绝执行，必须显式设置 `YUMI_ALLOW_THERMAL_DISABLE=1` 才继续，并在文件头写明风险
- [x] 低 CI 增加 `npm run type-check`；同时把 TypeScript 从 7.0 降到 5.9.3（`vue-tsc 3.3.7` 不兼容 TS 7 的包结构，升级后检查会直接报错）

## 默认语言调整（2026-11-23）

- [x] 包内 `module/config/config.yaml` 的 `language` 改为 `zh`
- [x] 代码缺省语言（`default_language()` / 配置读取失败兜底）改为 `zh`
- [x] 当前设备上的配置已切为 `zh` 并重启验证：日志输出中文（`[CLG] … 初始化`、`模式变更`）

产物（第 3 批）：`/sdcard/cccodroid/yumi-2.0.2-238-20261123-0047.zip`
SHA256：`86fc6aeefd751fbd286274b135464a22e84d65b2c3cced226382c23e1799cef9`
该包已于 2026-11-23 01:17 刷入并通过冒烟测试（见下）。

### 第 3 批刷入后冒烟测试（2026-11-23 01:17）

| 检查项 | 结果 |
|---|---|
| 二进制哈希 | `eee0b9fd…`，与包内一致 |
| 守护进程 | 运行中（PID 8297） |
| 日志语言 | 全中文（统一启动中 / 模式变更 / CLG 初始化） |
| 基线快照 | 已生成，含 policy0 / policy6 |
| 调频接管 | CLG 已接管 2 个集群，频率受限 |
| 模式切换 | launcher → powersave 正常 |
| WebUI 产物 | `index-BTYfLsXx.js` 哈希与本机构建一致 |
| 第三批标记 | UTF-8 容错字符串、`disable_boost.sh` 保护门均在 |
| 错误 / 重试 | 0 / 0 |

观察项：开机第 9 秒的日志出现过一次 98.8℃；当前实际传感器（cpu-1-0-1）稳定在 35–36℃。
温控默认关闭，无影响。

已处理：温度封顶加入防抖——连续两次超阈值才封顶，解除仍然立即生效（保护优先）。
单次异常读数只会让计数 +1，下一次正常回落即清零。

## 工程化补强（2026-11-23）

- [x] 刷入升级保留用户配置：`module/customize.sh` 备份旧模块的 `config.yaml` / `rules.yaml`（已用沙箱模拟验证）
- [x] 本机构建脚本 `scripts/build-local.sh`：自动识别 nightly / 稳定版，串联 WebUI、编译、测试与打包
- [x] 真机脚本：`scripts/device-smoke.sh`（只读）、`scripts/device-selftest.sh`（深度，需 `--yes`）
- [x] 文档审计与更新：`CLAUDE.md`、中英文 README、`docs/monitor-recovery.md`、`docs/agents/issue-tracker.md`、changelog
- [x] 真机验证：`device-smoke.sh` 9 项全过；`device-selftest.sh --yes` 13 PASS / 0 FAIL / 1 SKIP（温控实测需 `YUMI_TEST_GAME`）
- [ ] 待办：应用工具包升级后 Rust 模块被移除；重装「Rust 语言」模块后复验 `scripts/build-local.sh` 全流程
