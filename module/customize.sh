#!/system/bin/sh
# qinglong Magisk/KernelSU 模块安装脚本
# 全程离线：所有运行环境都随模块压缩包提供，安装时不访问网络。

print_msg() {
  if type ui_print >/dev/null 2>&1; then
    ui_print "$1"
  else
    echo "$1"
  fi
}

abort_install() {
  print_msg "! $1"
  exit 1
}

[ -n "${MODPATH:-}" ] || MODPATH=$(cd "${0%/*}" 2>/dev/null && pwd)

ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
case "$ABI" in
  arm64*) ;;
  *) abort_install "仅支持 arm64 设备（当前 ABI: ${ABI:-unknown}）" ;;
esac

[ -f "$MODPATH/rootfs.tar.gz" ] || abort_install "缺少 rootfs.tar.gz，模块包不完整"
[ -f "$MODPATH/bin/qlextract" ] || abort_install "缺少解包器，模块包不完整"

# 升级时旧模块可能仍在运行。旧 rootfs 与新 rootfs 是同一路径，必须先停止
# 进程并卸载其中的 bind mount，否则 rm -rf 会被挂载点挡住，旧进程也会继续
# 跑着已被替换的文件。
stop_old_instance() {
  OLD_MODDIR=/data/adb/modules/qinglong
  OLD_ROOTFS=$OLD_MODDIR/rootfs
  [ -d "$OLD_ROOTFS" ] || return 0

  print_msg "- 停止正在运行的青龙服务..."
  if [ -f "$OLD_MODDIR/bin/qlctl.sh" ]; then
    sh "$OLD_MODDIR/bin/qlctl.sh" "$OLD_MODDIR" stop >/dev/null 2>&1 || true
  fi

  # 兜底：qlctl 缺失或未能结束时，按 PID 文件和 chroot 根目录清理残留进程
  W=$(cat /data/adb/qinglong/watchdog.pid 2>/dev/null || true)
  case "$W" in
    ''|*[!0-9]*) ;;
    *) kill -9 "$W" 2>/dev/null || true ;;
  esac
  for p in /proc/[0-9]*; do
    [ "$(readlink "$p/root" 2>/dev/null)" = "$OLD_ROOTFS" ] || continue
    kill -9 "${p#/proc/}" 2>/dev/null || true
  done

  for m in ql/data dev/pts dev sys proc; do
    umount "$OLD_ROOTFS/$m" 2>/dev/null || umount -l "$OLD_ROOTFS/$m" 2>/dev/null || true
  done
}
stop_old_instance

print_msg "- 解包青龙运行环境（约 430MB），请耐心等待 1-3 分钟..."
chmod 755 "$MODPATH/bin/qlextract" 2>/dev/null
rm -rf "$MODPATH/rootfs"
"$MODPATH/bin/qlextract" "$MODPATH/rootfs.tar.gz" "$MODPATH/rootfs" || abort_install "运行环境解包失败"
rm -f "$MODPATH/rootfs.tar.gz"

[ -x "$MODPATH/rootfs/usr/bin/node" ] || abort_install "运行环境不完整（缺少 node）"
[ -f "$MODPATH/rootfs/ql/static/build/app.js" ] || abort_install "青龙程序文件缺失"

# qinglong 以 QL_CONTAINER=true 运行，会调用 sudo；chroot 内本来就是 root，放一个垫片
printf '#!/bin/sh\nexec "$@"\n' > "$MODPATH/rootfs/usr/bin/sudo"
chmod 755 "$MODPATH/rootfs/usr/bin/sudo"

# 删除运行时用不到的内容，节省空间
rm -rf "$MODPATH/rootfs/ql/.git" \
       "$MODPATH/rootfs/ql/test" \
       "$MODPATH/rootfs/var/cache/apk" \
       "$MODPATH/rootfs/tmp/dependency-lock.yaml"

chmod 755 "$MODPATH/bin/qlctl.sh" "$MODPATH/bin/ql.sh" \
          "$MODPATH/service.sh" "$MODPATH/action.sh" "$MODPATH/uninstall.sh"
chmod 755 "$MODPATH/rootfs/ql/shell/"*.sh 2>/dev/null

# KernelSU 支持模块 WebUI 时，移除旧的操作按钮，避免两个入口重复
if [ -d /data/adb/ksu ] && [ -f "$MODPATH/webroot/index.html" ] && [ -x /data/adb/ksu/bin/ksud ]; then
  KVER=$(/data/adb/ksu/bin/ksud -V 2>/dev/null | head -n 1)
  KVER=${KVER#ksud }
  KVER=${KVER%% *}
  KMAJ=${KVER%%.*}
  KREST=${KVER#*.}
  KMIN=${KREST%%.*}
  case "$KMAJ" in ''|*[!0-9]*) KMAJ=0 ;; esac
  case "$KMIN" in ''|*[!0-9]*) KMIN=0 ;; esac
  if [ "$KMAJ" -gt 0 ] || [ "$KMIN" -ge 6 ]; then
    rm -f "$MODPATH/action.sh"
    print_msg "- KernelSU WebUI 已启用，已移除操作按钮"
  fi
fi

STATE=/data/adb/qinglong
mkdir -p "$STATE/data" "$STATE/logs"
if [ ! -d "$STATE/data/dep_cache" ] && [ -d "$MODPATH/rootfs/ql/data/dep_cache" ]; then
  cp -a "$MODPATH/rootfs/ql/data/dep_cache" "$STATE/data/" 2>/dev/null
fi
# 保留依赖缓存模板，数据目录被清空后可自动恢复
if [ -d "$MODPATH/rootfs/ql/data/dep_cache" ]; then
  rm -rf "$MODPATH/dep_cache.seed"
  cp -a "$MODPATH/rootfs/ql/data/dep_cache" "$MODPATH/dep_cache.seed" 2>/dev/null
fi
touch "$STATE/enabled"

print_msg "- 安装完成，数据目录: /data/adb/qinglong/data"
print_msg "- 重启手机后自动启动，浏览器访问 http://127.0.0.1:5700"
print_msg "- 可在 Magisk/KernelSU 模块页点击操作按钮直接打开面板"

# 安装完成后解析短链，并打开最终目标页面（解析失败则打开短链本身）
AUTHOR_URL="https://dwz.liuyi.publicvm.com/qinglong"
OPEN_URL="$AUTHOR_URL"
if [ -x "$MODPATH/rootfs/usr/bin/curl" ]; then
  printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 8.8.8.8\n' > "$MODPATH/rootfs/etc/resolv.conf"
  CHROOT_BIN=/system/bin/chroot
  [ -x "$CHROOT_BIN" ] || CHROOT_BIN=chroot
  TARGET=$("$CHROOT_BIN" "$MODPATH/rootfs" /usr/bin/env -i PATH=/usr/local/bin:/usr/bin:/bin \
    /usr/bin/curl -sL -m 15 -o /tmp/.author_url -w '%{url_effective}' "$AUTHOR_URL" 2>/dev/null)
  if printf '%s' "$TARGET" | grep -qE '^https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$'; then
    OPEN_URL="$TARGET"
  fi
fi
if [ -x /system/bin/am ]; then
  print_msg "- 正在打开作者页面..."
  /system/bin/am start --user 0 -a android.intent.action.VIEW \
    -d "$OPEN_URL" >/dev/null 2>&1 || true
fi
