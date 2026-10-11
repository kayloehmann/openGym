import Capacitor

class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        bridge?.registerPluginInstance(PrintPlugin())
        bridge?.registerPluginInstance(AppleHealthPlugin())
    }
}
