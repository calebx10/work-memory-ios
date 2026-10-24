# 复制给 Codex：帮我安装自己的工作记忆 App

这个项目开源的是 App 源码，不包含免费 AI 额度或作者的账户。需要一台 Mac、可用的 Xcode、iPhone 和自己的 Apple 账户。AI 凭证可在装好后自行填写；没有凭证也可以先录音、回听和导出。

## 最省事的方式

1. 在 Mac 上下载本仓库，或运行 `git clone https://github.com/calebx10/work-memory-ios.git`。
2. 在 Codex 中打开下载后的项目文件夹。
3. 复制下方整段文字交给 Codex。

```text
请帮我把当前开源项目“工作记忆”编译并安装到我自己的 iPhone。

先读 AGENTS.md、README.md、docs/INSTALL.md 和 docs/TEST_PLAN.md。
请检查当前 Mac 的 Xcode、Swift 和已连接 iPhone 的状态，先完成能够自动完成的检查、测试和编译，再逐步引导我处理必须本人完成的 Apple 登录、设备信任和开发者模式。

请使用我自己的 Apple 账户和唯一 Bundle Identifier。将个人签名配置放在项目已忽略的 Signing.local.xcconfig 中，不要写进共享源码；不要沿用原作者的签名身份。若我已有此 App 和录音，先核对原 Bundle Identifier 和 Team，保留它们并覆盖安装，不要卸载或清空数据。

不要在聊天中索取 Apple 密码、验证码、API 密钥，不要读取或输出钥匙串中的密钥。Apple 登录由我在 Apple 窗口完成；AI 凭证由我在手机 App 内填写。

不要替我购买服务、充值、上传录音或自动调用收费 API。安装完成后先指导我做一次本地短录音、回听和导出测试；只有我明确要测试 AI 时，再说明哪些内容会发给哪家服务商，让我在 App 内确认。

请告诉我实际完成了哪些检查、还有哪些需要真机验证、当前安装签名何时到期，以及以后如何保留录音更新安装。不承诺一次安装永久有效。
```

## 你仍需要亲自完成的步骤

Apple 账户登录、密码和验证码输入、法律协议确认、iPhone 上的信任与开发者模式，以及收费服务的选择和授权。Codex 可以协助准备和检查，但不能代替你的账户或权限。

其他问题见 [安装教程](INSTALL.md)。Codex 不是必要依赖：熟悉 Xcode 的用户也可以直接编译安装。
