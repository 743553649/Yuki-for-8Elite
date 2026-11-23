#!/system/bin/sh
#
# ########################################################################################
#   yumi 模块安装脚本
#   作者: yuki
# ########################################################################################

# --- 模块路径和工具 ---
# $MODPATH 是 Magisk 传入的模块安装路径

# --- 自动检测 BusyBox (保留以备将来可能使用，当前未使用) ---
if [ -x "/data/adb/magisk/busybox" ]; then
  BUSYBOX="/data/adb/magisk/busybox"
elif [ -x "/data/adb/ksu/bin/busybox" ]; then
  BUSYBOX="/data/adb/ksu/bin/busybox"
elif [ -x "/data/adb/ap/bin/busybox" ]; then
  BUSYBOX="/data/adb/ap/bin/busybox"
fi

# --- 语言定义 ---
CURRENT_LOCALE=$(/system/bin/getprop persist.sys.locale)
if [ -z "$CURRENT_LOCALE" ]; then
    CURRENT_LOCALE=$(/system/bin/getprop ro.product.locale)
fi

LANG_CODE="en"
MSG_WELCOME="Welcome to Yumi Scheduler!"

if echo "$CURRENT_LOCALE" | $BUSYBOX grep -qi "zh"; then
  LANG_CODE="zh"
  MSG_WELCOME="欢迎使用 Yumi 调度！"
fi

# --- 仅输出欢迎信息 ---
ui_print " "
ui_print "$MSG_WELCOME"
ui_print " "

# --- 升级时保留用户的配置 ---
# 模块更新会整体替换模块目录。如果不主动保留，用户自定义的规则和模式设置
# 会被包内默认值覆盖。两个路径可通过环境变量覆盖，便于本地模拟测试。
MODULES_BASE="${YUMI_MODULES_BASE:-/data/adb/modules}"
MODULES_UPDATE_BASE="${YUMI_MODULES_UPDATE_BASE:-/data/adb/modules_update}"
MOD_ID=$(basename "$MODPATH")
OLD_MODULE=""
for BASE in "$MODULES_BASE" "$MODULES_UPDATE_BASE"; do
  CANDIDATE="$BASE/$MOD_ID"
  [ "$CANDIDATE" = "$MODPATH" ] && continue
  if [ -f "$CANDIDATE/module.prop" ]; then
    OLD_MODULE="$CANDIDATE"
    break
  fi
done

if [ -n "$OLD_MODULE" ]; then
  for REL in config/config.yaml rules.yaml; do
    if [ -f "$OLD_MODULE/$REL" ]; then
      mkdir -p "$MODPATH/$(dirname "$REL")"
      cp -f "$OLD_MODULE/$REL" "$MODPATH/$REL"
      ui_print "已保留旧配置: $REL"
    fi
  done
  ui_print "升级完成，原有配置已保留"
else
  ui_print "首次安装，使用默认配置"
fi

# --- 结束 ---