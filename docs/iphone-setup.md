# iPhone 安装、换机与排错指南

按“拿到一台新手机，从零开始”的顺序操作。已验证 iPhone XR / iOS 18.7.9、Xcode 27.1；其他机型达到最低 iOS 18 要求，也不等于所有硬件行为已验证。

## 1. 准备 Mac 与代码

1. 从 Mac App Store 安装 Xcode，或从 [Apple Developer 下载页](https://developer.apple.com/download/all/) 下载。先核对该版本对 macOS 的要求。
2. 第一次手动打开 Xcode，接受许可，完成必要组件安装。
3. 在 Xcode → Settings → Apple Accounts（有些版本叫 Accounts）登录自己的 Apple 账户。App Store 已登录不等于 Xcode 签名账户已登录。
4. 克隆并打开工程：

```sh
git clone https://github.com/Pandas886/deskpet-ios.git
cd deskpet-ios
open DeskPet.xcodeproj
```

真机安装不需要下载 iOS Simulator runtime，开发文档下载也不是前提。Xcode 可能仍需为连接的设备准备调试支持，等待其完成。

检查命令行工具选择：

```sh
xcode-select -p
xcodebuild -version
```

如果选择的是独立 Command Line Tools，而不是完整 Xcode：

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

Mac 密码只在自己的终端输入，不写入脚本、仓库或聊天。

## 2. 连接并信任电脑

1. 用能传数据的线连接 iPhone 与 Mac；只充电的线不够。
2. 解锁手机，选择“信任此电脑”，按提示输入手机密码；Finder 如有信任提示也需完成。
3. 在 Xcode 的设备管理窗口确认手机已配对。版本不同可能叫 Devices and Simulators 或 Device Hub。
4. 安装和启动期间保持手机解锁。调试镜像无法挂载时，先解锁再重试，不必立即重装 Xcode。

## 3. 开启手机开发者模式

1. 先让 Xcode 连接并识别手机，必要时选择这台设备尝试一次开发运行。
2. 手机“设置 → 隐私与安全性 → 开发者模式”，开启并按提示重启。
3. 重启后解锁，在确认窗口再次启用，按提示输入密码。
4. 返回 Xcode，等待手机重新连接。

如果开关没出现，先检查配对和首次开发运行是否完成，不要因此刷机或安装测试版系统。[Apple 官方说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

## 4. 设置签名并运行

1. 在 Xcode 选择工程 → **DeskPet target → Signing & Capabilities**。
2. 保持 `Automatically manage signing` 开启。
3. `Team` 选择自己的团队；未加入付费开发者计划的账户通常显示 Personal Team。
4. 将 `com.example.deskpet` 改成自己的唯一 Bundle Identifier，例如 `com.yourname.deskpet`。这是命名示例，不是共享签名身份。
5. 运行目标选择实际连接的 iPhone，而不是通用设备或模拟器。第一次自动签名需要网络，并可能注册该设备。
6. 点击 Run，等待构建、签名、安装和启动。

公开工程没有包含任何人的 Team、证书、描述文件或设备注册信息。换机后可以继续使用 Mac 上已有的 Apple 账户，但新设备仍需配对、开启开发者模式并完成签名注册。

个人免费签名有设备、App 和有效期限制，过期后可能打不开，需要连接 Mac 重新 Run。这不是永久安装，也不是 App Store 分发；以 [Apple 当前个人团队限制](https://developer.apple.com/help/account/basics/about-your-developer-account) 为准。

## 5. 首次开发者信任

如果 App 已安装却提示“不受信任的开发者”：

1. 手机“设置 → 通用 → VPN 与设备管理”。
2. 在开发者 App 下核对自己签名所用的账户，选择信任或验证。
3. 如果系统要求联网、允许并重启，按当前手机的提示完成。
4. 再打开“桌面小宠”。

仅在确实出现此提示时操作，不同 iOS 和签名类型界面可能不同。没有开发者 App 列表时，先确认安装完成。[Apple 企业 App 信任说明](https://support.apple.com/118254)可供了解系统提示，但企业分发流程不能直接等同于个人签名流程。

## 6. 首次权限和 API 设置

1. 允许相机权限；拒绝后仍能触摸互动，但不能跟随人脸。
2. 右上角“…”→“AI 与 API Key 设置”，在手机填写自己的 DeepSeek Key。默认地址 `https://api.deepseek.com`，模型 `deepseek-flash`。
3. 点右下角麦克风，允许麦克风和语音识别。系统权限窗口会打断首次启动；允许后可能要再点一次。
4. 先用按钮问一句简单问题，确认能识别和回答，再检查“本地唤醒：瓦力瓦力”开关。
5. 本机识别不可用时，可自行允许“苹果联网语音识别”，此时录音可能由苹果处理。唤醒模型本身不需要联网。
6. 叫“瓦力瓦力”，听到“我在，你说”后再提问。

Key 只存手机 Keychain，并设置 `WhenUnlockedThisDeviceOnly`。换机需要重新填写；更换 Bundle Identifier 后，公开版的 Keychain 服务名也会变化，需要重新配置。源码或编译产物不会携带旧手机的 Key。

不要将 Key 放进 Swift、Info.plist、共享 Scheme、终端命令、截图、Issue 或 Git 提交，也不要分享包含设置内容的截图。

## 7. 摆放、音色和日常运行

- 按屏幕文字的方向横放到固定支架，前摄无遮挡。
- “…”→“打开诊断”，核对预览正立、人脸框贴合、左右移动时眼睛方向一致。前摄旋转目前在 XR 上验证，换机必须复测。
- “中文音色试听”选择声音。如缺少声音资源，可在 iPhone“设置 → 辅助功能”搜索“朗读内容”或“声音”，选择中文并按系统提示下载；入口和音色随系统版本变化。下载音色不是下载唤醒模型。
- 确认 App 静音关闭、系统音量合适，声音没有输出到别的蓝牙设备。基础电子叫声与通话音频的静音行为未必完全一样。
- 保持 App 前台。前台会禁止自动锁屏，切后台停止采集。不要为部署永久关闭手机密码或锁屏保护。
- 待唤醒会持续使用麦克风，系统麦克风指示属于正常现象。切后台停止采集；关闭本地唤醒并结束会话也会释放麦克风。
- 回答完自动接着听；说“不聊了”或约 8 秒无识别文字回到待唤醒。关闭本地唤醒时，结束会话会停止收音。
- 安装、授权和 Key 配置完成后，可以拔掉数据线；Mac 无需常开，但 AI 对话仍需要手机自己的网络。

## 8. 命令行安装与诊断

先在图形界面完成账户、签名和首次配对。下面的设备 ID、Bundle ID 是占位符，仅在本机替换；不要提交替换后的个人设备信息。

列出设备：

```sh
xcrun devicectl list devices
```

针对真机构建，让自动签名处理设备注册：

```sh
xcodebuild -project DeskPet.xcodeproj -scheme DeskPet \
  -configuration Debug -destination 'platform=iOS,id=<设备ID>' \
  -derivedDataPath .build-ios \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

验证签名、安装、启动：

```sh
codesign --verify --deep --strict .build-ios/Build/Products/Debug-iphoneos/DeskPet.app
xcrun devicectl device install app --device '<设备ID>' \
  .build-ios/Build/Products/Debug-iphoneos/DeskPet.app --timeout 60
xcrun devicectl device process launch --device '<设备ID>' \
  --terminate-existing '<自己的BundleID>'
```

需要观察日志时：

```sh
xcrun devicectl device process launch --device '<设备ID>' \
  --terminate-existing --console '<自己的BundleID>'
```

命令不会绕过手机解锁、信任和系统权限。USB 已连接也不意味着当前系统支持远程屏幕控制。

核验仓库中的模型文件：

```sh
shasum -a 256 -c ThirdParty/models.sha256
```

## 9. 常见问题

| 现象 | 检查方法 |
| --- | --- |
| Xcode 找不到手机 | 数据线、解锁、信任此电脑和设备配对状态 |
| 没有 Developer Mode 入口 | 先完成 Xcode 配对并尝试开发运行，再回手机设置查看 |
| 调试镜像挂载失败 | 手机是否锁屏，开发者模式重启确认是否完成 |
| 需要团队或签名失败 | Xcode 账户、自己的 Team、唯一 Bundle ID、实际真机是否选对 |
| 安装后打不开 | 首次开发者信任、开发者模式，或个人签名已过期 |
| 更新后多出第二个 App | Bundle ID 改了；新 App 的设置和 Key 要重新填写 |
| 授权后没有开始听 | 授权窗口可能中断启动，回到前台再点一次麦克风 |
| 苹果识别错误 201 | 本机识别在听写已开时也曾报错。可检查“设置 → 通用 → 键盘 → 启用听写”，但不能仅凭此码断定开关关闭；已允许时会回退联网识别 |
| 唤醒要喊很多次 | 确认前台、本地唤醒开关和麦克风权限。距离、音色和噪声仍可能导致漏检 |
| 说完没自动发送 | 看有无转写；可点麦克风手动发送，背景持续声音也会影响断句 |
| “手机无法联网” | 检查手机 Wi-Fi/蜂窝网络及该 App 的网络权限，Mac 有网不等于手机有网 |
| AI 超时、服务拒绝、空回答 | 分别检查服务状态、Key/模型/余额和具体提示；HTTP200 不代表内容一定能解析 |
| 没声音 | App 静音、系统音量、蓝牙输出路由、中文声音资源、是否仍在等待 AI |
| 人脸框或眼神方向不对 | 先用诊断核对同帧预览；不同机型需验证旋转参数，不能简单再镜像一次 |

## 10. 换机验收清单

- [ ] 新机系统至少 iOS 18，Xcode 能识别并配对。
- [ ] 开发者模式开启，完成重启后的确认。
- [ ] 签名、安装、首次开发者信任完成，能启动 App。
- [ ] 相机、麦克风、语音识别权限按需授予。
- [ ] 新机重新填写 Key，明确是否允许苹果联网识别。
- [ ] 预览、人脸框和眼睛跟随方向正确。
- [ ] 轻点、抚摸、长按、拿起和放稳有对应反应。
- [ ] 正常音量能唤醒，确认语听得见，能连续问两轮。
- [ ] “不聊了”后回到待唤醒，切后台不继续收音。
- [ ] 音色、静音、蓝牙路由正确；持续插电运行时观察热状态和稳定性。
- [ ] 记住个人签名过期后需要重新 Run，不把一次安装当作永久安装。
