#!/system/bin/sh
#
# 真机冒烟检查（只读，不修改任何状态）。
# 刷入模块并重启后运行，确认守护进程、配置、调频接管与日志基本正常。
#
# 用法（root）：
#   priv 'sh /path/to/scripts/device-smoke.sh'
# 可用环境变量覆盖模块路径：
#   YUMI_MODULE_DIR=/data/adb/modules/yumi
#
# 退出码：0 全部通过；1 存在失败项。
set -u

M="${YUMI_MODULE_DIR:-/data/adb/modules/yumi}"
LOG="$M/logs/daemon.log"
PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

if [ ! -d "$M" ]; then
    echo "FAIL: 模块目录不存在: $M"
    exit 1
fi
ok "模块目录存在"

if [ -f "$M/module.prop" ]; then
    ok "module.prop 存在"
else
    bad "module.prop 缺失"
fi

PID=$(pidof yumi 2>/dev/null | awk '{print $1}')
if [ -n "$PID" ]; then
    ok "守护进程运行中 (PID $PID)"
else
    bad "守护进程未运行"
fi

if [ -f "$LOG" ]; then
    ok "日志文件存在"
else
    bad "日志文件缺失"
    echo
    echo "=== 结果: PASS=$PASS FAIL=$FAIL ==="
    exit 1
fi

echo "配置: $(grep -m1 'language:' "$M/config/config.yaml" 2>/dev/null || echo '未找到 language')"

if [ -f "$M/cpufreq_baseline.conf" ] && grep -q '^policy ' "$M/cpufreq_baseline.conf" 2>/dev/null; then
    ok "CPU 基线快照已生成"
else
    bad "缺少 CPU 基线快照（调频尚未接管或写入失败）"
fi

if grep -qE 'CPU 负载调频器已激活|CPU Load Governor activated' "$LOG" 2>/dev/null; then
    ok "CLG 已接管调频"
else
    bad "日志中未看到 CLG 接管"
fi

if grep -qE 'yumi-module (统一启动中|Unified Starting)|模块已启动|module started' "$LOG" 2>/dev/null; then
    ok "启动日志正常"
else
    bad "未找到正常启动日志"
fi

ERRORS=$(tail -400 "$LOG" 2>/dev/null | grep -cE '\[ERROR\]' || true)
if [ "${ERRORS:-0}" -eq 0 ]; then
    ok "最近日志无 ERROR"
else
    bad "最近日志有 ${ERRORS} 条 ERROR"
fi

RETRIES=$(grep -cE '秒后重试|will retry in' "$LOG" 2>/dev/null || true)
if [ "${RETRIES:-0}" -eq 0 ]; then
    ok "没有监控重试记录"
else
    bad "出现 ${RETRIES} 次监控重试，请查看日志"
fi

echo
echo "=== 结果: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ]
