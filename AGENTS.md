# 项目协作说明

本工作区用于中文文本背诵应用的产品设计、原型与 Remember Me 二次开发。用户已选择纯白、简洁的系统 iOS 风格。主应用底座为 Flutter，当前 HTML 是设计原型，不代表已经实现录音、识别或上线应用。

## Design System Guard

界面设计以以下文件为准。调整视觉前先阅读它们；新增颜色、组件和布局模式须同步更新设计契约。

- `docs/design-system/manifest.json`
- `docs/design-system/design-system.md`
- `docs/design-system/reference-board.md`
- `docs/design-system/component-map.md`
- `docs/design-system/tokens.css`

## 实现约束

- 所有面向用户的文字使用简体中文；专业实现名仅出现在开发文档。
- `vendor/remember-me` 是原样拉取的上游快照，先保持不改动。复用代码须保留 MIT 声明。
- 考核不能用原文补全未说出的内容。临时转录不生成通过记录；人工修订不能伪装成自动通过。
- 学习练习、无提示考核、待人工复核、自动通过分别记账。
- Windows 可以设计和审查代码；iOS 构建、签名和真实设备验证需要 macOS/Xcode。
