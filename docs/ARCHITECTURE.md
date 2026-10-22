# iPhone 独立版架构

- SwiftUI + AVFoundation（iOS 17+）；手机本地保存录音和 AI 工作记忆。
- `Core/Recording.swift`、`LocalRepository.swift`：录音、分段、SHA-256 校验、原子元数据和备份、异常恢复。
- `Core/MemoryDocument.swift`：原始与修订转写、分析原稿与编辑稿、来源引用、选题状态、持久化任务状态。
- `Core/AIService.swift`：可注入 URLSession 的转写与结构化分析接口；默认 HTTPS，只接收显式配置地址，拒绝携带凭证的重定向。
- `WorkMemory/AIController.swift`：前台串行处理、逐段成功检查点、手动重试、前后台切换取消、删除中任务保护。
- `WorkMemory/SecureSettings.swift`：非密钥参数存 UserDefaults，密钥按服务地址存 Keychain（不同服务不共享密钥），保存时不联网。
- `MemoryViews.swift`、`SettingsView.swift`：原文、分析编辑、选题/口播稿、全库搜索、隐私和服务配置。

## 录音可靠性

AVAudioRecorder AAC M4A，44.1kHz 单声道 64kbps；playAndRecord + audio 后台能力。音频系统 record(forDuration:) 控制切段，不依靠前台 Timer 轮转。暂停/中断关闭当前文件，继续创建新段。切段可能有短暂间隙，不声称无缝。中断后需要用户主动继续。

Application Support/WorkMemory/Recordings/<UUID>/manifest.json 保存索引；切段意图在采集前持久化，完成后记录实际字节数、时长、SHA-256。文件保护 completeUntilFirstUserAuthentication，排除系统备份。重启检查未结束录音，恢复有效分段、保留不可读末段并提示确认。不保证异常退出时未封装的 M4A 可恢复。

## AI 与数据

每条录音目录有 memory.json 及有效备份，和音频一起导出。转写缓存按 segment UUID + SHA256 + 服务地址 + 模型标记；切换服务/模型不隐式清除已成功结果，用户可通过确认清除转写后重跑。分析另有 promptVersion、模型、服务和转写指纹。修改原文使旧分析标记为待更新，不自动发请求。

API 是无共享密钥的个人自用客户端。服务参数可配置，密钥仅由用户在安全输入框输入并写入 Keychain。本项目不包含公网服务、云数据库或遥测。端点必须 HTTPS、无 URL 账号密码/query/fragment。302 等重定向拒绝，不跨主机发送授权。

分析内容结构化校验；引用 ID 必须来自真实原文条目，未知引用不生成可点击来源。转写内容作为不可信引用文本，不能改变系统分析指令。长转写按有界分批提炼后合并，批次结果持久化，避免一次塞入超长上下文。选题初稿仅在用户点击后生成。

## 验证边界

Mac Swift Package 测试覆盖模型、恢复、校验、AI 协议解析、重试缓存、导出。Xcode 编译校验 iOS 全部代码；模拟器验证导航和离线流程，使用仅测试的 URLProtocol 模拟服务验证 AI UI。真机锁屏、电话中断、耗电必须另做实测。未配置真实 API 凭证前，不宣称真实服务转写/分析已通过。
