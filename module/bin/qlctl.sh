#!/system/bin/sh
# 青龙服务控制：qlctl.sh <模块目录> <up|start|stop|restart|status|open>
set -u

MODDIR=${1:-}
CMD=${2:-status}
if [ -z "$MODDIR" ]; then
  echo "usage: qlctl.sh <module_dir> <up|start|stop|restart|status|open>" >&2
  exit 2
fi

ROOTFS=$MODDIR/rootfs
STATE=/data/adb/qinglong
DATA=$STATE/data
LOGDIR=$STATE/logs
LOG=$LOGDIR/qinglong.log
CTL_LOG=$LOGDIR/control.log
PIDFILE=$STATE/watchdog.pid
ENABLED=$STATE/enabled

CHROOT_PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/ql/data/dep_cache/node:/ql/data/dep_cache/python3/bin:/root/bin

mkdir -p "$STATE" "$DATA" "$LOGDIR" 2>/dev/null

log_ctl() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$CTL_LOG" 2>/dev/null
}

say() {
  echo "$*"
  log_ctl "$*"
}

panel_port() {
  PORT=5700
  CFG=$DATA/config/config.sh
  if [ -f "$CFG" ]; then
    V=$(grep -E '^[[:space:]]*(export[[:space:]]+)?QlPort=' "$CFG" 2>/dev/null | tail -n 1 | sed -E 's/.*QlPort=["'\'']?([0-9]+).*/\1/')
    case "$V" in
      ''|*[!0-9]*) ;;
      *) PORT=$V ;;
    esac
  fi
  printf '%s' "$PORT"
}

listeners() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null
  fi
}

is_running() {
  PORT=$(panel_port)
  listeners | grep -qE "[:.]${PORT}[[:space:]]"
}

is_mounted() {
  grep -q " $1 " /proc/mounts 2>/dev/null
}

bind_mount() {
  SRC=$1
  DST=$2
  MOUNTPOINT_ONLY=$3

  if [ "$MOUNTPOINT_ONLY" = "1" ]; then
    is_mounted "$DST" && return 0
  fi
  mount --bind "$SRC" "$DST" 2>/dev/null && return 0
  mount "$SRC" "$DST" 2>/dev/null && return 0
  log_ctl "mount $SRC -> $DST failed"
  return 1
}

prepare() {
  if [ ! -x "$ROOTFS/usr/bin/node" ]; then
    say "运行环境缺失: $ROOTFS"
    return 1
  fi

  mkdir -p "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev/pts" "$ROOTFS/ql/data" "$DATA"
  bind_mount /proc "$ROOTFS/proc" 1
  bind_mount /sys "$ROOTFS/sys" 1
  bind_mount /dev "$ROOTFS/dev" 1
  bind_mount /dev/pts "$ROOTFS/dev/pts" 1
  bind_mount "$DATA" "$ROOTFS/ql/data" 1

  if [ ! -d "$DATA/dep_cache" ] && [ -d "$ROOTFS/ql/data/dep_cache" ]; then
    cp -a "$ROOTFS/ql/data/dep_cache" "$DATA/" 2>/dev/null || \
      cp -R "$ROOTFS/ql/data/dep_cache" "$DATA/" 2>/dev/null
  fi

  if [ -f "$STATE/resolv.conf" ]; then
    cp -f "$STATE/resolv.conf" "$ROOTFS/etc/resolv.conf"
  else
    printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 8.8.8.8\noptions ndots:0\n' >"$ROOTFS/etc/resolv.conf"
  fi
  grep -q '^127\.0\.0\.1' "$ROOTFS/etc/hosts" 2>/dev/null || echo '127.0.0.1 localhost' >>"$ROOTFS/etc/hosts"

  # 容器模式会调用 sudo，镜像内没有该命令；chroot 内本来就是 root
  if [ ! -x "$ROOTFS/usr/bin/sudo" ]; then
    printf '#!/bin/sh\nexec "$@"\n' >"$ROOTFS/usr/bin/sudo"
    chmod 755 "$ROOTFS/usr/bin/sudo"
  fi
}

start_ql() {
  if is_running; then
    log_ctl "already running on port $(panel_port)"
    return 0
  fi

  if [ -f "$LOG" ] && [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
    mv -f "$LOG" "$LOG.1" 2>/dev/null
  fi

  say "启动青龙 (端口 $(panel_port))..."
  (
    cd "$ROOTFS" || exit 1
    exec chroot "$ROOTFS" /usr/bin/env -i \
      PATH="$CHROOT_PATH" \
      HOME=/root LANG=C.UTF-8 SHELL=/bin/bash \
      QL_DIR=/ql QL_DATA_DIR=/ql/data QL_CONTAINER=true QL_BRANCH=master \
      NODE_PATH=/usr/local/bin:/usr/local/lib/node_modules \
      PNPM_HOME=/ql/data/dep_cache/node \
      PYTHON_HOME=/ql/data/dep_cache/python3 \
      PYTHONUSERBASE=/ql/data/dep_cache/python3 \
      PYTHONPATH=/ql/data/dep_cache/python3:/ql/data/dep_cache/python3/lib/python3.11:/ql/data/dep_cache/python3/lib/python3.11/site-packages \
      PIP_CACHE_DIR=/ql/data/dep_cache/python3/pip \
      /bin/bash -c 'cd /ql && exec ./docker/docker-entrypoint.sh'
  ) >>"$LOG" 2>&1 </dev/null &
  echo $! >"$STATE/entry.pid"
}

kill_watchdog() {
  if [ -f "$PIDFILE" ]; then
    W=$(cat "$PIDFILE" 2>/dev/null)
    case "$W" in
      ''|*[!0-9]*) ;;
      *) kill -9 "$W" 2>/dev/null ;;
    esac
    rm -f "$PIDFILE"
  fi
}

kill_ql() {
  N=0

  # pm2 守护进程（父子进程可能已 disown，优先按 pid 文件处理）
  P=$(cat "$ROOTFS/root/.pm2/pm2.pid" 2>/dev/null || true)
  case "$P" in
    ''|*[!0-9]*) ;;
    *)
      R=$(readlink "/proc/$P/root" 2>/dev/null || true)
      if [ "$R" = "$ROOTFS" ]; then
        kill -9 "$P" 2>/dev/null
        N=$((N + 1))
      fi
      ;;
  esac

  # 先按特征命令行筛出候选进程，再校验 chroot 根目录，避免逐个 readlink 全部 /proc
  PASS=0
  while [ "$PASS" -lt 3 ]; do
    ps -A -w -o PID,ARGS 2>/dev/null >"$STATE/.ps" || break
    while read -r PID ARGS; do
      case "$ARGS" in
        *app.js*|*"/ql/"*|*task.sh*|*".pm2)"*|"crond -f"*|*" crond -f"*) ;;
        *) continue ;;
      esac
      R=$(readlink "/proc/$PID/root" 2>/dev/null || true)
      [ "$R" = "$ROOTFS" ] || continue
      kill -9 "$PID" 2>/dev/null
      N=$((N + 1))
    done <"$STATE/.ps"
    rm -f "$STATE/.ps"

    PASS=$((PASS + 1))
    is_running || break
    sleep 1
  done

  rm -f "$STATE/entry.pid"
  say "已停止 $N 个青龙进程"
}

stop_all() {
  kill_watchdog
  kill_ql
}

watchdog_main() {
  echo $$ >"$PIDFILE"
  log_ctl "watchdog started (pid $$)"
  FAILS=0
  while [ -f "$ENABLED" ]; do
    sleep 60
    [ -f "$ENABLED" ] || break
    if is_running; then
      FAILS=0
      continue
    fi
    FAILS=$((FAILS + 1))
    log_ctl "watchdog: panel not listening ($FAILS/3)"
    if [ "$FAILS" -ge 3 ]; then
      log_ctl "watchdog: restarting qinglong"
      kill_ql
      start_ql
      FAILS=0
    fi
  done
  rm -f "$PIDFILE"
  log_ctl "watchdog: exit"
}

ensure_watchdog() {
  W=$(cat "$PIDFILE" 2>/dev/null || true)
  case "$W" in
    ''|*[!0-9]*) ;;
    *)
      if kill -0 "$W" 2>/dev/null; then
        return 0
      fi
      ;;
  esac

  # 用独立进程启动，避免 fork 出来的子 shell 继承调用方的 socket
  if command -v setsid >/dev/null 2>&1; then
    setsid sh "$MODDIR/bin/qlctl.sh" "$MODDIR" watchdog >/dev/null 2>&1 </dev/null &
  else
    sh "$MODDIR/bin/qlctl.sh" "$MODDIR" watchdog >/dev/null 2>&1 </dev/null &
  fi
  log_ctl "watchdog launch requested"
}

up() {
  prepare || return 1
  start_ql
  ensure_watchdog
}

open_panel() {
  up
  I=0
  while [ "$I" -lt 30 ]; do
    is_running && break
    sleep 1
    I=$((I + 1))
  done

  URL="http://127.0.0.1:$(panel_port)/"
  if is_running; then
    say "青龙面板: $URL"
  else
    say "青龙正在启动，请稍后访问 $URL"
  fi
  am start --user 0 -a android.intent.action.VIEW -d "$URL" >/dev/null 2>&1 || true
}

status_cmd() {
  if is_running; then
    echo "青龙面板运行中: http://127.0.0.1:$(panel_port)/"
    return 0
  fi
  echo "青龙面板未运行"
  return 1
}

case "$CMD" in
  up)
    up
    ;;
  start)
    touch "$ENABLED"
    up
    ;;
  stop)
    stop_all
    ;;
  restart)
    touch "$ENABLED"
    stop_all
    sleep 1
    up
    ;;
  watchdog)
    watchdog_main
    ;;
  status)
    status_cmd
    ;;
  open)
    touch "$ENABLED"
    open_panel
    ;;
  *)
    echo "usage: qlctl.sh <module_dir> <up|start|stop|restart|status|open>" >&2
    exit 2
    ;;
esac
