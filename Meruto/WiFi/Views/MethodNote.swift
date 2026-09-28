import SwiftUI

struct MethodNote: View {
    var body: some View {
        Panel(title: "How it works", icon: "info.circle", tint: Theme.faint) {
            Text(
                "iOSは他のアプリにWi-Fiの電波強度（RSSI/dBm）を公開していません。Merutoは代わりにWi-Fiルーターへ毎秒約6回の応答確認（ICMP）を送り、応答時間・ばらつき・欠落率からリンク品質（0〜100）を実測します。電波が弱い場所ほど再送が増えて応答が遅く不安定になるため、場所ごとの差がはっきり出ます。大小2種類のパケットの応答時間差から、無線区間の実効レートも推定しています。"
            )
            .font(.system(size: 11))
            .foregroundStyle(Theme.label)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
