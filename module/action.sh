#!/system/bin/sh
MODDIR=${0%/*}
exec sh "$MODDIR/bin/qlctl.sh" "$MODDIR" open
