import Cocoa

let cases: [(String, [String], String)] = [
    ("system", ["zh-TW"], "zh-Hant"), ("system", ["zh-HK"], "zh-Hant"),
    ("system", ["zh-CN"], "zh-Hans"), ("zh-Hans-HK", [], "zh-Hans"),
    ("zh-Hant-CN", [], "zh-Hant"), ("system", ["pl-PL", "de-DE"], "de"),
    ("system", ["xx"], "en"), ("system", [], "en"), ("it", ["en"], "it"),
    ("bad-setting", ["zh-CN"], "en"), ("no-NO", [], "nb"), ("nn-NO", [], "nb"),
    ("sv_SE", [], "sv"), ("vi-VN", [], "vi"), ("ko-KR", [], "ko"), ("ja-JP", [], "ja"), ("pt-BR", [], "pt-BR"), ("system", ["pt-BR"], "pt-BR"),
    ("pt_PT", [], "pt-BR"), ("uk-UA", [], "uk"), ("sw-TZ", [], "sw")
]
for (preference, system, expected) in cases {
    assert(BentoLanguage.resolve(preference, preferred: system) == expected, preference)
}
assert(Set(allSkins.map { $0.id }).count == 15)
assert(skin(withID: "old-invalid-skin").id == "system")
assert(skin(withID: "matcha").id == "matcha")
assert(skin(withID: "midnight").appearanceName == .darkAqua)
assert(skin(withID: "lavender").appearanceName == .aqua)
for (language, _) in BentoLanguage.choices where language != "system" {
    assert(BentoLanguage.bundles[language] != nil, "Missing packaged resource: \(language)")
    UserDefaults.standard.setVolatileDomain(["languageID": language], forName: UserDefaults.argumentDomain)
    assert(L("语言") == BentoLanguage.text("语言", language: language))
    assert(!skin(withID: "aurora").name.isEmpty)
    let value = "file %@ \\name 日本語"
    assert(L("显示器 %@", value).contains(value), "User input is a format argument, never a format string")
    let pair = L("已更新 %@ / %@ 个文件夹", "17", "23")
    assert(pair.contains("17") && pair.contains("23"))
    if language != "zh-Hans" && language != "zh-Hant" { assert(L("文件夹着色") != "文件夹着色", language) }
}
print("Presentation checks passed: language resolution, all bundled languages, runtime switching, format safety, 15 stable skin IDs")

let lightSurfaces = Set(allSkins.filter { $0.accent != nil }.map { $0.palette(dark: false).surface.description })
let darkSurfaces = Set(allSkins.filter { $0.accent != nil }.map { $0.palette(dark: true).surface.description })
assert(lightSurfaces.count == 12 && darkSurfaces.count == 12, "Color skins have distinct backgrounds, not only text colors")
assert(skin(withID: "sand").palette(dark: false).radius != skin(withID: "aurora").palette(dark: false).radius)
for skin in allSkins {
    for dark in [false, true] {
        let colors = skin.palette(dark: dark)
        assert(colors.surface.alphaComponent == 1 && colors.card.alphaComponent == 1 && colors.selection.alphaComponent == 1)
        assert(colors.surface != colors.card, "Cards remain distinct from their panel")
    }
}
print("Skin surface checks passed: distinct opaque backgrounds, cards, borders, selection and corner styles")
