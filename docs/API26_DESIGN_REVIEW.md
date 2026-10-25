# API 26 与界面改造研究

目标为 HarmonyOS 7 / API 26，保留原生 ArkTS / ArkUI。参考用户提供的库街区官方截图，先改真实已接入功能，不添加不可用的关注、发布、消息按钮冒充完成。

| 能力 | 接入方案 | 边界 |
| --- | --- | --- |
| 沉浸式系统材质 | API 26 uiMaterial.ImmersiveMaterial；五档厚度 | 支持范围受组件区域、设备和系统设置限制，普通正文按钮未必生效 |
| HDS 悬浮页签 | HdsTabs + barFloatingStyle + hdsMaterial | HDS 等级与 ArkUI 厚度是不同参数 |
| 滚动隐藏页签 | 滚动距离阈值 + HdsTabs barHeight + UIContext.animateTo | 使用已有 ArkUI 能力，不冒称 API 26 首次新增；需实机验证悬浮栏折叠效果 |
| 数据条平滑 | Progress.style 的 enableSmoothEffect | 使用官方组件已有动效，避免手写逐帧定时器 |
| 终端数据更新 | 并行读请求、单次更新、当前数据保留、60秒复用 | 账号或角色变更时清理旧数据；不让视觉平滑掩盖请求失败 |
| 系统主题 | UIAbility.onConfigurationUpdate + setColorMode | 现有能力，跟随系统及显式浅深主题 |
| 安全区 | 原生页面避让系统栏；地图独立全屏 | 不再以全局全屏方式修饰原生页面 |

## 官方文档

- 沉浸光感简介：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-overview
- HDS 组件材质：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material
- Progress（示例5：进度平滑动效）：https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-basic-components-progress
- TabBar 动画与 barHeight：https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1096
- Tabs 数据刷新：https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-arkui-1476
- UIAbility 深浅主题：https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-inner-application-uiabilitycontext

## 评论协议证据

从库街区官方发布的 editor-component（index-MDdLk3nm.js）中核对：文本段落由 contentType、content、children 组成；children 内文本节点为 type=1、content、target。仅此结构证据不能替代真实账号写入验收。

## 尚未接入

官方关注流、原生发帖、消息中心、图片和 GIF 评论、系统推送、桌面卡片、3D 空间效果未纳入本轮。需要业务接口、交互或资产支持后再评估。

## 1.4.0 安全区方案

参考 Huawei 安全区域文档 https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-expand-safe-area ：原生内容保留默认系统避让，仅 AppBackdrop 扩展绘制。首页根部增加同一背景层，避免 HDS Tab 容器外没有背景。地图通过自身根容器扩展系统安全区，移除窗口全屏状态切换，避免影响返回后的页面。键盘区不扩展。

加号使用 SymbolGlyph($r('sys.symbol.plus'))，按钮尺寸44vp，沿用系统符号而非图片图标。没有声称它是 API26 首次新增。

任务切换截图只能辅助定位；没有设备，不能据此宣称前台状态栏、手势区或最近任务动画已完全修复。

## 1.5.0 替换旧安全区方案

上一版仅扩展组件背景未解决用户设备上的边缘色块。本版改为 EntryAbility 统一 setWindowLayoutFullScreen(true)，系统栏透明，使用 getWindowAvoidArea(TYPE_SYSTEM / TYPE_NAVIGATION_INDICATOR / TYPE_CUTOUT) 读取真实尺寸，经 Window.getUIContext().px2vp 换算后由 SafePage 对内容避让。背景独立铺满整个窗口，所有原生页面共用框架；删除全部 expandSafeArea，避免两种布局方案同时生效。

监听 avoidAreaChange，窗口销毁时移除；地图不额外留内容避让，不切换全局窗口布局。配置失败回退非全屏和零手动内边距，避免双重避让。未通过设备验证，不保证 HDS/Navigation/键盘组合的最终视觉行为。

官方参考：
- https://developer.huawei.com/consumer/cn/doc/doccenter-multi-device/bpta-multi-device-window-immersive
- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-window
