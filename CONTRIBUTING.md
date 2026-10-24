# 参与改进

欢迎报告问题、补充真机测试和提交 Pull Request。个人安装请先看 [安装教程](docs/INSTALL.md)；AI 费用由使用者自行承担。

提交问题时提供 iOS/Xcode 版本、操作步骤、预期和实际结果。不要提交 API 密钥、Apple 账户信息、真实录音、完整转写或其他人的隐私内容；截图先脱敏。安全问题按 [SECURITY.md](SECURITY.md) 处理。

修改代码前阅读 [AGENTS.md](AGENTS.md)。新增 Swift 源文件后运行项目生成器，提交前至少运行：

```sh
swift test
python3 scripts/check_project.py
```

涉及 Xcode 项目或签名时验证模拟器编译；涉及录音、后台和中断时说明真机检查结果，没测试的情况明确写出。不要用收费 AI 请求作为自动测试。每个 PR 聚焦一个问题，说明变化、验证和已知限制。

本项目采用 [MIT 许可证](LICENSE)，贡献应有权按相同条款提供；引入第三方代码时保留其许可证和来源，不把不明来源的代码当作原创提交。
