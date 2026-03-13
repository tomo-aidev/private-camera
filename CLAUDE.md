# Private Camera - Development Rules

## Critical: Photo Data Persistence

**撮影データは開発中のビルド更新で絶対に消失させないこと。**

### ルール

1. **Bundle ID を変更しない**: `com.privatecamera.app` を変更すると実機上のデータが消失する
2. **Application Support ディレクトリを使用**: `tmp/` や `Caches/` は OS が自動削除する可能性があるため禁止
3. **Xcode で "Clean Build Folder" 後も安全**: ビルド成果物のみ削除され、実機のサンドボックスには影響しない
4. **スキーマバージョニング必須**: `SecureStorage` のデータ構造を変更する場合は `DataPersistenceGuard` にマイグレーションを追加すること
5. **アプリ起動時に `DataPersistenceGuard.verifyOnLaunch()` を必ず呼ぶ**: ディレクトリ存在確認・マイグレーション実行・整合性チェック

### データ保存先

| データ | パス | 永続性 |
|--------|------|--------|
| 写真 (暗号化済み) | `ApplicationSupport/PrivateBox/photos/` | アプリ更新で保持 |
| サムネイル | `ApplicationSupport/PrivateBox/thumbnails/` | アプリ更新で保持 |
| メタデータインデックス | `ApplicationSupport/PrivateBox/metadata.json` | アプリ更新で保持 |
| 暗号化ソルト | Keychain | アプリ削除でも保持 |
| パスコードハッシュ | Keychain | アプリ削除でも保持 |

### やってはいけないこと

- `PRODUCT_BUNDLE_IDENTIFIER` の値を変更する
- `SecureStorage.storageRoot` のパスを変更する
- `metadata.json` のスキーマをマイグレーションなしで変更する
- テスト中に実機の「Appを削除」を行う（データが全消失する）

## Project Structure

- iOS: `ios/` - SwiftUI + AVFoundation (iOS 17+)
- Android: `android/` - Jetpack Compose + CameraX
- UI Reference: `stitch 3/` - HTML/Tailwind mockups (source of truth)

## Build

```bash
# iOS - Xcode project generation
cd ios && xcodegen generate

# iOS - Build
xcodebuild -project PrivateCamera.xcodeproj -scheme PrivateCamera -destination 'platform=iOS,name=jobs iPhone (2)' build
```
