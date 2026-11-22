#!/system/bin/sh

# 卸载说明：
# 正常的停止由守护进程自己恢复 CPU 状态；如果上次是异常退出（被强杀 / 掉电），
# 模块目录里会留下 cpufreq_baseline.conf，这里按它把 governor 与频率区间写回去，
# 避免卸载后手机继续停留在被限制的频率上直到重启。
MODDIR=${MODDIR:-${0%/*}}

# 先请守护进程正常退出（收到 SIGTERM 后它自己也会恢复一次），留一点时间
killall yumi > /dev/null 2>&1
sleep 1

BASELINE="$MODDIR/cpufreq_baseline.conf"
if [ -f "$BASELINE" ]; then
  while read -r kind a b c d; do
    case "$kind" in
      policy)
        BASE="/sys/devices/system/cpu/cpufreq/policy$a"
        [ -d "$BASE" ] || continue
        # 先放宽上限再写下限，避免中间态 min > max 被内核拒绝
        echo "$d" > "$BASE/scaling_max_freq" 2>/dev/null
        echo "$c" > "$BASE/scaling_min_freq" 2>/dev/null
        echo "$b" > "$BASE/scaling_governor" 2>/dev/null
        ;;
      perfmgr)
        echo "$b" > "$a" 2>/dev/null
        ;;
    esac
  done < "$BASELINE"
fi

echo "卸载yumi调度成功完成 请重启手机"
