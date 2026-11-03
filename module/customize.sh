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

# 安装完成后打开作者页面（Android 可能因锁屏/后台限制拦截，失败不影响安装）
if [ -x /system/bin/am ]; then
  print_msg "- 正在打开作者页面..."
  /system/bin/am start --user 0 -a android.intent.action.VIEW \
    -d "https://dwz.liuyi.publicvm.com/qinglong" >/dev/null 2>&1 || true
fi
