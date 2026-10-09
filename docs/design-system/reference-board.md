# 参考与取舍

| 来源 | 角色 | 借鉴 | 不直接采用 |
|---|---|---|---|
| 用户选择：纯白简洁、系统 iOS | 视觉约束 | 大标题、克制蓝色、清晰列表 | 纸纹、深色沉浸 |
| Apple HIG（通用原生原则） | 平台规则 | 安全区、44pt 触控、层级导航、动态字号 | 机械复制系统应用内容 |
| Remember Me 官网和已拉取源码 | 业务参考 | 文本练习、复习到期、录音回听、导入 | 经卷检索、宗教内容库、原版 Material 外观 |
| MemorizeMe 作者教程 | 语音流程参考 | 原文编辑、无原文背诵、停止后评分 | 英语空格分词与同位置比较 |
| Apple Speech 官方文档 | 技术参考 | 临时/最终转录状态 | 把识别置信度直接当背诵正确率 |

来源链接：
- https://www.remem.me/
- https://gitlab.com/remem-me/app
- https://developer.apple.com/design/human-interface-guidelines/
- https://swiftandcurious.com/2025/12/01/memorizeme/
- https://developer.apple.com/documentation/speech

离线设计知识检索覆盖了单列任务流、低动态与可读性。语料更偏营销网页，粒子、玻璃、拖拽焦点等结果与本产品冲突，全部拒绝。以用户明确风格、原生规范和阅读任务为主，未将检索到的营销模板套入 App。

## 自选日期与提醒

0.2.3 延用系统 iOS 日期/时间滚轮、取消/确定底部面板和开关，不新增装饰色。Flutter 测试引擎截图：output/native-ui/postpone-custom-390.png、postpone-history-390.png、reminder-settings-390.png；320pt 截图检验大字体，不代表 iPhone 真机。
