import FirebaseCore
import Foundation

/// Démarrage de Firebase.
///
/// Firebase n'est démarré que si le fichier `GoogleService-Info.plist` est présent dans l'app
/// (ajouté par la compilation sur GitHub à partir d'un secret). Sinon, ou si l'argument de
/// lancement `-tribu.demo YES` est passé, l'app tourne avec les données d'exemple.
enum Backend {
    private(set) static var isConfigured = false

    static var demoRequested: Bool {
        UserDefaults.standard.bool(forKey: "tribu.demo")
    }

    static func configureIfPossible() {
        guard !demoRequested, !isConfigured else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        isConfigured = true
    }
}
