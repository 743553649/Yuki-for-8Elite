yumi-module-starting = yumi-module Unified Starting...
scheduler-module-started = Scheduler module started.
scheduler-module-start-failed = Failed to start scheduler module: { $error }
monitor-module-crashed = Monitor module crashed: { $error }
monitor-module-started = Monitor module started.
monitor-starting = Starting yumi-monitor module...
monitor-initial-config-failed = [Main] Failed to read initial config: { $error }.
    Using default.
monitor-screen-watcher-failed = [Main] Screen state watcher thread crashed: { $error }
monitor-config-watcher-failed = [Main] Config watcher thread crashed: { $error }
monitor-fps-crashed = [Main] FPS Monitor crashed: { $error }
monitor-cpu-crashed = [Main] CPU Load Monitor crashed: { $error }
monitor-rlimit-memlock-failed = [Main] Failed to raise RLIMIT_MEMLOCK. eBPF maps might fail to load.

# --- Main & Monitor ---
app-detect-config-watch = [AppDetect] Started watching config file: { $path }
app-detect-change-detected = [AppDetect] Change detected, debouncing (100ms)...
app-detect-reloading = [AppDetect] Debounce finished. Reloading config...
app-detect-load-failed = [AppDetect] Failed: { $error }. Using default.
app-detect-reload-success = [AppDetect] Config reloaded successfully.
app-detect-loop-started = [AppDetect] App detection loop started (3000ms poll).
app-detect-screen-changed = [AppDetect] Screen state changed: { $old } -> { $new }
app-detect-mode-change-pkg = [AppDetect] Mode change: { $old } -> { $new } ({ $pkg })
app-detect-ime-auto = [AppDetect] Auto-detected IME: { $pkg }
app-detect-ime-fallback = [AppDetect] Failed to auto-detect IME, using fallback list.

# --- AppDetect ---
screen-state-change-detected = [Screen] State change detected via '{ $source }'.
screen-state-changed-value = [Screen] Screen state changed: { $state }
screen-netlink-started = [Screen] Started netlink-sys socket listener.

# --- ScreenDetect ---

scheduler-ipc-started = [Scheduler] IPC Channel listener started.
scheduler-mode-change-request = [Scheduler] Mode change request: { $old } -> { $new } (Pkg: { $pkg }, Temp: { $temp })
scheduler-channel-closed = [Scheduler] Channel closed! Thread exiting.
scheduler-ipc-panic = [Scheduler] IPC thread panicked, releasing CPU control.
scheduler-doze-enable = [Scheduler] Screen OFF: Enabling Extreme Doze mode (Restricting CPU max performance).
scheduler-doze-restore = [Scheduler] Screen ON: Restoring previous performance constraints.

# --- Scheduler ---
config-reloading = [Config] Config file change detected, reloading...
config-reloaded-success = [Config] Config reloaded successfully.
config-reload-fail = [Config] Config reload failed: { $error }
config-watch-error = [Config] Failed to watch config directory: { $error }
config-apply-tweaks-failed = [Config] Failed to apply reloaded system tweaks: { $error }

# --- Scheduler: Config Watcher ---
sysfs-open-failed = [SysFS] Failed to open { $path }: { $error }
sysfs-umount2-failed = [SysFS] umount2({ $path }) failed: { $error }
sysfs-write-freq-failed = [SysFS] Write freq { $freq } failed: { $error }

# --- SysFS (shared FastWriter) ---
clg-init = [CLG] P{ $pid } init | cores={ $cpus } | available={ $fmin }-{ $fmax } MHz | P={ $perf } -> range { $freq } kHz
clg-activated = [CLG] CPU Load Governor activated, taking over { $count } cluster(s)
clg-no-clusters = [CLG] CPU Load Governor: no valid clusters found, staying inactive
clg-deactivated = [CLG] CPU Load Governor deactivated
clg-config-reloaded = [CLG] config hot-reloaded | up={ $up } down={ $down } floor={ $floor } ceil={ $ceil }
clg-perf-clamped = [CLG] config perf_floor > perf_ceil ({ $floor } > { $ceil }), clamped perf_floor to perf_ceil
clg-tick-log = [CLG] P{ $pid } util={ $util }% perf={ $perf } range={ $freq } kHz boost={ $boost } kHz

# --- CLG ---
fas-auto-capacity = [FAS] auto capacity weight:
fas-auto-capacity-core = [FAS]   P{ $pid }: cap={ $cap } -> w={ $weight }
fas-policy-init = [FAS] P{ $pid } { $min }-{ $max } MHz | w={ $weight }
fas-init-summary = [FAS] init | { $fps }fps margin:{ $margin } clusters:{ $clusters } P:{ $perf } profiles:{ $profiles }
fas-app-switch = [FAS] app switch ({ $ms }ms) | P -> { $perf }
fas-loading-start = [FAS] entering loading state ({ $frames } frames, { $ms }ms) | P { $old_perf } -> { $new_perf }
fas-loading-exit = [FAS] exit loading state | P -> { $perf }
fas-gear-switch = [FAS] gear switch { $old } -> { $new }fps | P -> { $perf }
fas-low-perf-upgrade = [FAS] low-load steady frame upgrade | P={ $perf } avg={ $avg } stddev={ $stddev } -> { $fps }fps
fas-downgrade-boost = [FAS] downgrade boost | avg:{ $avg } | P { $old } -> { $new } (inc={ $inc })
fas-boost-expired = [FAS] boost expired, fast-tracking downgrade (confirm={ $confirm })
fas-floor-rescue = [FAS] floor-rescue | stuck { $frames } frames at P={ $old }, avg:{ $avg } -> P:{ $new }
fas-tick-log = [FAS] { $target }fps avg:{ $avg } | { $ms }ms ema:{ $ema } | err:{ $err_ema }/{ $err_inst } | { $act } | P:{ $perf } fg_util:{ $util }{ $cd }{ $damp }{ $temp }{ $offset }
fas-set-game = [FAS] set_game | pkg={ $pkg } | gears={ $gears } | target={ $target }fps
fas-no-profile = [FAS] no per-app profile for '{ $pkg }', using global gears { $gears }
fas-pid-reloaded = [FAS] PID coefficients hot-reloaded: Kp={ $kp } Ki={ $ki } Kd={ $kd }
fas-rules-reloaded = [FAS] rules hot-reloaded (margin={ $margin }, floor={ $floor }, ceil={ $ceil }, profiles={ $profiles })

# --- FAS ---
apply-cpu-idle-governor-start = CPU idle governor settings applied.
apply-io-settings-start = I/O settings applied.
main-config-watch-thread-create = Main config watcher thread created.

# --- Scheduler: Settings ---
log-level-updated = Log level updated to: { $level }

# --- Logger ---
config-load-failed = [Config] Failed to read config { $path }: { $error }. Starting with defaults
baseline-restored = [Baseline] Found a snapshot from an unclean exit; restored original CPU state
baseline-restore-failed = [Baseline] Failed to restore original CPU state: { $error }
signal-handler-install-failed = [Main] Failed to install shutdown signal handlers: { $error }
scheduler-shutdown-signal = [Scheduler] Shutdown signal received; restoring CPU state
monitor-thread-panicked = [Main] Monitor thread panicked
scheduler-thread-panicked = [Main] Scheduler thread panicked
yumi-module-stopped = yumi-module stopped
monitor-fps-retrying = [Main] FPS monitor will retry in { $secs }s: { $error }
monitor-cpu-retrying = [Main] CPU monitor will retry in { $secs }s: { $error }
fas-temp-throttle-on = [FAS] Temperature { $temp }C reached threshold { $threshold }C; capping perf at { $perf }
fas-temp-throttle-off = [FAS] Temperature fell to { $temp }C; removing thermal cap
# --- Maintenance ---
