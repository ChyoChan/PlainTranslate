// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import SwiftUI

struct ReleaseUpdateSection: View {
    @ObservedObject private var model: ReleaseUpdateService
    @ObservedObject private var l10n = L10n.shared

    init() { model = .shared }
    init(model: ReleaseUpdateService) { self.model = model }

    var body: some View {
        Section {
            LabeledContent(l10n.language.text("Installed version", "目前版本", "当前版本", "インストール済みバージョン")) {
                HStack(spacing: 12) {
                    Text(model.currentVersion).monospacedDigit().foregroundStyle(.primary)
                    Button(l10n.language.text("Check now", "立即檢查", "立即检查", "今すぐ確認")) { Task { await model.check() } }
                        .disabled(model.isChecking)
                        .accessibilityIdentifier("checkPublishedAppRelease")
                    if model.isChecking {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel(l10n.language.text("Checking…", "正在檢查…", "正在检查…", "確認中…"))
                    }
                }
            }
            if let error = model.error {
                Label(errorText(error), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.primary)
                    .accessibilityIdentifier("publishedReleaseError")
            }
            if let release = model.release {
                Label(model.hasNewerVersion ? l10n.language.text("New version available: \(release.tag)", "有新版本：\(release.tag)", "有新版本：\(release.tag)", "新しいバージョン：\(release.tag)") :
                          l10n.language.text("No newer release", "未有較新版本", "没有更新的版本", "新しいリリースはありません"),
                      systemImage: model.hasNewerVersion ? "arrow.down.circle" : "checkmark.circle")
                    .accessibilityIdentifier("publishedReleaseStatus")
                if release.preview { Text(l10n.language.text("Preview release", "預覽版本", "预览版", "プレビュー版")).font(.callout) }
                Link(l10n.language.text("View release and downloads", "查看版本及下載", "查看版本及下载", "リリースとダウンロードを表示"), destination: release.url)
                if !release.notes.isEmpty {
                    DisclosureGroup(l10n.language.text("Release notes", "更新內容", "更新内容", "リリースノート")) {
                        // Render remote notes as selectable text, never executable HTML.
                        Text(verbatim: release.notes).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if model.lastChecked != nil && model.error == nil {
                Text(l10n.language.text("No published releases yet", "暫時沒有已發佈版本", "暂无已发布版本", "公開済みのリリースはありません"))
                    .accessibilityIdentifier("publishedReleaseStatus")
            }
            if let date = model.lastChecked {
                LabeledContent(l10n.language.text("Last successful check", "上次成功檢查", "上次成功检查", "前回の確認")) {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.primary)
                }.font(.callout)
            }
            Link(l10n.language.text("All releases on GitHub", "GitHub 所有版本", "GitHub 所有版本", "GitHub の全リリース"), destination: model.client.releasesURL)
        } header: {
            Text(l10n.language.text("Check for updates", "檢查新版本", "检查更新", "アップデートを確認"))
        } footer: {
            Text(l10n.language.text("Checks GitHub releases, including previews. Download and install updates manually.", "檢查 GitHub 發佈版本，包含預覽版。更新需手動下載及安裝。", "检查 GitHub 发布的版本，包含预览版。更新需手动下载并安装。", "プレビュー版を含む GitHub のリリースを確認します。更新は手動でダウンロードしてインストールしてください。"))
                .font(.callout).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
        }
    }

    private func errorText(_ error: ReleaseCheckError) -> String {
        switch error {
        case .network: return l10n.language.text("Could not reach GitHub. Try again later.", "無法連接 GitHub，請稍後重試。", "无法连接 GitHub，请稍后重试。", "GitHub に接続できませんでした。しばらくしてから再試行してください。")
        case .rateLimited: return l10n.language.text("GitHub's request limit was reached. Try again later.", "已達 GitHub 請求限制，請稍後重試。", "已达 GitHub 请求限制，请稍后重试。", "GitHub のリクエスト上限に達しました。しばらくしてから再試行してください。")
        case .unavailable: return l10n.language.text("The release feed is unavailable. Try again later.", "暫時無法取得發佈版本，請稍後重試。", "暂时无法获取发布版本，请稍后重试。", "リリースを取得できません。しばらくしてから再試行してください。")
        case .invalidResponse: return l10n.language.text("The release information could not be verified.", "無法驗證發佈版本資料。", "无法验证发布版本信息。", "リリース情報を検証できませんでした。")
        }
    }
}
