import SwiftUI

/// 利用規約画面（免責事項含む）
struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("利用規約")
                        .font(.system(size: 28, weight: .bold))
                    Text("最終更新日: 2026年3月12日")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                sectionBlock(title: "第1条（適用）") {
                    "本利用規約（以下「本規約」）は、無音カメラ・位置情報削除 - Kesu Camera（以下「本アプリ」）の利用に関する条件を定めるものです。本アプリをダウンロードまたは使用した時点で、本規約に同意したものとみなします。"
                }

                sectionBlock(title: "第2条（サービス内容）") {
                    "本アプリは以下の機能を提供します。\n・無音での写真・ビデオ撮影\n・写真の位置情報(GPS)・撮影日時・端末情報の削除\n・アプリ起動時の自動ビデオ録画\n・パスコード・生体認証による写真保護（鍵付きアルバム）"
                }

                sectionBlock(title: "第3条（禁止事項）") {
                    "利用者は、本アプリを以下の目的で使用してはなりません。\n・盗撮その他の違法な撮影行為\n・他者のプライバシーを侵害する行為\n・法令または公序良俗に違反する行為\n・その他、開発者が不適切と判断する行為"
                }

                // 免責事項
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("第4条（免責事項）")
                            .font(.system(size: 18, weight: .bold))
                    }

                    disclaimerItem(
                        icon: "trash.slash",
                        text: "データの消失について",
                        detail: "本アプリ内に保存された画像・動画は、アプリの削除、端末の故障、OSのアップデート、その他予期しない事象により消失する可能性があります。開発者は、いかなる理由によるデータの消失についても一切の責任を負いません。重要なデータは利用者自身の責任でバックアップを行ってください。"
                    )

                    disclaimerItem(
                        icon: "key.slash",
                        text: "パスコードの紛失について",
                        detail: "鍵付きアルバムのパスコードを忘れた場合、保存されたデータへのアクセスを復旧する手段はありません。開発者はパスコードの復旧・リセットサービスを提供しません。"
                    )

                    disclaimerItem(
                        icon: "xmark.shield",
                        text: "メタデータ削除について",
                        detail: "メタデータ削除機能は、一般的なEXIF情報の削除を行いますが、すべてのメタデータが完全に削除されることを保証するものではありません。特殊な形式やアプリ固有のメタデータが残存する可能性があります。"
                    )

                    disclaimerItem(
                        icon: "bolt.slash",
                        text: "動作保証について",
                        detail: "本アプリの動作はすべての端末・OS環境での正常動作を保証するものではありません。開発者は、本アプリの利用により生じた直接的・間接的な損害について一切の責任を負いません。"
                    )
                }
                .padding(16)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                sectionBlock(title: "第5条（知的財産権）") {
                    "本アプリに関する著作権その他の知的財産権は開発者に帰属します。利用者は本アプリを本規約に従って使用する権利のみを有します。"
                }

                sectionBlock(title: "第6条（規約の変更）") {
                    "開発者は、必要と判断した場合、利用者に通知することなく本規約を変更できるものとします。変更後の規約は、本アプリ内に表示された時点で効力を生じるものとします。"
                }

                sectionBlock(title: "第7条（準拠法・管轄）") {
                    "本規約は日本法に準拠し、本規約に関する紛争は東京地方裁判所を第一審の専属的合意管轄裁判所とします。"
                }
            }
            .padding(20)
        }
        .navigationTitle("利用規約")
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

    private func disclaimerItem(icon: String, text: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(detail)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
        .padding(.vertical, 4)
    }
}
