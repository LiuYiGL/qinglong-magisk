# 青龙 Qinglong · Android 离线 Magisk/KernelSU 模块

把 [青龙定时任务面板](https://github.com/whyour/qinglong) 完整搬进 Android。所有运行时随模块打包，**安装过程无需联网**；刷入后开机自启，浏览器访问 `http://127.0.0.1:5700` 即可使用。

> 当前版本：`2.24.0-android.5` · 仅支持 **arm64** 设备

## 特性

- **完整离线安装**：Node.js 24.22、Python 3.11、青龙 2.24.0、SQLite 原生模块与前端资源全部内置，安装时不下载任何依赖。
- **与官方镜像同源**：运行环境取自 `whyour/qinglong:2.24.0` arm64 Alpine 镜像，行为与容器版一致。
- **chroot 隔离运行**：数据独立持久化在 `/data/adb/qinglong/data`，升级模块不丢数据。
- **开机自启 + watchdog**：服务异常退出会自动拉起。
- **Magisk / KernelSU 通用**：标准模块脚本；KernelSU 下通过模块 WebUI 控制台进入青龙面板，Magisk 下保留操作按钮。
- **KernelSU WebUI**：在 KSU 模块页点击 WebUI 打开控制台，可查看状态、启动/停止/重启、查看日志；点击“进入面板”会在当前 WebUI 内直接显示青龙面板。KSU 安装时会自动移除 `action.sh`，避免重复入口。
- **命令行工具**：start / stop / restart / status / open / log / shell / ql。
- **已实测**：小米 8（arm64 / Android 15 / Magisk 30.2 / 内核 4.9）安装、重启自启、面板健康检查均通过。

## 安装

1. 从 [Releases](https://github.com/LiuYiGL/qinglong-magisk/releases) 下载 `qinglong-v2.24.0-android.5-magisk-arm64.zip`。
2. Magisk：模块 → 从本地安装 → 选择 zip；KernelSU：模块 → 安装 → 选择 zip。
3. 重启手机。
4. 浏览器打开 `http://127.0.0.1:5700`，按青龙首次使用流程初始化账号。
5. KernelSU 用户可在模块页点击 **WebUI** 打开控制台，再点击“进入面板”直接显示青龙面板（服务未启动时请先点“启动服务”）。

> 已安装旧版本时直接刷入即可：安装脚本会先停止正在运行的青龙、卸载旧 rootfs 的 bind mount，再替换运行时；`/data/adb/qinglong/data` 不受影响。

> 安装结束时会解析作者短链 `https://dwz.liuyi.publicvm.com/qinglong` 并打开最终目标页面；解析失败则直接打开短链本身。若被 Android 锁屏或后台限制拦截，不影响安装。

## 使用

- 面板：`http://127.0.0.1:5700`（局域网访问请使用手机 IP:5700）
- 数据：`/data/adb/qinglong/data`
- 日志：`/data/adb/qinglong/logs`
- 自定义 DNS：创建 `/data/adb/qinglong/resolv.conf`

命令行（需要 root）：

```bash
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh status'
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh stop'
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh start'
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh restart'
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh log -f'
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh open'
```

在 chroot 内执行 `ql` 命令：

```bash
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh ql --help'
```

电脑访问：

```bash
adb forward tcp:5700 tcp:5700
```

然后打开 `http://127.0.0.1:5700`。

## 备份与卸载

> **卸载模块会删除全部数据**。升级模块不会删除数据，但卸载不可恢复，请先备份。

卸载时会停止服务并删除 `/data/adb/qinglong` 下的任务、脚本、配置、数据库、日志与依赖缓存。

卸载前备份：

```bash
adb shell su -c 'tar -czf /data/local/tmp/qinglong-data.tar.gz -C /data/adb/qinglong data'
adb pull /data/local/tmp/qinglong-data.tar.gz
```

恢复时：重新安装模块并启动一次，停止服务后把备份解压回 `/data/adb/qinglong/data`，再启动。

## 实现说明

Android bionic 无法直接运行官方镜像里为 musl 编译的 Node、Python 与 SQLite 原生模块，因此模块采用：

1. 用 `crane` 将官方 `whyour/qinglong:2.24.0` arm64 镜像导出为扁平 rootfs，并随模块压缩包分发。
2. 安装时由仓库内的静态 Go 解包器 `tools/qlextract` 解压 rootfs。Android 自带的 toybox/busybox tar 会截断 PAX 长硬链接路径，而 pnpm 的 `node_modules` 依赖硬链接，因此不能直接用系统 tar。
3. 运行时通过 `chroot` 启动青龙，`/ql/data` 绑定到宿主 `/data/adb/qinglong/data`。
4. 容器模式所需的 `sudo` 由 rootfs 内的垫片提供；watchdog 独立进程运行，负责异常拉起。

## 仓库结构

```text
module/                  Magisk/KernelSU 模块脚本
  module.prop
  customize.sh           安装时离线解包与初始化
  service.sh             开机启动
  action.sh              模块操作按钮
  uninstall.sh           停止服务并删除全部数据
  bin/ql.sh              宿主机命令行工具
  bin/qlctl.sh           服务控制与 watchdog
webroot/                 KernelSU WebUI 控制台
  index.html
tools/qlextract/         离线解包器（Go）
RELEASE_NOTES.md         发布说明
LICENSE / NOTICE         许可与来源说明
```

rootfs 与成品 zip 体积较大，不进入 Git；成品通过 Releases 发布。

## 说明与限制

- 仅支持 arm64 设备。
- 青龙及其定时任务以 root 身份运行；面板默认监听 `0.0.0.0:5700`，请设置强密码并注意局域网暴露。
- 不建议在面板内升级青龙本体（会修改模块目录）；升级请安装新的模块 zip。
- KernelSU 使用标准模块脚本，格式兼容，但未在 KSU 真机实测。
- 安装完成后的作者页面跳转由模块安装脚本执行，部分系统可能拦截后台启动浏览器。

## 致谢

- [whyour/qinglong](https://github.com/whyour/qinglong)（Apache-2.0）
- Alpine Linux、Node.js、Python 及所有上游依赖

## 许可

本项目以 Apache License 2.0 发布，详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
