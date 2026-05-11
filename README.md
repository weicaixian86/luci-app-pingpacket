# luci-app-pingpacket

`luci-app-pingpacket` 是一个面向 OpenWrt 的 LuCI 网络监控插件，用于持续探测国内和国外目标的连通性、延迟和丢包情况，并提供运行日志、服务控制与简单故障排查能力。

## 适用环境

- OpenWrt 24.10.x
- 已安装 LuCI Web 管理界面
- 依赖系统常见基础工具：`ping`、`awk`、`sed`、`grep`、`tail`
- 当前仓库的构建示例主要面向 `x86/64` SDK，但插件本身为脚本和 LuCI 页面，原则上可用于支持 LuCI 的 OpenWrt 设备

## LuCI 页面位置

后台菜单路径：

`状态 -> Ping丢包监控`

该菜单下包含两个子页面：

- `监控`
- `日志`

## 当前功能

### 监控页

- 支持分别配置国内和国外两个 Ping 目标
- 目标支持输入 IP 地址或域名
- 支持页面内直接启用、关闭监控服务
- 支持“保存并应用”后自动写入配置
- 当服务已启用时，保存配置会自动重启服务，使新配置立即生效
- 当服务数据长时间未更新时，页面会提示“数据停滞”，并提供“重新启动服务”按钮
- 实时显示以下运行信息：
  - 开始时间
  - 运行时长
  - 最近更新时间
  - CPU 占用
  - 内存占用
- 分别显示国内和国外目标的累计统计值：
  - 平均延迟
  - 最低延迟
  - 最高延迟
  - 丢包率
  - 样本数

说明：

- 以上统计均为“本次服务启用后的累计统计值”
- 停止服务或重启服务后，统计会重新开始
- 国内和国外的样本数分别独立累计，不是两者总和

### 日志页

- 显示插件运行日志
- 默认开启自动刷新
- 可取消勾选自动刷新，暂停日志轮询
- 提供“清除日志”按钮
- 显示日志最后更新时间、日志行数、日志大小
- 日志内容默认保留最近 500 行

### 运行日志内容

日志页当前会记录以下事件：

- 服务启动时间与目标信息
- 服务停止时间
- 目标单次丢包事件
- 目标恢复事件

当前日志规则：

- 某目标只要单次 Ping 失败，就立即记录一条丢包日志
- 连续失败时，每次失败都会单独记录
- 失败后的首次成功响应会记录一条恢复日志

## 配置与校验规则

- 国内、国外两个目标都为空时：
  - 点击“保存并应用”会提示必须至少填写一个目标
  - 在启用开关打开时也会提示必须至少填写一个目标
- 监控关闭时可以保留配置，不会自动清空输入内容
- 页面轮询刷新时，不会覆盖用户正在编辑但尚未保存的输入内容

## 安装说明

将编译好的 IPK 上传到 OpenWrt 设备后执行：

```sh
opkg install luci-app-pingpacket_*.ipk
```

如果是升级安装：

- 现有 `/etc/config/pingpacket` 会被保留
- 包安装时仅在配置文件不存在时自动创建默认配置
- 安装脚本会尽量清理历史升级过程中可能残留的 `/etc/config/pingpacket-opkg`

## 默认配置行为

如果系统中不存在对应配置项，安装脚本会按需补入默认目标：

- 国内：`www.baidu.com`
- 国外：`www.google.com`

`/etc/config/pingpacket` 默认结构如下：

```uci
config pingpacket 'config'
	option enabled '0'
	option domestic_target ''
	option foreign_target ''
```

## 主要运行文件

- LuCI 控制器：`luci-app-pingpacket/luasrc/controller/pingpacket.lua`
- 监控页模板：`luci-app-pingpacket/luasrc/view/pingpacket/status.htm`
- 日志页模板：`luci-app-pingpacket/luasrc/view/pingpacket/logs.htm`
- 服务脚本：`luci-app-pingpacket/root/etc/init.d/pingpacket`
- 采集脚本：`luci-app-pingpacket/root/usr/bin/pingpacket.sh`

## 当前实现要点

- 监控数据写入 `/tmp/pingpacket_status.json`
- 运行日志写入 `/tmp/pingpacket.log`
- 服务运行目录使用 `/var/run/pingpacket`
- CPU 占用通过 `/proc/stat` 两次采样差值计算
- 内存占用通过 `/proc/meminfo` 计算

## 构建说明

本仓库适合配合 OpenWrt SDK 编译使用。插件包目录为：

`luci-app-pingpacket/`

编译时需确保目标 SDK 已包含 LuCI 相关依赖。
