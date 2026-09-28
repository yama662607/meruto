import SwiftUI
import WidgetKit

@main
struct MerutoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AIQuotaWidget()
        DeviceWidget()
        WiFiWidget()
    }
}
