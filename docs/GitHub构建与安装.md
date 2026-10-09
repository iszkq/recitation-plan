# GitHub 构建与安装

## 当前范围

项目已有真实 Flutter 页面和本机数据链路，可以上传 GitHub 验证构建。它是本机文字与 iOS 语音背诵 App；HTML 仍是设计原型。

本机版包含文本导入、分段调整、计划日期/学习日/配额/通过门槛、全文阅读、无提示文字/语音考核、间隔复习、计划详情和周/月/年报告。考核通过由一致率、覆盖率及规则共同决定，读取原文不会自动打卡。备份使用 JSON 档案，恢复前检查校验和及冲突并保留原档案。

## 上传源代码

最新源码以 GitHub main 分支为准。旧设计交付 ZIP 不代表当前应用版本；复制源文件时保留 .github、product、docs、scripts、ui 和根 README/AGENTS/.gitignore。

不要上传 `.tools`、`.dart_tool`、`build`、本机数据库、录音、证书和缓存。`vendor/remember-me` 只是保留许可的上游参考快照，当前 App 构建不依赖它。

目标仓库为 https://github.com/iszkq/recitation-plan 。账户和应用签名身份可后续配置。

## 自动构建

`.github/workflows/flutter.yml` 在修改 `product` 后运行，也可从 Actions 手动触发。

1. Ubuntu 安装 Flutter 3.47.6，运行核心层分析/测试、App 分析/组件测试。
2. 检查通过后，macOS 使用 Xcode 编译 `flutter build ios --release --no-codesign`。
3. 成功时下载 `ios-unsigned-ipa` 构建产物，其中包含 IPA 与 SHA-256 校验值。

运行记录：Actions `37747539181` 已通过核心 37 项测试、App 的 5 项页面测试，并完成 macOS/Xcode iOS Release 编译。构建日志确认 `Xcode build done`，产物校验通过。

`recitation-plan-unsigned.ipa` 内含 `Payload/Runner.app`，属于未签名包，安装前需重新签名；不能直接用于 TestFlight。

## 安装到 iPhone

开发调试：在有 Xcode 的 Mac 打开 `product/app/ios/Runner.xcworkspace`，为 Runner 选择自己的开发团队，然后连接 iPhone 运行。已有安装需要保留此前实际使用的 Bundle ID 与签名身份；仅首次安装或创建独立测试应用时才改为账户可用的新标识。个人 Apple ID 的免费开发签名有有效期和设备限制。

长期内测：准备付费 Apple Developer 账户、App Store Connect 应用、唯一 Bundle ID、签名证书和描述文件。在 macOS 配置签名后执行 `flutter build ipa --release`，上传 App Store Connect，再用 TestFlight 安装。GitHub 可以自动做此步骤，但必须先将签名和上传凭据放入仓库 Secrets；项目没有预置这些凭据。

现有 Bundle ID 为 `cn.recitation.recitationApp`。覆盖升级须保留旧安装实际使用的标识与签名身份，不要先卸载旧应用。若首次正式上架需要更换标识，应先规划本机档案迁移。

## 发布前待办

- iPhone 上验证本机保存、关闭重启、文件选择、分享备份、恢复、键盘和大字体。
- 已接入系统录音/最终转录与权限、超时、来电/后台中断；这些平台行为需 iPhone 实测。当前不保存录音，不提供疑点回听；参考文本不补全漏背内容。
- 用真实中文语音校准评分。同音字容错和专业发音评分要分别验证。
- 完成隐私政策、应用图标、签名、崩溃恢复、VoiceOver 和长期数据迁移。
- Apple 登录及云同步可后续增加；当前本机保存不要求个人账户，卸载前须导出档案。

本机源码分析和组件测试不能替代 iOS 构建、平台插件测试及真机验收。

## 历史版本 0.2.0 验证

当时代码版本为 0.2.0+2。最终 GitHub CI 的 42 项核心测试、11 项 Flutter 测试及静态分析通过。语音测试使用受控识别适配器验证临时转录不打卡、只用最终结果、自动结束、拒绝权限和中断。16 个主要页面检查 390/320 宽度与 1.5 倍字体；截图来自 Flutter 测试渲染，不是 iPhone 真机。新 IPA 必须来自本次提交对应的成功 Actions，旧构建不能代表新增语音功能。

最终应用提交 fa929a2 的 [Actions 构建 37762456398](https://github.com/iszkq/recitation-plan/actions/runs/37762456398) 全部成功。
[下载新版未签名 IPA 产物](https://github.com/iszkq/recitation-plan/actions/runs/37762456398/artifacts/11542838665)，版本 0.2.0+2，SHA-256 为 a1fecd28a431e64c4ba259b2e2e4111d9cc14f303d63a0bd3126115a481c5a05。
本次之后若仅更新截图、文档和验收记录，不重复构建 IPA；应用代码变化时再构建。

## 历史版本 0.2.3+5

支持单项/批量自选日期延期、撤销与工作量确认，自动通过后的提前完成及下次复习提示，iPhone 本地学习/每周备份提醒。提醒默认关闭，从“我的→提醒设置”开启；只在开启时申请系统权限。

真实设备覆盖升级、通知和分享见 [真机验收步骤](真机覆盖升级验收.md)，自动验证与发布记录见 [延期撤销与提醒验收](延期撤销与提醒验收.md)。[下载0.2.3+5未签名IPA](https://github.com/iszkq/recitation-plan/actions/runs/37894173505/artifacts/11599442782)。[Actions 37894173505](https://github.com/iszkq/recitation-plan/actions/runs/37894173505) 的60项核心测试、27项Flutter测试和macOS iOS Release编译通过。SHA-256：`b3ed44ec3e310a19af339b06c581890a4fc9cff4c1e31741cfd16a923aa3d232`。

## 0.2.4+6 已验证

新增计划月历、剩余新背重新排期、积压复习分日处理和本机快照恢复。沿用 Bundle ID `cn.recitation.recitationApp`，iOS 15+，保持原安装身份覆盖升级。[Actions 37899285227](https://github.com/iszkq/recitation-plan/actions/runs/37899285227)通过73项核心、33项Flutter及iOS Release。[未签名IPA](https://github.com/iszkq/recitation-plan/actions/runs/37899285227/artifacts/11601479488)，SHA-256：`77be010ea312270fa7166a01de82da545bc340dc2cf1f2e5a2d47bf6f985a4a9`。

## 0.2.5+7 构建中

新增文字/语音逐字高亮校对、语音同音容错及校正内容展示、连续学习与学习花园。成熟方案取舍、测试及最终构建记录见 [语音校对方案与成长验收](语音校对方案与成长验收.md)。仍保留原Bundle ID与签名升级要求，未签名包需签名后安装。
