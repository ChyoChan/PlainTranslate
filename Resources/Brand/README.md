# PlainTranslate artwork

`AppIcon.png` is the 1024-pixel master used by `Tools/MakeIcon.swift`.
`BrandMarkTemplate.png` and `BrandMarkTemplate@2x.png` are the menu-bar marks.
The editable, self-contained SVG masters are in [Source](Source/).

Normal builds use the committed PNG files and do not need an SVG renderer.
After editing the SVG artwork, regenerate the corresponding PNG files before
running `./build.sh --test` and `./build.sh` from the repository root.

README logo variants are in `docs/assets/readme/`. Original artwork is licensed
under GPL-3.0-or-later; see the repository LICENSE and NOTICE.md.
