# XR 真机验证记录

设备：iPhone XR，iOS 18.7.9。
工具：Xcode 27.1（27A9275），iOS 27.1 SDK，最低部署版本 iOS 18.0。

## 已确认

- 已用 Personal Team 自动签名，安装并启动 `com.example.deskpet`。
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO build`：通过。
- `xcodebuild ... -destination 'platform=iOS,id=…' -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`：通过。
- `codesign --verify --deep --strict`：通过。
- `plutil -lint`：Info.plist 和 project.pbxproj 通过。
- `swiftc DeskPet/Gaze.swift Tests/main.swift` 后运行：6 项方向、中心位置和边界测试通过。
- 实际手机生成统计记录，证明前摄采集和 Vision 人脸检测已运行。

## 首轮手机记录

| 运行秒数 | 累计处理样本 | 累计检测到脸 | 最近一次检测耗时 | 系统热状态 |
| --- | --- | --- | --- | --- |
| 3.1 | 1 | 1 | 308.97 ms | 正常 |
| 13.3 | 72 | 68 | 44.45 ms | 正常 |
| 23.3 | 140 | 130 | 49.98 ms | 正常 |
| 33.3 | 208 | 192 | 38.87 ms | 正常 |
| 43.3 | 278 | 241 | 41.24 ms | 正常 |
| 53.4 | 345 | 304 | 39.26 ms | 正常 |
| 63.5 | 414 | 373 | 52.23 ms | 正常 |

这些是每 10 秒一次的快照，不是完整延迟分布；耗时只包含 Vision 请求，不代表端到端跟随延迟。热状态来自 iOS 的等级接口，不是摄氏温度。

## 尚待验收

- 横屏前摄是否正向，诊断人脸框是否与脸重合。
- 左右移动时眼睛方向是否正确，平滑度是否自然。
- 离开后重新出现、触摸互动、切后台后恢复。
- 30～60 分钟插电运行的热状态和稳定性。

## 曾遇到并已解决

- 工程首次构建重复打包 Info.plist：将 plist 放到同步源码目录外后解决。
- Swift 模块显式导入错误：补充 CoreGraphics 后解决。
- 初次通用设备签名未注册 XR：指定实际设备后生成签名成功。
- 手机锁定导致调试镜像挂载失败：用户解锁后解决。
- 首次启动需要信任个人开发者：用户确认信任后成功启动。

当前构建仍有一条非阻断提示：没有 AppIntents 依赖，因此跳过其元数据提取；原型未使用该功能。

## v0.2 方向修正

用户真机反馈：左右移动时绿色人脸框方向相反；附图显示框与人脸未重合。

修改：取消独立的 AVCaptureVideoPreviewLayer；捕获画面在前摄横屏方向下统一旋转并只镜像一次，生成同一张 CGImage 用于 Vision 与 UIImageView 预览。绿色框按该图的实际尺寸和等比留边转换。眼神读取同一份观测坐标。

新增不重复镜像、纵坐标转换及等比留边测试，总计 9 项通过。v0.2 已通过签名编译及 codesign 校验，已覆盖安装并成功启动。

用户复测确认：“贴着了”，即绿色框已贴住人脸。眼睛使用同一份位置数据；眼神动作的主观自然度尚未单独确认。

v0.2 运行 30.9 秒时累计处理 208 个样本，197 次检测到人脸；最近一次 Vision 请求耗时 47.89 ms。期间系统热状态为 fair（温热），尚不能据此推断长期稳定性。

## v0.3 陪伴互动

新增抚摸、长按安抚、连续戳躲闪；自然注意力、目送、打瞌睡与唤醒；六种程序合成的电子叫声；运动与倾斜反应；折叠菜单。静音和运动开关保存在本机。声音遵循系统静音开关，不使用麦克风。

所有新增 Swift 文件使用 4 空格缩进；保留现有源文件缩进，未新增第三方依赖。

验证命令：

```sh
swiftc outputs/DeskPet/DeskPet/Gaze.swift outputs/DeskPet/DeskPet/PetBehavior.swift outputs/DeskPet/Tests/main.swift -o work/deskpet-behavior-tests
work/deskpet-behavior-tests
xcodebuild -project outputs/DeskPet/DeskPet.xcodeproj -scheme DeskPet -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath work/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project outputs/DeskPet/DeskPet.xcodeproj -scheme DeskPet -configuration Debug -destination 'platform=iOS,id=…' -derivedDataPath work/DerivedData -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
codesign --verify --deep --strict work/DerivedData/Build/Products/Debug-iphoneos/DeskPet.app
plutil -lint outputs/DeskPet/Info.plist outputs/DeskPet/DeskPet.xcodeproj/project.pbxproj
```

结果：36 项断言通过，包括方向、留边、欢迎防抖与冷却、欢迎不打断安抚、睡眠唤醒、抚摸与连续戳、前后台重置、运动持续时间过滤。无签名编译、最终签名编译、签名校验和 plist 校验均通过。最终版本已安装到 XR 并由设备工具确认启动。

原有的 AppIntents 元数据提取提示仍存在，不阻断构建。当前没有额外配置 SwiftLint 或独立 UI 自动化测试。

真实手感、声音是否合适、运动误触发情况及长时间稳定性，仍需用户真机体验；运动算法只能识别持续移动与放稳，不能可靠区分拿起、桌面移动或持续晃动。

安装后从手机回收的最新记录：运行 61.6 秒、处理 396 个样本，396 次检测到脸，最近一次 Vision 请求耗时 39.71 ms；系统热状态 fair（温热）。用户收到互动复测请求后回复“好了”，未报告新问题；该回复不等同于对所有细节和长时间稳定性的逐项确认。

## v0.4 / v0.5 语音与本地唤醒

- 用户已确认按钮启动的语音能够识别、得到 AI 回复。
- v0.5 已签名编译、codesign 校验、覆盖安装并启动；真机日志有 `model ready=true`、`recording=true`、`voiceProcessing=true`、`state: armed`。
- 真机实际出现 `local wake: detected`，随后进入 listening，说明本地唤醒已触发；之后苹果本机识别报 `kLSRErrorDomain / 201`。
- 用户确认系统听写一直开启。修复：201 不再优先阻断联网回退；已允许联网时只回退一次，后续本次运行保持联网策略；没有联网许可不会上传录音。
- 官方 master 的 Swift 包装代码和 1.13.8 二进制不一致导致首次构建失败。固定到 v1.13.8 对应提交后构建通过。
- Swift 方向、行为、取消、断句、API 校验、结束口令和识别回退测试通过。命令：`swiftc DeskPet/Gaze.swift DeskPet/PetBehavior.swift DeskPet/ConversationCore.swift Tests/main.swift -o <test-binary>` 后运行。
- macOS 上用同一模型、Sherpa 原生库和系统 Tingting 合成音进行流式烟雾测试：“小宠小宠”命中 1 次，一段普通天气/工作语句命中 0 次。该测试只验证模型配置和基本区分，不能代表真人唤醒率或 XR 推理速度。
- `xcodebuild ... -clonedSourcePackagesDirPath work/SourcePackages ... build` 及 `codesign --verify --deep --strict` 均通过。仍仅有无 AppIntents 依赖的非阻断提示。
- 尚待确认：201 联网回退在手机上的实际识别结果、连续多轮聊天、不同距离/噪声下误唤醒率与全双工插话。主人声纹按用户要求暂不开发。

### v0.5.1 现场复测结果

- 给本地唤醒增加“我在，你说”的语音确认，播放后再进入识别；确认语不加入 AI 对话历史，也不开启实验插话识别。
- 唤醒阈值从 0.35 调整为模型默认 0.25，保持关键词加分 1.5。
- 修复版已再次通过 `xcodebuild ... build`、`codesign --verify --deep --strict` 并覆盖安装。`plutil -lint Info.plist DeskPet.xcodeproj/project.pbxproj` 通过。
- 真机日志确认：local wake detected → speaking → listening → 本机 201 → 联网 recognition → waiting（AI 请求）。随后用户对“是否听到确认语、是否能接着问第二句”的联合验收回答“可以”，确认实际唤醒和连续聊天可用。
- 扩展合成音测试：Tingting 慢速、快速各命中 1 次；近音句与普通桌面语句均 0 次误命中。Eddy 中文合成音样本未命中，正样本断言失败，已知不同音色仍可能漏唤醒；不能据这些样本宣称全音色稳定。
- 目前通过的是前台唤醒与连续轮流对话；全双工语音插话仍为实验，未单独验收。声纹暂不做。

## v0.5.2 正常音量唤醒调整

用户反馈：需要重复、大声喊才会唤醒。检查确认此前待唤醒和对话共用 voiceChat + Voice Processing；该处理是否为唯一原因尚不能确定。

修改仅限收音切换与诊断：待唤醒使用 playAndRecord / measurement，关闭 Voice Processing；KWS 命中后重启同一音频引擎，切回 voiceChat 并启用 Voice Processing，再播确认语和进行对话。关键词阈值保持 0.25、加分保持 1.5，没有继续放宽。

增加每约 5 秒的累计输入时长、最响缓冲 RMS（dBFS）和处理队列丢帧计数；不记录或保存声音。真机已看到 measurement / voiceProcessing=false 与 voiceChat / voiceProcessing=true 正确往返，以及多次 local wake detected；采样窗口未见丢帧。

首次调整将 Voice Processing 切换放在音频会话激活之前，真机麦克风初始化失败。改为先配置并激活会话，仅在状态确需改变时切换 Voice Processing 后，启动和唤醒切换成功。

验证命令：`xcodebuild ... build`、`codesign --verify --deep --strict`、`plutil -lint Info.plist DeskPet.xcodeproj/project.pbxproj` 通过；已覆盖安装并启动。此改动依赖真机音频路由，未用纯 Swift 单元测试冒充硬件验证。

用户对正常音量是否更易唤醒反馈“好像是”，属于初步改善，不代表已完成唤醒率、误唤醒率或远距离验收。需要继续根据日常使用反馈判断稳定性。

参考 Apple 官方说明：measurement 减少系统音频处理；voiceChat 面向双向通话。https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement ，https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat 。

## v0.5.3 “网络连接失败”诊断与恢复

原真机日志有两次“识别完成 → waiting → 网络连接失败”，但未记录原始错误码，无法追溯这两次是否确为网络故障。代码检查发现 JSONDecoder 等非 ChatFailure 异常均被外层误报成 network。

复现：XR 使用钥匙串中的 Key、非敏感固定测试问题做三轮带历史请求。两轮测试都出现前两次 HTTP200 有效，第三次 HTTP200 / finish=stop 后在内层 JSON 解码失败（invalid JSON or null field）。证明至少存在“请求成功、回答解析异常”的误报路径；没有记录返回正文，不能断言当次具体是空串还是 null 等内容。DeepSeek 官方 JSON 模式文档也明确提示偶发空内容：https://api-docs.deepseek.com/guides/json_mode/ 。

修复：

- 分类超时、离线、DNS、安全连接、连接中断、HTTP服务错误、无效回答与未知异常；JSON 解码失败不再冒充网络断开。
- 请求仅记录匿名请求编号、尝试次数、HTTP状态、响应字节数、耗时、错误域/码，以及结构化校验元数据；不记录 Key、聊天正文或录音。
- 系统提示补充明确 JSON 示例和非空要求；发送历史时把已说完的 assistant 文本编码成相同的 speech/mood 结构，避免模型历史示例与输出要求不一致。
- 对 URLSession -1005 中途断连、HTTP200 的空内容最多重试一次；超时、HTTP错误等不自动重试。不把截断或无效JSON读给用户。
- AI失败后按本地唤醒开关回到待唤醒，保留错误提示。待唤醒不依赖苹果整句识别服务是否在线可用，但仍检查已有权限。

验证：`swiftc DeskPet/Gaze.swift DeskPet/PetBehavior.swift DeskPet/ConversationCore.swift Tests/main.swift -o <binary>` 后运行通过。新增 URLProtocol 模拟传输验证断连后成功、持续断连上限、超时不重试、HTTP500不重试、格式异常分类、HTTP200空内容恢复及持续空内容上限。模拟测试不代表外网稳定性。

`xcodebuild ... build`、`codesign --verify --deep --strict` 和 `plutil -lint Info.plist DeskPet.xcodeproj/project.pbxproj` 通过，已覆盖安装。早期诊断入口曾把成功 API 请求接到未验证的纯 TTS 输出路径而出现朗读不可用；随后改为独立、静默的 API 探针，此诊断现象不用于判断网络失败。

最终现场结果：修改输出示例与历史格式后，XR 的三轮固定探针全部返回有效 JSON；随后同一进程又完成三次实际语音触发的 AI 请求，均 HTTP200、结构校验通过且进入 speaking。合计连续 6 次，单次 AI 请求约 0.64～0.98 秒，均未触发重试。这只代表当前样本，不能据此保证今后不会出现真实网络故障。探针结束后已自动恢复本地待唤醒，未重启正在使用中的连续对话。

## 公开版本验证

公开副本移除了个人 Team 和 Bundle 命名、环境变量注入 Key 的专用辅助入口、Xcode 用户状态；Keychain 服务改为随当前 App 的 Bundle ID 生成。公开版本没有携带原手机的 Key，不覆盖原型手机当前安装。

公开目录单独执行 `./scripts/test.sh` 通过；`xcodebuild -project DeskPet.xcodeproj -scheme DeskPet -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath <本地构建目录> CODE_SIGNING_ALLOWED=NO build` 通过。仅保留未使用 AppIntents 的非阻断提示。`plutil -lint`、本地文档链接检查、模型 SHA-256 校验通过。无签名构建不能当成已在另一台手机完成部署。

发布前用 Gitleaks 8.30.1 扫描公开副本，未发现凭据；另行检查个人设备标识、本机绝对路径、签名身份和实际提交文件。测试中出现的 test-key、example.invalid 等均为不可用测试占位值。日志、证书、用户状态、原始照片/音视频和构建产物不纳入提交。

## v0.5.4 唤醒漏检修正

用户再次反馈正常位置需要重复、大声喊；此前“好像改善”的主观反馈不足以认定问题解决。对比后更换推荐词、模型与 KWS 输入音量补偿，阈值保持不变。完整样本和失败条件见 [唤醒对比记录](wake-benchmark.md)。

初步合成对比中旧词仍有漏检；最终配置新词 18/18、兼容词 7/9、负样本 0/30 误触发。此结果不是实际用户统计。未保存或上传用户声音。

v0.5.4 自动检查：`./scripts/test.sh`、模型 SHA-256 校验、`git diff --check` 通过；公开工程无签名构建、原机签名构建和 codesign 校验通过。实际启动确认模型就绪，RMS 诊断持续运行，当前窗口未见丢帧。Gitleaks 扫描约 13.26 MB 未发现凭据；无个人签名、设备 ID 或本机路径进入本次更改。

尚待用户在原位置以自然音量完成“三次中几次一遍命中”的复测；未将合成样本成绩作为真人验收通过。新模型比旧模型大、候选路径更多，长时间功耗和发热仍需观察。

现场反馈补充：用户确认新词“比之前好了”，要求仅保留“瓦力瓦力”并提交推送。已移除旧关键词；历史对比数据保留供追溯，不表示当前仍兼容旧词。单关键词配置合成样本复跑：18/18 正样本命中，39 个负样本均未触发。用户未提供具体逐次命中数。

## 系统音色与试听入口

用户试听后选择 Rocko（zh-CN）作为默认音色。默认选择优先匹配该音色；设备没有时回退可用普通话音色，菜单的手动选择仍然保留。XR 运行日志已确认 `Rocko / zh-CN`，并已在原设备保存为当前选择。

修复原试听入口的音频配置失败：试听复用已经验证的通话音频播放路径，不启动整句识别、不调用 AI、不把试听句加入对话历史；播放完成后按已有开关恢复待唤醒。实际签名构建和 codesign 校验通过，用户已确认试听能播放。

## v0.6.0 全双工插话验证

新增 `DuplexGate` 纯逻辑回归：回声文字过滤、累计转写中的已知回声前缀移除、尾音过滤、插话开头保留、敲击不取消、延迟转写保留能量证据、无文字噪声恢复音量、低音量与音节间隙。`./scripts/test.sh` 通过。这些是逻辑验证，不能代替真实声学测试。

首次 XR 现场测试失败：用户正常说“等等”没有打断。追加仅含能量、字符数与状态的诊断后，确认朗读中有识别文字返回，但多次峰值约 0.006～0.009，旧版固定下限 0.008 和连续计时要求把插话挡住；期间也有更高峰值，单纯峰值超阈值不能证明连续条件成立。随后降低能量下限，改为估计噪声底和累积有效时长，允许音节间短暂停顿；加入对应回归样本。未保存或记录用户语音、转写正文。

已通过原机签名构建、公开工程无签名构建与 `codesign --verify --deep --strict`；Xcode 唯一构建提示为未依赖 AppIntents，因此跳过其元数据提取。XR 日志确认 voiceChat / Voice Processing=true、Rocko / zh-CN 和本机 201 后联网回退。首次固定长句期间未看到确认插话事件，不能宣称全双工验收通过。

DEBUG 启动参数 `--duplex-self-test`：播放固定长句并同时开启识别，不为测试句请求 AI；测试句播完仍回到连续倾听。测试会打开全双工开关，使用手机已有识别授权和已配置 Key；用户插入的问题会沿正常路径调用 AI。诊断日志不应提交公开仓库。

仍需现场验收：正常音量打断并接住完整问题、AI 思考期间改口、安静时不自我打断、敲桌与持续噪声恢复、连续多轮、后台和系统中断。不能将模拟回归、短暂安静窗口或一次成功等同于长期可用率。

门槛修正后现场复测：用户确认在原位置直接提新问题“可以，会转而回答”。日志对应到朗读中 `confirmed interruption`、同一识别请求继续增加转写字符、新请求 HTTP200 与有效回复、再次进入 speaking；窗口内还看到后续插话链路成功。只能认定本次正常音量插话通过，未统计延迟或长期误触发率。没有把诊断中的正文或录音加入仓库。

## v0.7.0 外观与跟随试验

新增琥珀发光眼、实时眼核跟随、左右眼差异与抚摸后的缓慢恢复。珠光材质试验及后续方向调整、较热时只有约 2 fps 的跟随问题、缓存光影和相机实际采集频率修复，详见 [外观与性能记录](face-design.md)。新外观与长期流畅度仍在现场试验中，不能把构建通过或单张导出图当作全面体验验收。
