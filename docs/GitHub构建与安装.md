# GitHub 构建与安装

## 当前范围

项目已有真实 Flutter 页面和本机数据链路，可以上传 GitHub 验证构建。它是第一版本机文字背诵 App；HTML 仍是设计原型。

本机版包含文本导入、分段调整、计划日期/学习日/配额/通过门槛、全文阅读、无提示文字考核、间隔复习、计划详情和周/月/年报告。考核通过由一致率、覆盖率及规则共同决定，读取原文不会自动打卡。备份使用 JSON 档案，恢复前检查校验和及冲突并保留原档案。

## 上传源代码

使用 `output/背诵计划-设计交付.zip` 中的源文件，解压后保留 `.github` 目录。也可直接上传工作区中 `.github`、`product`、`docs`、`scripts`、`ui`、根 README/AGENTS/.gitignore。

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

开发调试：在有 Xcode 的 Mac 打开 `product/app/ios/Runner.xcworkspace`，为 Runner 选择自己的开发团队并更改唯一 Bundle ID，然后连接 iPhone 运行。个人 Apple ID 的免费开发签名有有效期和设备限制。

长期内测：准备付费 Apple Developer 账户、App Store Connect 应用、唯一 Bundle ID、签名证书和描述文件。在 macOS 配置签名后执行 `flutter build ipa --release`，上传 App Store Connect，再用 TestFlight 安装。GitHub 可以自动做此步骤，但必须先将签名和上传凭据放入仓库 Secrets；项目没有预置这些凭据。

现有 Bundle ID `cn.recitation.recitationApp` 是临时标识，正式提交前应替换为账户可用的唯一标识。

## 发布前待办

- iPhone 上验证本机保存、关闭重启、文件选择、分享备份、恢复、键盘和大字体。
- 接入真实录音/最终转录、权限/来电/后台中断、识别疑点回听；参考文本不得补全漏背内容。
- 用真实中文语音校准评分。同音字容错和专业发音评分要分别验证。
- 完成隐私政策、应用图标、签名、崩溃恢复、VoiceOver 和长期数据迁移。
- Apple 登录及云同步可后续增加；当前本机保存不要求个人账户，卸载前须导出档案。

本机源码分析和组件测试不能替代 iOS 构建、平台插件测试及真机验收。
