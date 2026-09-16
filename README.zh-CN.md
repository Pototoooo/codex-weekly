# Codex Weekly

<p align="center">
  <a href="README.md">English</a> | <strong>简体中文</strong>
</p>

<p align="center">
  <img src="Assets/AppIcon-1024-v2.png" width="160" alt="Codex Weekly 图标">
</p>

<p align="center">
  <a href="https://github.com/Pototoooo/codex-weekly/actions/workflows/ci.yml"><img src="https://github.com/Pototoooo/codex-weekly/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/Pototoooo/codex-weekly/releases/latest"><img src="https://img.shields.io/github/v/release/Pototoooo/codex-weekly" alt="GitHub release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Pototoooo/codex-weekly" alt="MIT License"></a>
</p>

一个轻量的原生 macOS 菜单栏工具，同时显示当前 Codex 账号的**滚动 5 小时额度**、**一周额度**和各自的重置时间。

> 这是独立的社区项目，与 OpenAI 无隶属、背书或赞助关系。

## 特点

- 菜单栏优先显示滚动 5 小时窗口的剩余百分比
- 下拉菜单同时显示 5 小时与一周窗口的使用量和重置时间
- 每 60 秒自动刷新，也可手动刷新
- 自动适配浅色、深色及全屏菜单栏背景
- 低额度时切换为警告图标，不依赖固定颜色
- 显示已使用比例及下一次重置时间
- 可选“登录时启动”
- 原生多分辨率 macOS 应用图标
- 不读取、复制或上传 `~/.codex/auth.json`；额度通过本机 Codex CLI 的 `app-server` 接口读取

## 安装

1. 从[最新版本](https://github.com/Pototoooo/codex-weekly/releases/latest)下载 `Codex-Weekly-macOS.zip`。
2. 解压安装包。
3. 将 `Codex Weekly.app` 拖入 `/Applications`。
4. 双击运行。它是菜单栏软件，不会出现在程序坞中。
5. 如果 macOS 阻止未经公证的社区构建，请在 Finder 中右键应用并选择“打开”。

需要本机已安装并登录 Codex 桌面版或 Codex CLI。

## 构建与验证

```bash
./build-app.sh
.build/release/CodexWeekly --probe
```

构建结果位于 `dist/`。要求 macOS 13+ 与 Xcode/Swift 6。

## 工作原理

应用启动本机 Codex CLI 的 `app-server --stdio`，调用
`account/rateLimits/read` 获取额度窗口，同时解析时长为 300 分钟的滚动
5 小时窗口，以及时长为 10,080 分钟的一周窗口。

- 不直接读取 `~/.codex/auth.json`
- 不复制或上传 Codex Token
- 不包含统计、遥测或第三方网络请求
- 所有额度读取均由本机 Codex CLI 完成

Codex CLI app-server 属于实验性接口，未来协议变化可能需要同步适配。

## 开发

```bash
swift test
swift run CodexWeekly --probe
```

主要结构：

- `CodexQuotaClient.swift`：Codex app-server 通信
- `QuotaSnapshot.swift`：5 小时与周额度解析和窗口选择
- `AppDelegate.swift`：菜单栏 UI、刷新及开机启动
- `QuotaParserTests.swift`：协议响应解析测试

## License

[MIT](LICENSE)

## Sub2API 分配额度（可选）

菜单选择「配置 Sub2API…」，输入 HTTPS Base URL 和 Key，再点「保存并查询」。
Key 存入系统钥匙串，只发送给配置地址的 `/v1/usage`，不读取浏览器 Cookie、不记录 Key。
此模式会向配置的第三方平台发起请求，与原有本地 Codex 模式不同。

显示日/周已用、上限、剩余 USD 和更新时间，菜单栏固定显示日剩余百分比（日额度未返回时显示未知）；
每五分钟刷新，也可立即刷新。订阅额度可能由同订阅的多个 Key 共用，不代表上游 20x 总额度。
接口未提供的周期标记为未知/未返回，不冒充零；综合余额不冒充周额度。
只有接口明确提供重置时间时才显示，不按本地日期或订阅到期时间推算。
查询失败时清空当前值并标记上次成功时间。可随时「切换到 Codex 本地额度」。

Key 留空时复用同一接口地址已保存的 Key；更换地址不会沿用旧地址的 Key。
真实额度需使用自己的 Key 与平台页面对照验证，切勿把 Key 发到聊天或提交到仓库。

菜单的切换入口随当前数据源变化：本地模式可一键「切换到 Sub2 额度」，复用钥匙串中已保存的 Key，无需重新配置；Sub2 模式可一键返回本地。查询失败也不影响切换。
