#!/system/bin/sh
# 青龙模块命令行工具
# 用法: su -c 'sh /data/adb/modules/qinglong/bin/ql.sh <命令>'
set -u

SELF=$0
case "$SELF" in
  /*) ;;
  *) SELF=$PWD/$SELF ;;
esac

MODDIR=${SELF%/bin/ql.sh}
ROOTFS=$MODDIR/rootfs
STATE=/data/adb/qinglong
CTL=$MODDIR/bin/qlctl.sh
CHROOT_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/ql/data/dep_cache/node:/ql/data/dep_cache/python3/bin:/root/bin

CMD=${1:-help}

case "$CMD" in
  start|stop|restart|status|open|port)
    exec sh "$CTL" "$MODDIR" "$CMD"
    ;;
  log)
    if [ "${2:-}" = "-f" ]; then
      exec tail -f "$STATE/logs/qinglong.log"
    fi
    tail -n 200 "$STATE/logs/qinglong.log" 2>/dev/null || echo "暂无日志"
    ;;
  shell)
    sh "$CTL" "$MODDIR" up >/dev/null 2>&1
    exec chroot "$ROOTFS" /usr/bin/env -i \
      PATH="$CHROOT_PATH" HOME=/root LANG=C.UTF-8 TERM="${TERM:-xterm}" \
      QL_DIR=/ql QL_DATA_DIR=/ql/data QL_CONTAINER=true \
      /bin/bash -i
    ;;
  ql)
    shift
    sh "$CTL" "$MODDIR" up >/dev/null 2>&1
    exec chroot "$ROOTFS" /usr/bin/env -i \
      PATH="$CHROOT_PATH" HOME=/root LANG=C.UTF-8 \
      QL_DIR=/ql QL_DATA_DIR=/ql/data QL_CONTAINER=true \
      NODE_PATH=/usr/local/bin:/usr/local/lib/node_modules \
      /bin/bash -lc 'cd /ql && exec ql "$@"' -- "$@"
    ;;
  *)
    cat <<'EOF'
青龙 Magisk/KernelSU 模块

用法: su -c 'sh /data/adb/modules/qinglong/bin/ql.sh <命令>'

  start     启动青龙（并设为开机自启）
  stop      停止青龙
  restart   重启青龙
  status    查看运行状态
  port      查看面板端口
  open      启动并在手机上打开面板
  log [-f]  查看入口日志（-f 持续跟踪）
  shell     进入青龙的 chroot 环境
  ql ...    在 chroot 内执行 ql 命令，例如 ql --help

面板默认地址: http://127.0.0.1:5700
数据目录:     /data/adb/qinglong/data
EOF
    ;;
esac
