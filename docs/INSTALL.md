# 安装到自己的 iPhone

## 开始之前

- 一台能运行完整 Xcode 的 Mac；只有命令行开发工具不够编译 iPhone App。
- iOS 17 或更高版本的 iPhone。使用支持你当前 iPhone 系统版本的 Xcode；实际验证环境见 [测试记录](TEST_PLAN.md)，并非所有系统组合都已测试。
- 自己的 Apple 账户；免费账户可以开始测试，不要求购买会员。
- 首次安装建议使用数据线连接，并解锁 iPhone。
- API 凭证不是安装前提。录音、回听、导出不调用 AI；联网分析需要使用者自己的兼容 API 和额度。

## 下载源码

在 [仓库首页](https://github.com/calebx10/work-memory-ios) 点 Code → Download ZIP 并解压，或运行：

```sh
git clone https://github.com/calebx10/work-memory-ios.git
cd work-memory-ios
```

不熟悉技术可以先用 [Codex 安装指令](CODEX_QUICKSTART.md)。

## 用 Xcode 安装

1. 从 Mac App Store 安装 Xcode，首次打开后完成组件安装和协议确认。
2. 打开 `app/ios/WorkMemory.xcodeproj`，选择 WorkMemory scheme。
3. 在 Xcode Settings → Accounts 登录自己的 Apple 账户。密码和验证码只在 Apple 窗口填写。
4. 选择 WorkMemory target → Signing & Capabilities，启用自动签名，选择自己的 Team。首次安装使用唯一 Bundle Identifier，例如 `com.yourname.workmemory`，把 `yourname` 替换成自己的英文标识。如果是更新已有安装，必须保留原来的标识和 Team。
5. 如需测试 WorkMemoryUITests target，同样配置自己的 Team 和对应 `.uitests` 标识。
6. 连接并解锁 iPhone，在手机提示时信任电脑。按系统要求开启“设置 → 隐私与安全性 → 开发者模式”，重启后确认。
7. 在 Xcode 运行设备中选择自己的 iPhone，点击 Run。首次运行如提示开发者不受信任，在手机“设置 → 通用 → VPN 与设备管理”中信任自己的开发者账户。
8. 打开“工作记忆”，先做一段本地短录音并回听；随后可测试导出。真正的长时间锁屏、来电和异常恢复仍需自行验证。

## 把签名身份留在本地（推荐给开发者和 Codex）

先完成 Apple 登录并取得自己的 Team ID，然后运行下面的命令，替换示例参数，不要照抄占位值：

```sh
python3 scripts/generate_project.py --team-id YOURTEAMID --bundle-id com.yourname.workmemory
```

它把 Team 和 Bundle Identifier 保存在 `app/ios/WorkMemory/Signing.local.xcconfig`，这个文件不上传 GitHub；共享项目通过 `Signing.xcconfig` 可选引用它。Team ID 是标识，不是密码；不要把证书私钥或密码放进任何配置文件。后续直接运行 `python3 scripts/generate_project.py` 会保留本地配置。

只用 Xcode 页面配置也可以，但 Xcode 可能把身份写进共享 project 文件；向项目提交修改前应移除这些个人配置。若重新生成项目，建议先使用上述本地配置方式，以保留 Bundle Identifier。

## 配置自己的 AI

在手机“设置 → AI 服务”选择“APIMart 转写 + DeepSeek 提炼”，分别填写两家的凭证并保存。也可选择只用 APIMart。凭证只存此手机钥匙串，不要发到聊天、GitHub Issue、源码或截图里。

录音详情中打开“文字与重点分析”，检查接收服务后确认发送。先用不敏感的短录音测试，保持 App 在前台。服务是否可访问、模型权限、额度和价格以自己的账户为准，不保证任何地区的网络直连。

## 到期、更新和数据

免费 Personal Team 的安装授权通常 7 天到期，需要重新签名覆盖安装。开源不改变苹果安装规则；以实际 provisioning profile 到期时间为准。[苹果官方说明](https://developer.apple.com/help/account/basics/about-your-developer-account)

更新前导出重要录音和笔记，使用相同 Apple Team 与 Bundle Identifier 覆盖安装。不要先卸载。更换签名账户或标识不保证保留原安装数据，需先备份并单独处理迁移。本项目目前不提供完整备份导入功能，导出不等同于一键恢复。

## 常见情况

| 情况 | 怎么处理 |
| --- | --- |
| 没有 Mac | 本教程的原生编译安装流程需要 Mac；GitHub 源码不能在 iPhone 直接点开安装 |
| 提示 App ID 不可用 | 首次安装改用自己的唯一 Bundle Identifier；已有录音时不要贸然改标识 |
| 手机无法运行 | 核对 Xcode 是否支持手机系统、开发者模式、设备信任和签名有效期 |
| API 返回授权/额度错误 | 在服务商账户检查凭证权限和额度；不影响本地录音 |
| 想不花 AI 费用先体验 | 先只测试录音、回听和导出；本机中文转写尚未实现 |
| 需要长期或分享安装 | 开源下载与苹果分发是两件事，TestFlight/App Store 需要独立处理 |
