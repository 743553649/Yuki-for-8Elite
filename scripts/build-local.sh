#!/usr/bin/env bash
#
# 本机构建脚本：编译 WebUI、Rust 守护进程与 eBPF 探针，打包模块 zip。
#
# 与 CI 的区别：CI 用 Rust nightly + NDK 交叉编译；本脚本面向"在 Android 设备上
# 原生编译"（也可在 Linux x86_64 上直接跑）。稳定版 Rust 通过 RUSTC_BOOTSTRAP
# 解锁 build-std，实测可用于本项目。
#
# 依赖（Android 上）：
#   1. cccodroid → 扩展 → 工具包模块：安装「Rust 语言」（含 rust / rust-src）
#      注意：应用工具包升级后，这个模块可能需要重新安装
#   2. 预编译 bpf-linker 0.11.1（aya-rs 官方 ARM64 静态包）加入 PATH：
#      https://github.com/aya-rs/bpf-linker/releases
#   3. node / npm / zip / sha256sum（工具包一般自带）
#
# 可选环境变量：
#   SKIP_WEBUI=1    跳过 WebUI 构建与类型检查
#   SKIP_TESTS=1    跳过单元测试
#   CARGO_TARGET_DIR 自定义编译目录（默认 target/）
#
# 用法：./scripts/build-local.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "缺少 $1：$2" >&2
    exit 1
  fi
}

need cargo "在 cccodroid「扩展 → 工具包模块」安装「Rust 语言」，或 pkg install rust rust-src"
need rustc "在 cccodroid「扩展 → 工具包模块」安装「Rust 语言」，或 pkg install rust rust-src"
need node "安装 Node.js：pkg install nodejs"
need npm "安装 Node.js：pkg install nodejs"
need zip "安装 zip：pkg install zip"
need sha256sum "安装 coreutils：pkg install coreutils"

if ! command -v bpf-linker >/dev/null 2>&1; then
  echo "缺少 bpf-linker：下载 aya-rs 官方预编译包并加入 PATH（版本需与 CI 一致：0.11.1）" >&2
  exit 1
fi

# 稳定版需要解锁 -Z build-std；nightly 则不需要
if rustc --version | grep -q nightly; then
  CARGO=(cargo)
else
  echo "检测到稳定版 Rust，使用 RUSTC_BOOTSTRAP 解锁 build-std"
  CARGO=(env RUSTC_BOOTSTRAP=1 __CARGO_TEST_CHANNEL_OVERRIDE_DO_NOT_USE_THIS=nightly cargo)
fi

TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"

if [ "${SKIP_WEBUI:-0}" != "1" ]; then
  echo "== 构建 WebUI =="
  (
    cd webui
    if [ ! -d node_modules ]; then
      npm ci
    fi
    npm run type-check
    npm run build
  )
fi

echo "== 编译守护进程与 eBPF 探针 =="
"${CARGO[@]}" build --release --locked --target-dir "$TARGET_DIR"

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "== 单元测试 =="
  "${CARGO[@]}" test -p yumi --bin yumi --locked --release --target-dir "$TARGET_DIR"
fi

echo "== 打包模块 =="
VERSION=$(grep -m1 '^version' Cargo.toml | sed -E 's/.*"([^"]+)".*/\1/')
COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
STAMP=$(date +%Y%m%d-%H%M)
NAME="yumi-${VERSION}-${COUNT}-${STAMP}.zip"
TMP="output/.temp"

rm -rf "$TMP"
mkdir -p "$TMP/core/bin" "$TMP/webroot"
cp -a module/. "$TMP/"
rm -f "$TMP/.gitignore"
if [ "${SKIP_WEBUI:-0}" != "1" ]; then
  cp -a webui/dist/. "$TMP/webroot/"
else
  echo "跳过 WebUI：包内 webroot 将为空，仅用于验证 Rust 产物" >&2
fi
cp "$TARGET_DIR/release/yumi" "$TMP/core/bin/yumi"
chmod 755 "$TMP/core/bin/yumi" "$TMP/service.sh" "$TMP/uninstall.sh"
chmod 755 "$TMP"/scripts/*.sh 2>/dev/null || true

(cd "$TMP" && zip -r -X "../$NAME" . > /dev/null)
unzip -t "output/$NAME" > /dev/null

echo
echo "产物: output/$NAME"
echo "大小: $(wc -c < "output/$NAME") 字节"
echo "SHA256: $(sha256sum "output/$NAME" | awk '{print $1}')"
echo "提示: 复制到共享目录后即可用 KernelSU / Magisk 刷入"
