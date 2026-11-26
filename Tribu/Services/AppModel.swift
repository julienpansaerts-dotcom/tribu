import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import Foundation
import Observation
import Security

/// État global : connexion, tribu courante et synchronisation.
@Observable
final class AppModel {
    enum Phase: Equatable {
        case loading
        case demo
        case signedOut
        case needsTribe
        case choosePerson
        case ready
    }

    var phase: Phase
    var errorMessage: String?
    var isBusy = false
    /// Prénom renvoyé par Apple à la première connexion (pour préremplir).
    var suggestedFirstName = ""

    private(set) var store: FamilyStore
    /// Vrai quand la famille d'exemple a été ouverte volontairement (Firebase reste disponible).
    private(set) var isTryingDemo = false
    private(set) var householdId: String?
    private(set) var role: String?
    @ObservationIgnored private var sync: RemoteSync?
    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var currentNonce: String?

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Backend.isConfigured ? Auth.auth().currentUser?.uid : nil }

    init() {
        if Backend.isConfigured {
            store = .empty()
            phase = .loading
            authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
                guard let self else { return }
                guard !self.isTryingDemo else { return }
                Task { @MainActor in await self.handle(user: user) }
            }
        } else {
            store = .sample()
            phase = .demo
        }
    }

    var isParent: Bool { phase == .demo || role == "parent" }

    // MARK: - Connexion avec Apple

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "La connexion avec Apple a échoué : \(error.localizedDescription)"
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorMessage = "Réponse d'Apple incomplète, réessaie."
                return
            }
            if let given = credential.fullName?.givenName, !given.isEmpty { suggestedFirstName = given }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: token,
                rawNonce: nonce,
                fullName: credential.fullName
            )
            isBusy = true
            Task { @MainActor in
                defer { self.isBusy = false }
                do {
                    _ = try await Auth.auth().signIn(with: firebaseCredential)
                } catch {
                    self.errorMessage = "Connexion impossible : \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Famille d'exemple

    /// Ouvre une famille d'exemple, gardée sur l'iPhone uniquement, pour découvrir l'app.
    func enterDemo() {
        sync?.stop()
        sync = nil
        store = .sample()
        isTryingDemo = true
        phase = .demo
    }

    /// Quitte la famille d'exemple et revient à la vraie tribu (ou à l'écran de connexion).
    func exitDemo() {
        isTryingDemo = false
        store = .empty()
        guard Backend.isConfigured else { return }
        phase = .loading
        Task { @MainActor in await self.handle(user: Auth.auth().currentUser) }
    }

    func signOut() {
        if let hid = householdId, let uid, let token = AppDelegate.latestToken {
            db.collection("households").document(hid).collection("members").document(uid)
                .updateData(["fcmTokens": FieldValue.arrayRemove([token])])
        }
        AppDelegate.onToken = nil
        UserDefaults.standard.removeObject(forKey: "tribu.householdId")
        sync?.stop()
        sync = nil
        store.reset()
        householdId = nil
        role = nil
        if Backend.isConfigured { try? Auth.auth().signOut() }
    }

    // MARK: - Chargement de la tribu

    @MainActor
    private func handle(user: User?) async {
        guard let user else {
            sync?.stop()
            sync = nil
            store.reset()
            phase = .signedOut
            return
        }
        phase = .loading
        do {
            let userDoc = try await db.collection("users").document(user.uid).getDocument()
            guard let hid = userDoc.data()?["householdId"] as? String else {
                phase = .needsTribe
                return
            }
            let member = try await db.collection("households").document(hid)
                .collection("members").document(user.uid).getDocument()
            guard member.exists, let data = member.data() else {
                phase = .needsTribe
                return
            }
            await openTribe(hid: hid, uid: user.uid, member: data)
        } catch {
            errorMessage = "Impossible de charger la tribu : \(error.localizedDescription)"
            phase = .needsTribe
        }
    }

    @MainActor
    private func openTribe(hid: String, uid: String, member: [String: Any]) async {
        householdId = hid
        UserDefaults.standard.set(hid, forKey: "tribu.householdId")
        role = member["role"] as? String
        let personId = member["personId"] as? String
        let name = member["displayName"] as? String ?? suggestedFirstName

        let sync = RemoteSync(householdId: hid, uid: uid, authorName: name, store: store)
        sync.onPeopleChange = { [weak self] people in
            guard let self, let me = people.first(where: { $0.linkedUid == uid }) else { return }
            self.store.currentUserId = me.id
            self.sync?.authorName = me.firstName
            UserDefaults.standard.set(me.firstName, forKey: "tribu.authorName")
        }
        self.sync = sync
        store.currentUid = uid
        sync.start()

        // Notifications : on enregistre le jeton de cet iPhone dans la fiche du membre.
        let memberRef = db.collection("households").document(hid).collection("members").document(uid)
        AppDelegate.onToken = { token in
            memberRef.updateData(["fcmTokens": FieldValue.arrayUnion([token])])
        }
        if let token = AppDelegate.latestToken {
            memberRef.updateData(["fcmTokens": FieldValue.arrayUnion([token])]) { _ in }
        }
        NotificationPermission.request()

        if let personId {
            store.currentUserId = personId
            phase = .ready
        } else {
            phase = .choosePerson
        }
    }

    // MARK: - Créer, rejoindre, inviter

    struct PersonDraft: Identifiable {
        let id = UUID().uuidString
        var firstName = ""
        var colorHex: UInt32
        var birthDate: Date?
    }

    func createTribe(name: String, me: PersonDraft, others: [PersonDraft]) {
        guard let uid else { return }
        isBusy = true
        Task { @MainActor in
            defer { self.isBusy = false }
            do {
                let household = db.collection("households").document()
                try await household.setData([
                    "name": name.isEmpty ? "La tribu" : name,
                    "country": "BE",
                    "schoolCalendar": "FWB",
                    "timezone": "Europe/Brussels",
                    "currency": "EUR",
                    "createdBy": uid,
                    "createdAt": FieldValue.serverTimestamp(),
                ])
                let member: [String: Any] = [
                    "role": "parent",
                    "personId": me.id,
                    "displayName": me.firstName,
                    "joinedAt": FieldValue.serverTimestamp(),
                ]
                try await household.collection("members").document(uid).setData(member)

                let batch = db.batch()
                var entries: [(draft: PersonDraft, linked: String?)] = [(draft: me, linked: uid)]
                entries += others.map { (draft: $0, linked: String?.none) }
                for (draft, linked) in entries {
                    guard !draft.firstName.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                    var data: [String: Any] = [
                        "firstName": draft.firstName.trimmingCharacters(in: .whitespaces),
                        "colorHex": Int(draft.colorHex),
                        "allergies": [String](),
                        "notes": [String](),
                        "sizes": [String: Any](),
                        "createdAt": FieldValue.serverTimestamp(),
                    ]
                    if let birthDate = draft.birthDate { data["birthDate"] = Timestamp(date: birthDate) }
                    if let linked { data["linkedUid"] = linked }
                    batch.setData(data, forDocument: household.collection("people").document(draft.id))
                }
                try await batch.commit()
                try await db.collection("users").document(uid).setData(["householdId": household.documentID], merge: true)
                await openTribe(hid: household.documentID, uid: uid, member: member)
            } catch {
                self.errorMessage = "Création impossible : \(error.localizedDescription)"
            }
        }
    }

    func joinTribe(code rawCode: String) {
        guard let uid else { return }
        let code = rawCode.uppercased().filter { $0.isLetter || $0.isNumber }
        isBusy = true
        Task { @MainActor in
            defer { self.isBusy = false }
            do {
                let invite = try await db.collection("invites").document(code).getDocument()
                guard
                    let data = invite.data(),
                    let hid = data["householdId"] as? String,
                    let expires = (data["expiresAt"] as? Timestamp)?.dateValue(),
                    expires > .now
                else {
                    self.errorMessage = "Ce code n'existe pas ou a expiré. Demande un nouveau code."
                    return
                }
                let member: [String: Any] = [
                    "role": data["role"] as? String ?? "parent",
                    "inviteCode": code,
                    "displayName": suggestedFirstName,
                    "joinedAt": FieldValue.serverTimestamp(),
                ]
                try await db.collection("households").document(hid).collection("members").document(uid).setData(member)
                try await db.collection("users").document(uid).setData(["householdId": hid], merge: true)
                await openTribe(hid: hid, uid: uid, member: member)
            } catch {
                self.errorMessage = "Impossible de rejoindre la tribu : \(error.localizedDescription)"
            }
        }
    }

    /// Le membre qui vient de rejoindre indique qui il est dans la famille.
    func choosePerson(_ person: Person?, newFirstName: String, colorHex: UInt32) {
        guard let uid, let hid = householdId else { return }
        Task { @MainActor in
            do {
                let household = db.collection("households").document(hid)
                var personId = person?.id
                var name = person?.firstName ?? newFirstName
                if let person {
                    try await household.collection("people").document(person.id).setData(["linkedUid": uid], merge: true)
                } else {
                    let ref = household.collection("people").document()
                    name = newFirstName.trimmingCharacters(in: .whitespaces)
                    try await ref.setData([
                        "firstName": name,
                        "colorHex": Int(colorHex),
                        "allergies": [String](),
                        "notes": [String](),
                        "sizes": [String: Any](),
                        "linkedUid": uid,
                        "createdAt": FieldValue.serverTimestamp(),
                    ])
                    personId = ref.documentID
                }
                try await household.collection("members").document(uid).updateData([
                    "personId": personId ?? "",
                    "displayName": name,
                ])
                self.store.currentUserId = personId ?? ""
                self.sync?.authorName = name
                self.phase = .ready
            } catch {
                self.errorMessage = "Enregistrement impossible : \(error.localizedDescription)"
            }
        }
    }

    /// Crée un code d'invitation valable 7 jours.
    func createInvite() async -> String? {
        if phase == .demo { return "K7M4QX" }
        guard let uid, let hid = householdId else { return nil }
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let code = String((0..<6).map { _ in alphabet.randomElement()! })
        do {
            try await db.collection("invites").document(code).setData([
                "householdId": hid,
                "role": "parent",
                "createdBy": uid,
                "createdAt": FieldValue.serverTimestamp(),
                "expiresAt": Timestamp(date: Date.now.addingTimeInterval(7 * 24 * 3600)),
            ])
            return code
        } catch {
            errorMessage = "Impossible de créer l'invitation : \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Outils

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
