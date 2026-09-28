# Meruto

iPhone / iPad の内部状態を計測器のように見せるアプリ。CPU・メモリ・GPU・通信・バッテリー・熱状態・ストレージをリアルタイムに表示し、**Wi-Fi 電波測定器と部屋の電波マップ（ヒートマップ）**、SuperNotch と同じ **AI プロバイダー使用量** を備える。ホーム画面・ロック画面ウィジェット対応。

## 画面

| タブ | 内容 |
|---|---|
| モニター | CPU（全体・コア別 P/E・履歴）、メモリ内訳（App/Wired/圧縮）、GPU（Metal 情報・表示 FPS）、通信（↓↑速度・1.1.1.1 までの ping・IP・5G/LTE）、バッテリー、熱状態、ストレージ、Wi-Fi 概況、AI 使用量カード |
| Wi-Fi | アーチメーター（リンク品質 0–100）、RTT/ジッタ/ロス/推定レート、オシロスコープ、振動で強さを知らせるガイガーモード、**電波マップ**（AR で歩いて自動記録 / 見取り図をタップして記録）、保存済みマップ一覧 |
| AI | SuperNotch の AgentQuota カード（6 プロバイダーの 5h リング + 週次バー、タップで展開）と各プロバイダーの内訳 |
| 設定 | agent-quota の接続先 URL・接続テスト、App Group の状態 |

ウィジェット: **AI 使用量**（small / medium = SuperNotch と同じ 6 連ゲージ / large / ロック画面 3 種、更新ボタン付き）、**デバイスモニター**、**Wi-Fi 電波**（最後のスコア + 最新の電波マップ）。

## Wi-Fi 電波の測り方

iOS は他のアプリに RSSI / dBm を公開していない（`NEHotspotNetwork.signalStrength` は Hotspot Helper 専用で通常は 0）。そこで Meruto は **既定ゲートウェイ（= Wi-Fi ルーター）へ Wi-Fi インターフェイスに束縛した ICMP Echo を毎秒約 6 回**送り、

- RTT の中央値（電波が弱いと PHY レート低下と再送で伸びる）
- ジッタ（連続 RTT 差の平均）
- ロス率
- 大小パケットの RTT 差から推定した無線区間の実効レート

を 0–100 のリンク品質スコアに畳み込む（`MerutoCore/LinkQuality.swift`）。値は dBm ではないが、場所ごとの差ははっきり出る。VPN（Tailscale 等）が既定経路を持っていても `IP_BOUND_IF` で Wi-Fi 区間を測る。

電波マップは ARKit のワールドトラッキングで床面上の位置を追い、0.35m 動くごとにスコアを記録して逆距離加重（IDW）で補間する。測っていない場所は塗らない（測定点から 0.9m まで不透明、2.4m で透明）。最弱 / 最強地点をマーカー表示。

## iOS の制約（正直な注記）

- **GPU 使用率**: iOS は公開していない。Metal のデバイス情報と実際の表示 FPS を出す。
- **温度**: 実測値は取れない。`ProcessInfo.thermalState`（4 段階）を出す。
- **SSID / BSSID**: Access WiFi Information の entitlement と位置情報の許可が必要。無ければ表示しないだけで測定は動く。
- **ウィジェットの更新間隔**: OS の裁量（概ね 15–30 分）。アプリをバックグラウンドへ送るとスナップショットを書いてウィジェットの更新を要求する。

## セットアップ

1. `cp Config/Local.example.xcconfig Config/Local.xcconfig` して、署名チーム ID と agent-quota の URL を書く (このファイルはコミットされない)。
2. `./script/build.sh` で `Meruto.xcodeproj` を生成してビルド (XcodeGen。`project.yml` が正本)。署名は Xcode の自動管理。
3. AI 使用量: Mac で動く agent-quota を tailnet 内に公開する。

   ```bash
   tailscale serve --bg --https=10000 http://127.0.0.1:8765
   ```

   その URL (`https://<mac>.<tailnet>.ts.net:10000`) を `Config/Local.xcconfig` の `AGENT_QUOTA_BASE_URL` に書くと既定の接続先になる (アプリの設定タブでも変更可)。iPhone を同じ tailnet に参加させる。

## 開発

```bash
./script/build.sh                # シミュレータ向けビルド
./script/build.sh --device       # 実機向けに署名なしでコンパイル確認
./script/build.sh --test         # MerutoKit のロジックテスト
./script/upload-testflight.sh    # TestFlight 配信
```

| ドキュメント | 内容 |
|---|---|
| [AGENTS.md](AGENTS.md) | 作業ルール (ブランチ、ビルド経路、設計の原則) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 層構成、フォルダ構成、データの流れ、詳細画面の追加手順、落とし穴 |
| [docs/RELEASE.md](docs/RELEASE.md) | TestFlight 配信の構成と手順 |

データ取得の方針は姉妹アプリ menu-meter（mach / sysctl を直接読む、差分で使用率、仮想 IF を除外）と super-notch（AgentQuota）を踏襲している。

## 商標

AI 使用量の表示に使っている各 AI サービスのロゴ (`Shared/SharedAssets.xcassets/AgentIcons`) は各社の商標で、[lobe-icons](https://github.com/lobehub/lobe-icons) (MIT) 由来の SVG を利用している。
