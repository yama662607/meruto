# Project workflow

- リポジトリのディレクトリ名は末尾に空白を含む (`meruto `)。シェルでは必ずパスを引用符で囲む。
- 機能追加は `main` へ直接コミットしない。実装は `feature/<topic>`、修正は `fix/<topic>`、ドキュメントは `docs/<topic>`、雑務は `chore/<topic>` を使う。
- Xcode project の正本は `project.yml`。`Meruto.xcodeproj` は XcodeGen で生成し、手編集もコミットもしない (`.gitignore` 済み)。
- 共通経路:
  - `./script/build.sh` … プロジェクト生成 + シミュレータ向けビルド
  - `./script/build.sh --device` … 実機向けに署名なしでコンパイル確認
  - `./script/build.sh --test` … `MerutoKit` のテスト (`swift test`)
  - `./script/upload-testflight.sh` … TestFlight 配信 (手順は [docs/RELEASE.md](docs/RELEASE.md))
- 変更後は最低限 `./script/build.sh --test` と `./script/build.sh` が通ることを確認する。警告も 0 を保つ。
- 外部依存 (SPM パッケージ) を追加しない。Darwin / Apple フレームワークだけで書く。

## 設計の要点

- 構成・データの流れ・詳細画面の追加手順は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) が正本。構成を変えたら先にここを更新する。
- 層の依存は一方向: `MerutoCore` ← `MerutoProbes` ← `Shared` ← `Meruto` / `MerutoWidgets`。
  - 計算・判定 (スコア、補間、書式、デコード) は `MerutoCore` に置いてテストを書く。View に計算を書かない。
  - OS の値を読むコード (mach / sysctl / getifaddrs / ICMP) は `MerutoProbes` に閉じ込める。
- iOS が公開していない値 (GPU 使用率、温度の実測値、Wi-Fi の RSSI) を推測値で埋めない。代替の指標を出すときは画面で「何を測っているか」を明記する。
- UI 文言は日本語。色は `Theme` のトークンだけを使う。
- AI 使用量カードは姉妹アプリ SuperNotch の AgentQuota モジュールの見た目を移植したもの。寸法・色は SuperNotch 側 (`AgentQuotaView.gaugeColor`) と揃える。残量の色の段階は `MerutoCore` の `QuotaLevel` (0.5% 未満は制限中の紫、5h 枠は残り 10/20/30%、週次は 7 等分で赤・オレンジ・黄・緑)。SuperNotch 側が変わったら追従する。
- データ源は Mac で動く agent-quota (`GET /api/v1/quota`)。API を変えるときは agent-quota の `docs/API.md` を確認する。
- 個人の値 (署名チーム ID、agent-quota の URL、tailnet 名) はコミットしない。`Config/Local.xcconfig` (gitignore 済み) に書き、ビルド設定経由で使う。公開リポジトリなので、コミット前に `git grep` で ts.net・チーム ID・メールアドレスが混ざっていないか確認する。
