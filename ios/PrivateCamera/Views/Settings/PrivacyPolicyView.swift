import SwiftUI

/// プライバシーポリシー画面
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("プライバシーポリシー")
                        .font(.system(size: 28, weight: .bold))
                    Text("最終更新日: 2026年3月12日")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                sectionBlock(title: "はじめに") {
                    "無音カメラ・位置情報削除 - Kesu Camera（以下「本アプリ」）は、利用者のプライバシーを最優先に設計されています。本プライバシーポリシーは、本アプリにおける情報の取り扱いについて説明するものです。"
                }

                // 核心メッセージ
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(AppTheme.accentGreen)
                        Text("基本方針")
                            .font(.system(size: 18, weight: .bold))
                    }

                    policyHighlight(icon: "icloud.slash", text: "外部サーバーへのデータ送信は一切行いません")
                    policyHighlight(icon: "wifi.slash", text: "本アプリはオフラインで完全に動作します")
                    policyHighlight(icon: "person.slash", text: "アカウント登録・ログインは不要です")
                    policyHighlight(icon: "chart.bar.xaxis", text: "利用状況の分析・トラッキングは行いません")
                    policyHighlight(icon: "megaphone.slash", text: "広告は表示しません")
                }
                .padding(16)
                .background(AppTheme.accentGreen.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                sectionBlock(title: "1. 収集する情報") {
                    "本アプリは、利用者の個人情報を収集しません。\n\n撮影した写真・ビデオ、パスコード、アプリの設定情報はすべて端末内にのみ保存され、外部に送信されることはありません。"
                }

                sectionBlock(title: "2. カメラ・マイクの使用") {
                    "本アプリは写真・ビデオの撮影のためにカメラとマイクへのアクセスを要求します。これらはアプリ内での撮影目的にのみ使用され、映像・音声データが外部に送信されることはありません。"
                }

                sectionBlock(title: "3. 位置情報の使用") {
                    "本アプリは位置情報へのアクセスを要求する場合があります。これは写真のEXIFデータに位置情報を含めるか選択するためです。位置情報は端末内でのみ処理され、外部に送信されることはありません。デフォルトでは位置情報は自動削除されます。"
                }

                sectionBlock(title: "4. Face ID / Touch ID") {
                    "本アプリは鍵付きアルバムの認証のためにFace ID / Touch IDを使用します。生体認証データはiOSのSecure Enclaveで処理され、本アプリがアクセスすることはできません。"
                }

                sectionBlock(title: "5. データの保存場所") {
                    "すべてのデータは端末のアプリ専用領域に保存されます。\n\n・写真・ビデオ: アプリ内部ストレージ（暗号化対応）\n・パスコード: Keychain（iOS標準のセキュア領域）\n・設定情報: UserDefaults（アプリ内）\n\nこれらのデータは他のアプリからアクセスすることはできません。"
                }

                sectionBlock(title: "6. データの削除") {
                    "利用者はアプリ内からいつでも写真・ビデオを削除できます。アプリ自体を削除すると、保存されたすべてのデータ（写真・ビデオ・設定）が完全に削除されます。Keychainに保存されたパスコードはアプリ削除後も端末に残る場合があります。"
                }

                sectionBlock(title: "7. 第三者への提供") {
                    "本アプリは利用者のデータを第三者に提供、販売、共有することはありません。第三者のSDK、分析ツール、広告ネットワークは一切使用していません。"
                }

                sectionBlock(title: "8. 子どものプライバシー") {
                    "本アプリは年齢制限なく利用可能ですが、個人情報を一切収集しないため、児童オンラインプライバシー保護法(COPPA)等の対象となる情報収集は行っていません。"
                }

                sectionBlock(title: "9. ポリシーの変更") {
                    "本ポリシーは必要に応じて更新される場合があります。重要な変更がある場合は、アプリのアップデート時にお知らせします。"
                }

                sectionBlock(title: "10. お問い合わせ") {
                    "本ポリシーに関するご質問がある場合は、App Storeのアプリページからお問い合わせください。"
                }
            }
            .padding(20)
        }
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionBlock(title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
            Text(content())
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }

    private func policyHighlight(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.accentGreen)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 14, weight: .medium))
        }
    }
}
