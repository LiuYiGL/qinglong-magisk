#!/system/bin/sh
MODDIR=${0%/*}
ROOTFS=$MODDIR/rootfs

# 模块被停用或环境不完整时不启动
[ -f /data/adb/qinglong/enabled ] || exit 0
[ -x "$ROOTFS/usr/bin/node" ] || exit 0

exec sh "$MODDIR/bin/qlctl.sh" "$MODDIR" up
