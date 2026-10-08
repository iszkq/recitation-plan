# 背诵计划本机产品核心

`vendor/remember-me`保持上游快照。这里的正式业务代码独立于Flutter页面，已在Windows用Dart运行验证。

## 已实现

- `RecitationService`：导入、计划、最终文字考核、任务完成、首次通过生成复习、写统计事件。
- `HiveRecitationStore`：schema版本1，一次本机批次保存成绩/任务/事件，关闭重开可恢复。
- `BackupService`：结构化导出、SHA-256校验、数量和引用校验、冲突预览、恢复前备份。
- 报告：事件去重、历史首次掌握、真实到期分母、仅自动有效复习考核参与通过比例、当前周期截至日期。

## 复验

工作区根目录运行 `scripts/check-core.ps1`。SDK为`.tools/dart-sdk`，依赖缓存为`.tools/pub-cache`，未改变全局PATH。

在`product/core`目录运行：

```powershell
$env:PUB_CACHE = Join-Path (Get-Location).Path '../../.tools/pub-cache'
& '../../.tools/dart-sdk/bin/dart.exe' --suppress-analytics analyze
& '../../.tools/dart-sdk/bin/dart.exe' --suppress-analytics test
& '../../.tools/dart-sdk/bin/dart.exe' --suppress-analytics run bin/local_demo.dart '../../output/local-verification'
```

本机演示每次建立新内容；复验隔离数据时使用新的输出目录。正式应用在调用服务时使用新会话ID，重复回调沿用同一ID。

## 范围

HTML仍是原型，不连接Hive。Flutter UI 和 iOS 系统语音已接入，麦克风与系统识别需真机验收；账户和云同步待接入。本机导出默认不带录音，也不承诺本地文件或云端加密已实现。恢复接口接受结构化完整档案，对冲突明确拒绝，冲突选择和重映射仍需UI/服务扩展。

当前使用单Hive键JSON快照实现批次一致性，不需要新typeId；每次写入整份快照，适合首版小规模档案。大量录音/多年海量事件需分页存储或事务数据库。一个档案仅有一个写入实例；多进程同步与恢复并发锁仍需后续处理。
