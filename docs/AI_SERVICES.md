# 服务与费用（核对日期：2026-10-22）

使用量可从偶尔短录音到每天数小时不等。录音先本地保存，收费分析必须用户确认。不能把“已录音时长”当成“已产生费用”。

## 当前可用配置

- APIMart 单服务：`https://api.apimart.ai/v1`，`whisper-1` 转写，`gpt-4o` 分析。一次填写一份凭证；不代表最低费用。
- 日常整理组合：APIMart 转写 + DeepSeek 官方 `https://api.deepseek.com`，`deepseek-flash` 提炼和初稿。需要两份凭证，由 App 自动衔接。
- DeepSeek 官方当前公开接口没有列出音频转写能力，不能单靠其文本模型替代转写。

APIMart 音频按公开文档使用 JSON 中文转写；聊天明确非流式，普通 JSON 提示并在本地校验字段、来源。DeepSeek 使用 JSON mode，明确关闭默认的思考模式、限制输出，减少日常整理不必要的推理用量。结果不完整或来源无法核对时拒绝采用。

## 价格与估算边界

DeepSeek 官方 Flash（人民币/百万 tokens）：未缓存输入空闲 1 元、高峰 2 元；输出空闲 4 元、高峰 8 元。因此单次若总输入 20,000、总输出 3,000，约 0.032～0.064 元。只是文字调用的示例，不是每小时录音报价；长录音分批、合并、初稿、重试会增加用量。

APIMart Whisper 的当前实际单价尚未得到可核实的公开报价，需要按用户账户模型价格页和实际账单确认。不得将 OpenAI 价格冒充 APIMart 价格。仅作独立参考，OpenAI Whisper 公布价 0.006 美元/分钟：每月 30/90/180 小时分别为 10.8/32.4/64.8 美元，不含文字分析，不含汇率换算。

先用短录音验证质量、实际扣费和失败重试行为；不要在没有核价时自动处理全天录音。不自动充值、不自动购买会员、不把请求失败当作免费。

## 本机转写候选（尚未实现或真机验证）

Apple 提供本机语音识别能力；需要检查实际机型、系统、语言和模型资源。旧 SFSpeechRecognizer 有任务时长和服务限制，不能仅凭本机识别开关保证几小时录音稳定。优先评估新版 SpeechAnalyzer 对已保存长音频的处理，确认普通话支持、准确率、耗电和恢复能力后再决定是否作为默认。未通过真机验收前不宣称离线中文转写可用。

## 官方依据

- [APIMart Whisper 接口](https://docs.apimart.ai/en/api-reference/audios/whisper-1)
- [APIMart 快速开始](https://docs.apimart.ai/en/quickstart)
- [DeepSeek 价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)
- [DeepSeek 思考开关](https://api-docs.deepseek.com/zh-cn/guides/thinking_mode/)
- [DeepSeek JSON mode](https://api-docs.deepseek.com/zh-cn/guides/json_mode/)
- [OpenAI Whisper 价格，仅用于参考](https://developers.openai.com/api/docs/models/whisper-1)
- [Apple 本机识别支持检查](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
