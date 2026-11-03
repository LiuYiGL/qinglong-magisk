# 青龙 Qinglong v2.24.0 · Android 离线 Magisk/KernelSU 模块

把青龙定时任务面板完整搬进 Android。所有运行时随模块打包，**安装过程无需联网**；刷入后开机自启，浏览器访问 `http://127.0.0.1:5700` 即可使用。

## 特性

- **完整离线安装**：Node.js 24.22、Python 3.11、青龙 2.24.0、SQLite 原生模块与前端资源全部内置，安装时不下载任何依赖。
- **与官方镜像同源**：运行环境取自 `whyour/qinglong:2.24.0` arm64 Alpine 镜像，行为与容器版一致。
- **chroot 隔离运行**：数据独立持久化在 `/data/adb/qinglong/data`，升级或卸载模块不会丢数据。
- **开机自启 + watchdog**：服务异常退出会自动拉起。
- **Magisk / KernelSU 通用**：标准模块脚本；模块操作按钮可启动服务并打开面板。
- **已实测**：小米 8（arm64 / Android 15 / Magisk 30.2 / 内核 4.9）安装、重启自启、面板健康检查均通过。
- **命令行工具**：start / stop / restart / status / open / log / shell / ql。

## 安装

1. 下载本页附件 `qinglong-v2.24.0-arm64.zip`。
2. Magisk：模块 → 从本地安装 → 选择 zip；KernelSU：模块 → 安装 → 选择 zip。
3. 重启手机。
4. 浏览器打开 `http://127.0.0.1:5700`，按青龙首次使用流程初始化账号。

> 仅支持 arm64 设备。安装结束时会尝试打开作者页面 `https://dwz.liuyi.publicvm.com/qinglong`；若被 Android 拦截，不影响安装。

## 使用

- 面板：`http://127.0.0.1:5700`（局域网用手机 IP:5700）
- 数据：`/data/adb/qinglong/data`
- 自定义 DNS：`/data/adb/qinglong/resolv.conf`
- 命令行：

```bash
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh status'
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh stop'
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh start'
su -c 'sh /data/adb/modules/qinglong/bin/ql.sh log -f'
```

- 电脑访问：

```bash
adb forward tcp:5700 tcp:5700
```

然后打开 `http://127.0.0.1:5700`。

## 说明

- 青龙及其定时任务以 root 身份运行；面板默认监听 `0.0.0.0:5700`，请设置强密码并注意局域网暴露。
- 不建议在面板内升级青龙本体（会修改模块目录）；升级请安装新的模块 zip。
- KernelSU 使用标准模块脚本，格式兼容，但未在 KSU 真机实测。
- 源码与安装脚本：https://github.com/LiuYiGL/qinglong-magisk

## 校验

```text
SHA256  c3f92f48ac5ce764f05004e2999d8020c4d43bc803c795fabcc9cbd77b245d92
```

## 致谢

- [whyour/qinglong](https://github.com/whyour/qinglong)（Apache-2.0）
- Alpine Linux、Node.js、Python 及所有上游依赖
