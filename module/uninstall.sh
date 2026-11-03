#!/system/bin/sh
MODDIR=${0%/*}
STATE=/data/adb/qinglong

# 停止 watchdog 与青龙进程
if [ -f "$MODDIR/bin/qlctl.sh" ]; then
  sh "$MODDIR/bin/qlctl.sh" "$MODDIR" stop >/dev/null 2>&1
fi

# 卸载 chroot 的 bind mount（若命名空间已随进程退出，失败可忽略）
for M in ql/data dev/pts dev sys proc; do
  umount "$MODDIR/rootfs/$M" 2>/dev/null || umount -l "$MODDIR/rootfs/$M" 2>/dev/null
done

sleep 1

# 卸载模块即删除全部数据：任务、脚本、配置、数据库、日志、依赖缓存
rm -rf "$STATE"

echo "青龙模块已卸载，所有数据已删除（$STATE）。"
