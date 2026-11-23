# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

yumi 是一个 Android CPU 调度模块（Magisk / KernelSU 刷入），由三部分组成：

- **Rust 守护进程**（根包 `yumi`）——监控采集 + 调频决策
- **三个 eBPF 探针**（`yumi-ebpf`，no_std）——CPU 负载与渲染帧采集
- **Vue 3 WebUI**（`webui/`）——模式切换、应用规则、YAML 配置、日志查看

打包后是一个模块 zip，安装到设备上的模块根目录（通常 `/data/adb/modules/yumi`），运行时布局：

```
<module>/core/bin/yumi      # 守护进程
<module>/webroot/           # WebUI 构建产物
<module>/config/config.yaml # 全局配置（模式、I/O、语言、日志级别）
<module>/rules.yaml         # 调度规则（global_mode、app_modes、fas_rules）
<module>/current_mode.txt   # 当前模式（守护进程写入）
<module>/cpufreq_baseline.conf # 接管前的原始 governor/频率快照（异常退出恢复用）
<module>/logs/daemon.log    # 滚动日志（5MB × 3）
```

## 常用命令

### 本机构建（Android 设备，无需 NDK）

```sh
./scripts/build-local.sh
```

前置：应用「扩展 → 工具包模块」里的「Rust 语言」、预编译 `bpf-linker 0.11.1` 在 PATH，以及 Node / zip / sha256sum。
脚本会自动识别稳定版工具链并加 `RUSTC_BOOTSTRAP=1` 与 cargo 频道覆盖，解锁 `-Z build-std`。
可用 `SKIP_WEBUI=1`、`SKIP_TESTS=1` 跳过对应步骤。
注意：应用工具包升级后 Rust 模块可能被移除，`pkg` 会提示重装。

### 构建模块 zip（CI / Linux 交叉编译）

前置：Rust nightly + `rust-src`、`aarch64-linux-android` 与 `bpfel-unknown-none` 目标、预编译 `bpf-linker`（CI 固定 0.11.1）在 PATH、Android NDK（CI 用 r29）+ `cargo-ndk`、Node 20.19+ 或 22.12+，以及先在 `webui/` 里 `npm install`。

```sh
cargo xtask build      # 别名：cargo xtask b
```

流程：`webui`: `npm run build` → `cargo +nightly ndk ...` 交叉编译守护进程 → 拷贝 `module/`、WebUI 产物和二进制 → 生成 `output/yumi-<Cargo 版本>-<提交总数>-<YYYYMMDD-HHMM>.zip`。

`build.rs` 会在编译守护进程时自动用 `cargo build -Z build-std=core --target bpfel-unknown-none` 编译 `yumi-ebpf` 的三个 probe，拷成 `$OUT_DIR/{cpu,fps-ring,fps-perf}.ebpf`。缺 `bpf-linker` 会直接 panic（构建期不做自动安装）。

### 测试

```sh
cargo test -p yumi --bin yumi --locked
cargo test -p yumi --bin yumi --locked perf_record_wrapping_at_every_offset   # 单个测试
```

测试会解析 `build.rs` 产出的真实 eBPF ELF（`monitor/mod.rs` 里用 `aya_obj` 校验程序/map 隔离），因此同样需要 nightly + `bpf-linker`，不是纯逻辑单测。

刷入真机后的验证脚本：

```sh
sh scripts/device-smoke.sh          # 只读检查：进程、配置、快照、CLG 接管、日志
sh scripts/device-selftest.sh --yes # 深度自检：停启守护进程、kill -9 恢复、规则热重载、配置损坏日志
```

`device-selftest.sh` 会临时替换 `rules.yaml` / `config.yaml`，用 trap 保证退出时原子还原。

### WebUI

```sh
cd webui
npm install
npm run dev          # 浏览器里 window.ksu 不存在时自动用 MockBridge
npm run type-check   # vue-tsc
npm run lint         # ESLint（flat config，正确性问题）
npm run format:check # Prettier 格式检查
npm run test         # Vitest 单元测试
npm run build        # 产出 dist/，由 xtask 拷进 webroot/
```

CI 在打包前依次执行：`cargo fmt --check`、`cargo clippy -D warnings`、WebUI `type-check/lint/format:check/test`、`npm audit`、`cargo test`。
每周还有 `security-audit.yml` 定时跑 `cargo audit` 与 `npm audit`。

## 架构

### 进程与线程模型（`src/main.rs`）

`main` 读取 `config/config.yaml`、初始化日志后建立一个 `mpsc::channel::<DaemonEvent>`，先启动 Scheduler 线程（持有接收端），再在 `monitor_core` 线程里启动 Monitor（持有发送端），最后依次 `join` Monitor 与 Scheduler 两个线程（退出时要等恢复逻辑跑完）。若带第一个命令行参数，会先 `chdir` 到该目录。

**Monitor**（`src/monitor/`）各线程向同一通道发事件：

- `app_detect`：主循环（阻塞）；读 `top-app` cgroup 判断前台应用，带防抖与输入法过滤，决定模式并产生 `ModeChange`
- `fps_monitor`：aya uprobe 挂在目标进程的 `queueBuffer`，优先 RingBuf，创建失败（EINVAL/EOPNOTSUPP/ENOSYS）才降级 PerfEventArray
- `cpu_monitor`：aya `sched_switch` tracepoint，每 200ms 产生 `SystemLoadUpdate`
- `screen_detect`：Netlink uevent 监听亮灭屏
- `config_watcher`：inotify 监听 `rules.yaml` 所在目录（兼容“写临时文件再改名”），产生 `ConfigReload`

事件定义在 `src/common.rs`（`DaemonEvent`）。

**Scheduler IPC 线程**（`src/scheduler/mod.rs`）同时持有 `FasController` 和 `CpuLoadGovernor`，循环用 200ms 超时收事件：

- 任何时刻只允许一个控制器持有频率；交接前必须先释放旧控制器（恢复接管前的 governor 与 min/max 频率），再让新控制器做快照
- `MonitorHealth` 在对应数据超过 2 秒未更新时判失效，立即释放相关控制；恢复时重新建立采样基线
- 息屏进入 Doze：强制用 `powersave` 的 CLG 配置，`perf_ceil` 封到 0.40、降频极快；亮屏恢复
- 模式为 `fas` 且亮屏时由 FAS 调频，其余模式走 CLG
- 循环 panic 或通道关闭时也要恢复频率状态，避免残留
- 接管前把原始 governor/频率写入 `cpufreq_baseline.conf`；收到 SIGTERM/SIGINT 时先恢复再退出；启动时若发现快照先恢复，防止把已受限的值当成原始值

**FAS**（`src/scheduler/fas/`）：PID 输出驱动 `perf_index`（0~1），按 `capacity_weight` 映射到各 CPU 簇频率；子模块分别负责帧窗口、档位状态（升降档确认/冷却）、jank 冷却、加载场景、PID、策略写入。

**CLG**（`src/scheduler/cpu_load_governor.rs`）：按簇用负载 EMA、升降频速率限制、headroom 计算区间；`freq_range_steps_below` 控制下限相对目标频点下探几档。

**sysfs 层**（`src/scheduler/cpufreq.rs`、`src/scheduler/scheduler.rs`）：包装 cpufreq policy 的频率区间写入、governor 切换、容量权重探测，以及 I/O 与 CPU idle 等系统调整。

### eBPF（`yumi-ebpf/`）

- 三个独立二进制：`cpu`、`fps-ring`、`fps-perf`。map/程序必须保持隔离（测试会断言 CPU 探针没有 `RING_BUF`，FPS 探针没有 `CORE_IDLE_TIME`），不要合并
- FPS uprobe 的 libgui 候选符号**顺序不可调换**：Android 16 及以下 → 16 回合并的 `sp<GraphicBuffer>&&` → Android 17 的 `sp<GraphicBuffer>`/`sp<Fence>` → 最后 `ANativeWindow::hook_queueBuffer`。Android 16 上 17 的重载也存在但不在渲染路径，先试会“附加成功却收不到帧”。详见 `docs/monitor-recovery.md`
- 用户态只发送新产生的帧间隔，过滤 1ms~200ms；PID 切换或长时间无帧后重置基线，不重放旧帧
- release profile 对 eBPF 包强制 `opt-level = 2`（BPF verifier 不能接受 `-Oz` 和调试栈溢出）

### 配置与热重载

- `config/config.yaml`：`meta`（loglevel / language，语言默认 `zh`）、`function`（IOOptimization、CpuIdleScalingGovernor）、各模式 `powersave` / `balance` / `performance` / `fast` 的 `cpu_load_governor` 参数
- `rules.yaml`（模块**根目录**，不在 `config/` 下）：`global_mode`、`app_modes`、`ignored_apps`、`fas_rules`（`fps_gears`、`pid`、`per_app_profiles` 等）
- 两个文件都有 `schema_version`（缺失按 0 处理）：旧规则读取时会自动把 `per_app_margins` 迁移到 `per_app_profiles`；新增字段或改语义时递增版本并在 `migrate()` 里补迁移
- 两个文件都支持 inotify 热重载；日志语言与级别也随 `config.yaml` 热切换
- 温度封顶：`fas_rules.core_temp_threshold`（默认 0 = 关闭）连续两次采样超阈值才封顶，`core_temp_throttle_perf` 为封顶后的 perf 上限；解除不做延迟
- 模式字符串 `fas` 表示帧感知调度，其余值对应 `config.yaml` 里的 CLG 模式；当前模式写入 `current_mode.txt`

### WebUI（`webui/`）

- Vue 3 + Vite + Vant（自动按需引入）+ Pinia + vue-i18n，使用 **hash 路由**
- `vite.config.ts` 的 `base: './'` 是必须的，否则 WebUI 容器里资源加载失败
- `src/utils/bridge.ts` 是唯一的数据通道：通过 KernelSU 的 `exec` 执行 `cat` / base64 写入 / `pm list packages` 等命令，路径硬编码为 `/data/adb/modules/yumi`；开发环境（无 `window.ksu`）走 `src/utils/mock.ts`
- 页面：`HomeView`（模式切换）、`AppRulesView`（per-app 规则）、`ConfigEditorView`（YAML 文本编辑）、`LogViewerView`（读 `logs/daemon.log`）
- WebUI 的 i18n（`src/i18n/locales/`）与守护进程的 Fluent 翻译（`module/config/i18n/*.ftl`）是两套，改动界面文案时别只改一边

### 打包与发布

- `xtask/src/main.rs` 负责编译 WebUI / 核心并打 zip；zip 名中的数字是 `git rev-list --count HEAD`
- `scripts/build-local.sh` 是本机构建入口；`module/customize.sh` 在升级安装时保留旧模块的 `config.yaml` 与 `rules.yaml`
- `origin` 是自己的仓库 `743553649/Yuki-for-8Elite`，`upstream` 是 `imacte/yumi`；同步上游用 `git fetch upstream && git merge upstream/main`
- 发版时同步 `Cargo.toml`、`module/module.prop`、`updateInformation/update.json` 三处版本号；正式版 Release 会额外上传固定名称 `yumi-latest.zip`，供 `update.json` 的 `releases/latest/download/yumi-latest.zip` 使用
- `.github/workflows/build.yml`：推 `main` 自动发布预发行版（标签 `yumi-v<版本>-pre.<run_number>`，指向本次提交）；推送版本标签发布正式版，且标签版本必须与 `Cargo.toml` 的 `version` 完全一致；PR 只产出 artifact
- 正式发版时同步更新 `updateInformation/update.json` 的 `version` / `versionCode` / `zipUrl` 与 `module/module.prop`；当前版本号在 `Cargo.toml`

## 注意事项

- **模块根目录是按可执行文件位置回推的**（`core/bin/yumi` 往上三级），在别处直接运行二进制会导致配置、日志路径全错
- 频率单位统一为 **kHz**（日志与配置都是），温度传感器读数是毫摄氏度，代码里会除以 1000
- 调频失败不能让状态卡死：任何提前返回/panic 路径都要考虑恢复 governor 与频率上下限
- WebUI 写文件走 `bridge.ts` 的 base64 传参，不要再拼接 shell 字符串；读取/解析失败时必须拒绝回写
- 本机工具链（Rust / bpf-linker）可能随应用工具包更新失效；构建前先跑 `scripts/build-local.sh`，缺依赖会给出明确提示

## Agent skills

### Issue tracker

当前工作队列维护在 `docs/remaining-work.md`；`.scratch/<feature>/` 的 issue 流程尚未启用（详见 `docs/agents/issue-tracker.md`）。

### Domain docs

单上下文：仓库根目录一个 `GLOSSARY.md`，加 `docs/adr/`。详见 `docs/agents/domain.md`。
