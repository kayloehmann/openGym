import Capacitor
import SwiftUI

@objc(NativeWorkoutPlugin)
public final class NativeWorkoutPlugin: CAPPlugin {
    private weak var host: UIViewController?
    private var model: NativeWorkoutViewModel?

    @objc func present(_ call: CAPPluginCall) {
        guard let context = call.getObject("context"), let decoded = NativeWorkoutContext.decode(context) else {
            call.reject("Invalid workout context")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { call.reject("Workout controller unavailable"); return }
            if let model = self.model {
                model.apply(decoded)
                call.resolve()
                return
            }
            let model = NativeWorkoutViewModel(context: decoded) { [weak self] event in
                self?.notifyListeners("nativeWorkoutEvent", data: ["event": event], retainUntilConsumed: true)
            }
            let controller = UIHostingController(rootView: NativeWorkoutView(model: model) { [weak self] in
                self?.close(notify: true)
            })
            controller.modalPresentationStyle = .fullScreen
            self.model = model
            self.host = controller
            self.bridge?.viewController?.present(controller, animated: true) { call.resolve() }
        }
    }

    @objc func update(_ call: CAPPluginCall) {
        guard let context = call.getObject("context"), let decoded = NativeWorkoutContext.decode(context) else {
            call.reject("Invalid workout context")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { call.reject("Workout controller unavailable"); return }
            self.model?.apply(decoded)
            if decoded.state != "active" { self.close(notify: true) }
            call.resolve()
        }
    }

    @objc func dismiss(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in self?.close(notify: true); call.resolve() }
    }

    private func close(notify: Bool) {
        host?.dismiss(animated: true)
        host = nil
        model = nil
        if notify {
            notifyListeners("nativeWorkoutEvent", data: ["event": ["type": "dismiss"]])
        }
    }
}
