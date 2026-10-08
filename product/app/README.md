# 背诵计划 App

Flutter 3.47.6 / Dart 3.13.5，iOS 15 起。中文 Cupertino 页面，默认无需账户，学习数据写入应用文档目录下的 Hive 档案。

安装指定 Flutter 版本后，在本目录运行：

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

已在 Windows 使用引擎内置 `dart analyze` 验证静态分析、使用 `flutter test` 验证页面流程。Windows 中文路径可能导致 Flutter 测试进程或分析服务异常，可使用英文目录的工作副本或路径别名。

测试使用内存仓库验证导入保存、计划生成、今日任务刷新、阅读隐藏、评分完成和窄屏大字体；Hive 的重新打开、备份及幂等更新在 `../core/test` 验证。

正式启动入口使用 Hive。`web` 工程是工具生成的脚手架，当前含 `dart:io` 的本机实现不支持 Web 发布。

语音识别、发音评测、登录和云同步没有实现。系统文本选择、备份分享、恢复及 iOS 生命周期需真机验证。尚未配置 Apple 签名，不包含可安装 IPA。

构建和安装步骤见 `../../docs/GitHub构建与安装.md`。
