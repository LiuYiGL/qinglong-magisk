#!/system/bin/sh
MODDIR=${0%/*}

sh "$MODDIR/bin/qlctl.sh" "$MODDIR" stop 2>/dev/null

for M in ql/data dev/pts dev sys proc; do
  umount "$MODDIR/rootfs/$M" 2>/dev/null
done

echo "青龙已停止。数据保留在 /data/adb/qinglong/data，重新安装模块后可直接恢复。"
