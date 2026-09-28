# リリース (TestFlight)

## 構成

| 項目 | 値 |
|---|---|
| チーム | `Config/Local.xcconfig` の `DEVELOPMENT_TEAM` |
| アプリ | `com.yama662607.meruto` |
| ウィジェット | `com.yama662607.meruto.widgets` |
| App Group | `group.com.yama662607.meruto` |
| Capability | App Groups (アプリ・ウィジェット)、Access Wi-Fi Information (アプリ) |
| App Store Connect | アプリ「Meruto」(SKU `meruto`、日本語) |
| TestFlight | 内部グループ「Internal」(自動配信、審査なし、ビルドの有効期限 90 日) |

署名は Xcode の自動管理。この Mac の Xcode に Apple ID (Settings > Accounts) が入っていれば、証明書・プロファイル・App ID の Capability は `-allowProvisioningUpdates` で自動的に作られる。

## 手順

```bash
./script/upload-testflight.sh
```

スクリプトが行うこと:

1. `MerutoKit` のテスト (`swift test`)。落ちたら中止。
2. `project.yml` の `CURRENT_PROJECT_VERSION` を +1 (`--build N` で指定も可)。
3. XcodeGen → Release でアーカイブ (`.build/archives/`)。
4. 暗号化の申告 (`ITSAppUsesNonExemptEncryption=false`) とアイコンにアルファが無いことを確認。
5. `xcodebuild -exportArchive` で App Store Connect へアップロード (`script/ExportOptions-upload.plist`)。

アップロード後 5〜15 分で処理が終わり、「Internal」グループへ自動で配信される。更新したビルド番号はコミットする。

新しいバージョン (1.0 → 1.1 など) は `project.yml` の `MARKETING_VERSION` を上げる。

## よくある失敗

| 症状 | 原因と対処 |
|---|---|
| `App record ... not found on App Store Connect` | App Store Connect にアプリの登録が無い。登録済み (2026-09-28) なので、Bundle ID を変えたときだけ起きる |
| アイコンで弾かれる | 1024px アイコンにアルファチャンネルがある。不透明な PNG にする |
| TestFlight で輸出コンプライアンスを聞かれる | Info.plist (アプリ・ウィジェット両方) の `ITSAppUsesNonExemptEncryption` が消えている |
| Capability のエラー | Developer の App ID から App Groups / Access Wi-Fi Information が外れている。`-allowProvisioningUpdates` 付きで再アーカイブすると付け直される |
