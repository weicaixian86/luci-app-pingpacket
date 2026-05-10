# luci-app-pingpacket

`luci-app-pingpacket` 是一个用于 OpenWrt 的 LuCI 监控插件，用来持续检测目标地址的 Ping 延迟和丢包情况，方便快速判断当前网络质量。

## 适用平台

- OpenWrt 24.10.x
- LuCI Web 管理界面
- 当前仓库默认适配 `x86_64`
- 依赖 `luci-base` 以及系统自带 `ping`、`awk`、`sed` 等基础工具

## 具体功能

- 支持分别配置国内和国外两个 Ping 目标
- 支持目标填写 IP 地址或域名
- 实时显示平均延迟、最低延迟、最高延迟、丢包率
- 页面自动刷新，便于持续观察网络状态
- 显示监控开始时间和已运行时长
- 支持在页面内直接启用或关闭监控服务
- 配置保存后自动应用，并重启监控服务
- 通过 LuCI 页面集中管理，无需手动执行监控脚本

## 页面位置

LuCI 后台路径：

`Status -> Ping Packet Loss`

## 安装说明

将编译生成的 IPK 包上传到 OpenWrt 设备后执行：

```sh
opkg install luci-app-pingpacket_*.ipk
```
