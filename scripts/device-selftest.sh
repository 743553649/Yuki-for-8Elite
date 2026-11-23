#!/system/bin/sh
#
# 真机自检（会修改运行状态，必须显式确认）。
#
# ⚠️ 这个脚本会：
#   1. 停止 / 启动守护进程若干次（期间 CPU 短暂回到默认调频）
#   2. 临时替换 rules.yaml / config.yaml（结束后用备份原子还原）
#   3. 用 kill -9 模拟异常退出，验证基线快照恢复
#
# 用法（root）：
#   priv 'sh /path/to/scripts/device-selftest.sh --yes'
#
# 可选环境变量：
#   YUMI_MODULE_DIR  模块目录（默认 /data/adb/modules/yumi）
#   YUMI_TEST_GAME   若设置，额外测试温度封顶（会启动该游戏再强制关闭）
#
# 退出码：0 全部通过/跳过；1 存在失败项。
set -u

if [ "${1:-}" != "--yes" ]; then
    echo "该脚本会停止/启动守护进程并临时修改配置。"
    echo "确认理解后重新执行：sh $0 --yes"
    exit 1
fi

M="${YUMI_MODULE_DIR:-/data/adb/modules/yumi}"
LOG="$M/logs/daemon.log"
STAMP=$(date +%Y%m%d-%H%M%S)
BK="/sdcard/cccodroid/yumi-selftest-backup-$STAMP"
mkdir -p "$BK" 2>/dev/null

cp "$M/rules.yaml" "$BK/rules.yaml" 2>/dev/null
cp "$M/config/config.yaml" "$BK/config.yaml" 2>/dev/null
cp "$M/cpufreq_baseline.conf" "$BK/baseline.conf" 2>/dev/null

PASS=0
FAIL=0
SKIP=0
ok()   { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
skip() { SKIP=$((SKIP + 1)); echo "SKIP: $1"; }

log_size() { wc -c < "$LOG" 2>/dev/null | tr -d ' '; }
new_log_since() { tail -c +$(( $1 + 1 )) "$LOG" 2>/dev/null; }
wait_log() { # pattern offset timeout
    _pat=$1; _off=$2; _tmo=${3:-8}; _i=0
    while [ $_i -lt $_tmo ]; do
        if new_log_since "$_off" | grep -qE "$_pat"; then return 0; fi
        sleep 1; _i=$((_i + 1))
    done
    return 1
}
daemon_pid() { pidof yumi 2>/dev/null | awk '{print $1}'; }
start_daemon() {
    if [ -z "$(daemon_pid)" ]; then
        if command -v setsid >/dev/null 2>&1; then
            setsid "$M/core/bin/yumi" >/dev/null 2>&1 < /dev/null &
        else
            nohup "$M/core/bin/yumi" >/dev/null 2>&1 < /dev/null &
        fi
        _i=0
        while [ $_i -lt 15 ] && [ -z "$(daemon_pid)" ]; do sleep 1; _i=$((_i + 1)); done
    fi
    sleep 3
}
stop_graceful() {
    _pid=$(daemon_pid)
    [ -z "$_pid" ] && return 0
    kill "$_pid" 2>/dev/null
    _i=0
    while [ $_i -lt 10 ] && [ -n "$(daemon_pid)" ]; do sleep 1; _i=$((_i + 1)); done
    [ -z "$(daemon_pid)" ]
}

restore_files() {
    if [ -f "$BK/rules.yaml" ]; then
        cp "$BK/rules.yaml" "$M/.rules.restore" && mv -f "$M/.rules.restore" "$M/rules.yaml"
    fi
    if [ -f "$BK/config.yaml" ]; then
        cp "$BK/config.yaml" "$M/.config.restore" && mv -f "$M/.config.restore" "$M/config/config.yaml"
    fi
}

cleanup() {
    restore_files
    sleep 1
    start_daemon
    echo "=== 结束：守护进程 PID=$(daemon_pid)，备份目录 $BK ==="
}
trap cleanup EXIT

echo "=== yumi 真机自检 $STAMP ==="
echo "binary: $(sha256sum "$M/core/bin/yumi" | awk '{print $1}')"
ORIG="$BK/baseline.conf"

# 用基线快照里的频率区间逐条核对当前 sysfs
check_freqs_match_baseline() {
    _label=$1
    _ok=1
    while read -r kind id _gov min max; do
        [ "$kind" = "policy" ] || continue
        _d="/sys/devices/system/cpu/cpufreq/policy$id"
        [ -d "$_d" ] || continue
        _cmin=$(cat "$_d/scaling_min_freq" 2>/dev/null)
        _cmax=$(cat "$_d/scaling_max_freq" 2>/dev/null)
        if [ "$_cmin" = "$min" ] && [ "$_cmax" = "$max" ]; then
            echo "   policy$id 已恢复 $_cmin-$_cmax"
        else
            echo "   policy$id 未恢复：期望 $min-$max，实际 $_cmin-$_cmax"
            _ok=0
        fi
    done < "$ORIG"
    [ "$_ok" -eq 1 ] && ok "$_label" || bad "$_label"
}

echo
echo "--- 1. 基线快照 ---"
if [ -s "$M/cpufreq_baseline.conf" ] && grep -q '^policy ' "$M/cpufreq_baseline.conf"; then
    ok "基线文件包含 policy 原始状态"
else
    bad "基线文件缺失或格式不对"
fi

echo
echo "--- 2. 正常停止恢复 ---"
OFF=$(log_size)
if stop_graceful; then ok "SIGTERM 后进程退出"; else bad "SIGTERM 后进程仍存活"; fi
sleep 1
check_freqs_match_baseline "正常停止后频率与基线一致"
if [ -f "$M/cpufreq_baseline.conf" ]; then bad "正常停止后快照未删除"; else ok "正常停止后快照已删除"; fi
if new_log_since "$OFF" | grep -qE '收到退出信号|Shutdown signal'; then
    ok "日志记录了退出信号"
else
    bad "日志没有退出信号记录"
fi
start_daemon

echo
echo "--- 3. 强杀恢复 ---"
if [ -f "$M/cpufreq_baseline.conf" ]; then ok "重启后重新生成快照"; else bad "重启后没有快照"; fi
sleep 2
OFF=$(log_size)
kill -9 "$(daemon_pid)" 2>/dev/null
sleep 1
if [ -f "$M/cpufreq_baseline.conf" ]; then ok "强杀后快照保留"; else bad "强杀后快照丢失"; fi
start_daemon
if wait_log '已恢复上次异常退出前的 CPU 原始状态|restored original CPU state' "$OFF" 8; then
    ok "启动时执行了恢复"
else
    bad "启动日志没有恢复记录"
fi

echo
echo "--- 4. 卸载脚本恢复 ---"
sleep 2
kill -9 "$(daemon_pid)" 2>/dev/null
sleep 1
sh "$M/uninstall.sh" > /dev/null 2>&1
sleep 1
check_freqs_match_baseline "uninstall.sh 按快照恢复频率"
start_daemon

echo
echo "--- 5. 规则文件原子替换 ---"
OFF=$(log_size)
cp "$M/rules.yaml" "$M/.rules.test"
printf '\n# selftest %s\n' "$STAMP" >> "$M/.rules.test"
mv -f "$M/.rules.test" "$M/rules.yaml"
if wait_log '重载成功|reloaded successfully' "$OFF" 8; then
    ok "原子替换触发热重载"
else
    bad "原子替换后没有重载日志"
fi
cp "$BK/rules.yaml" "$M/.rules.test"; mv -f "$M/.rules.test" "$M/rules.yaml"
sleep 2

echo
echo "--- 6. 配置损坏日志 ---"
if [ -f "$BK/config.yaml" ]; then
    stop_graceful
    OFF=$(log_size)
    printf 'meta: [\n' > "$M/config/config.yaml"
    start_daemon
    if wait_log '读取配置失败|Failed to read config' "$OFF" 8; then
        ok "损坏配置有明确错误日志"
    else
        bad "没有错误日志"
    fi
    if [ -n "$(daemon_pid)" ]; then ok "配置损坏时仍能启动"; else bad "配置损坏后启动失败"; fi
    stop_graceful
    cp "$BK/config.yaml" "$M/.config.test"; mv -f "$M/.config.test" "$M/config/config.yaml"
    start_daemon
else
    skip "没有配置备份"
fi

echo
echo "--- 7. 温度封顶（可选） ---"
if [ -n "${YUMI_TEST_GAME:-}" ]; then
    sed -e 's/^global_mode:.*/global_mode: "fas"/' \
        -e 's/^  core_temp_threshold:.*/  core_temp_threshold: 20.0/' \
        -e 's/^  core_temp_throttle_perf:.*/  core_temp_throttle_perf: 0.30/' \
        "$BK/rules.yaml" > "$M/.rules.test"
    OFF=$(log_size)
    mv -f "$M/.rules.test" "$M/rules.yaml"
    sleep 2
    monkey -p "$YUMI_TEST_GAME" -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 &
    if wait_log '温度封顶|capping perf at' "$OFF" 30; then
        ok "超过阈值后触发封顶"
    else
        skip "未观察到封顶（游戏可能没有产生帧）"
    fi
    am force-stop "$YUMI_TEST_GAME" > /dev/null 2>&1
    cp "$BK/rules.yaml" "$M/.rules.test"; mv -f "$M/.rules.test" "$M/rules.yaml"
    sleep 2
else
    skip "未设置 YUMI_TEST_GAME，跳过温控实测"
fi

echo
echo "--- 8. 监控重试观察 ---"
RETRIES=$(grep -cE '秒后重试|will retry in' "$LOG" 2>/dev/null || true)
if [ "${RETRIES:-0}" -eq 0 ]; then
    ok "没有监控重试记录"
else
    bad "出现 $RETRIES 次监控重试，请查看日志"
fi

echo
echo "=== 汇总 PASS=$PASS FAIL=$FAIL SKIP=$SKIP ==="
[ "$FAIL" -eq 0 ]
