# PlainTranslate — Logo Kit

已選定的 A 方案：P 的透明留白藏著 T，分別呼應 Plain 與 Translate。
所有符號及英文字標均為原創向量輪廓，不需要安裝或購買字型。

| 目錄 | 用途 |
| --- | --- |
| `masters/` | 可編輯 SVG：符號、反白、小尺寸、字標、橫排、直排及 App 圖示 |
| `svg/` | 黑色、白色及品牌單色版本 |
| `png/` | 透明底 PNG，包含大尺寸字標及圖示 |
| `app/` | 16–1024px App 圖示、macOS ICNS、18pt 選單列 template 圖示 |
| `web/` | favicon、ICO、Apple touch icon、PWA 圖示、manifest 及 HTML 範例 |
| `print/` | 保持向量的 RGB PDF，印刷前另作色彩打樣 |
| `presentation/` | 配色及應用示意，附 HTML 和 PNG |
| `checks/` | SVG 檢查及交付驗證結果 |

詳見 [一頁使用指南](GUIDELINES.md) 及 [色彩數值](palette.json)。

## 開發者

App 使用的 `Resources/Brand/AppIcon.png` 應與
`app/PlainTranslate-1024.png` 完全一致。`Tools/MakeIcon.swift` 使用 macOS
CoreGraphics／ImageIO 將這個已提交的 PNG 製成各尺寸 ICNS，因此一般建置不需
SVG renderer、字型、網絡連線或任何外部技能檔案。

編輯向量後，可使用開源 librsvg 的 `rsvg-convert` 重新輸出 PNG，例如：

```sh
rsvg-convert -w 1024 -h 1024 masters/plaintranslate-app-icon.svg -o app/PlainTranslate-1024.png
rsvg-convert -w 18 -h 18 masters/plaintranslate-menu-template.svg -o app/BrandMarkTemplate.png
rsvg-convert -w 36 -h 36 masters/plaintranslate-menu-template.svg -o app/BrandMarkTemplate@2x.png
```

再同步 App 的三個 `Resources/Brand/` 檔案，執行 `./build.sh --test` 及
`./build.sh`。`web/head-snippet.html` 假設圖示置於網站根目錄；請按實際路徑調整。
此套件不會建立或部署網站。

## 授權與交付範圍

Copyright © 2026 PlainTranslate contributors. 原創圖形及自繪字標按
**GPL-3.0-or-later** 提供，完整條款見 `LICENSE.txt`。
SVG master 沒有外部字型、點陣圖、濾鏡或假白色挖空；T 為真正透明留白。
App tile 上的白色符號則是刻意的白色圖形。

已做數碼尺寸、黑白、反白、透明度及色彩對比檢查。這不等於商標權利審查；公開品牌
使用前如需法律確定性，應另做專業商標及相似圖像查核。CMYK 為未套印刷色彩描述檔
的近似值，未指定或驗證 Pantone 色票。PDF 是 RGB 向量原稿，並非已打樣的 CMYK 印刷稿。

## 檢查結果補充

- P 符號的垂直偏移是平衡上方圓弧的光學調整。
- App tile 的白色 P 是刻意的白色圖形，T 才是透明留白。
- 直排字標只用於160px寬以上；16–32px使用獨立小尺寸符號，避免 i 的圓點消失。
- 已以原始 sRGB 像素核對色值，避免 AppKit 額外轉色影響數值檢查。
- macOS Dock／選單列、README、網站、瀏覽器分頁及社群版面均為應用示意，並非已發布的網站或帳戶。
