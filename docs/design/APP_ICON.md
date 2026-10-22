# 工作记忆 App 图标

2026-10-22，使用内置 imagegen 生成。用户要求替换手机上显示的全黑图标。

设计：深蓝底色、暖白色记忆卡片、铜橙声波、小星光。无文字，缩小后仍可识别。源文件 `work-memory-icon-source.png`；安装资源在 `app/ios/WorkMemory/Assets.xcassets/AppIcon.appiconset/AppIcon.png`，1024×1024、不透明 RGB PNG。iOS 自行裁切圆角。旧黑图标备份为 `AppIcon-before.png`。

使用 `swift scripts/create_icon.swift <output.png>` 从保留的源图重新导出，避免旧绘制脚本覆盖成黑图。

## 最终生成提示词

Use case: logo-brand. Create a final production iOS app icon for a Chinese personal voice recording and work memory app named 工作记忆. A single square icon, 1024 by 1024 composition, full bleed opaque background, no surrounding presentation or mockup. No typography, no letters, no words. Refined minimal geometric symbol: a large softly sculpted warm ivory memo card with a subtly folded upper-right corner, bearing five thick rounded copper-orange vertical waveform bars of varied heights in its center. Card upright and centered; the bars are the unmistakable visual focus, expressing voice turned into useful memories. A tiny four-point warm copper spark at the upper-right near the card can suggest insights, subordinate to the main waveform. Deep rich navy blue background, visibly blue not black, subtle lighter indigo illumination behind the card, restrained dimensional highlights and soft short shadow; tasteful premium native productivity app aesthetic, uncluttered, precise, strong warm/cool contrast. Large bold mark taking about 65 percent of the square, readable at 48 pixels. Full square canvas all the way to corners; do not draw an outer rounded app tile, no frame, no border, no watermark. No microphone hardware, no brain, no circuitry, no excessive gloss or many details.
