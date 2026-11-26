import Foundation

/// Un ingrédient découpé : quantité, unité et nom (« 400 g de champignons »).
struct ParsedIngredient: Identifiable, Hashable {
    var id: String { raw }
    var raw: String
    var amount: Double?
    var unit: String
    var name: String

    /// Quantité lisible, ajustée au nombre de portions.
    var quantityText: String? {
        guard let amount else { return unit.isEmpty ? nil : unit }
        let number = IngredientParser.format(amount)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    func scaled(by factor: Double) -> ParsedIngredient {
        var copy = self
        copy.amount = amount.map { $0 * factor }
        return copy
    }
}

enum IngredientParser {
    private static let units: [(pattern: String, unit: String)] = [
        ("kg", "kg"), ("kilos?", "kg"), ("g", "g"), ("gr", "g"), ("grammes?", "g"),
        ("ml", "ml"), ("cl", "cl"), ("dl", "dl"), ("l", "l"), ("litres?", "l"),
        ("c\\.? ?à ?s\\.?", "c. à soupe"), ("cs", "c. à soupe"), ("càs", "c. à soupe"),
        ("cuill(?:e|è)res? à soupe", "c. à soupe"), ("c\\. à soupe", "c. à soupe"),
        ("c\\.? ?à ?c\\.?", "c. à café"), ("cc", "c. à café"), ("càc", "c. à café"),
        ("cuill(?:e|è)res? à café", "c. à café"), ("c\\. à café", "c. à café"),
        ("pincées?", "pincée"), ("gousses?", "gousse"), ("tranches?", "tranche"),
        ("boîtes?", "boîte"), ("sachets?", "sachet"), ("bottes?", "botte"), ("brins?", "brin"),
        ("feuilles?", "feuille"), ("verres?", "verre"), ("tasses?", "tasse"), ("pots?", "pot"),
    ]

    private static let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]

    static func parse(_ line: String) -> ParsedIngredient {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var amount: Double?

        // Quantité : « 2 », « 1,5 », « 1/2 », « ½ », « 1 ½ »
        let numberPattern = #"^(\d+(?:[.,]\d+)?)?\s*(\d+/\d+|[½¼¾⅓⅔])?"#
        if let match = text.range(of: numberPattern, options: .regularExpression), !text[match].isEmpty {
            let token = String(text[match]).trimmingCharacters(in: .whitespaces)
            var total = 0.0
            for part in token.split(separator: " ") {
                if let fraction = part.first.flatMap({ fractions[$0] }), part.count == 1 {
                    total += fraction
                } else if part.contains("/") {
                    let nums = part.split(separator: "/").compactMap { Double($0) }
                    if nums.count == 2, nums[1] != 0 { total += nums[0] / nums[1] }
                } else if let value = Double(part.replacingOccurrences(of: ",", with: ".")) {
                    total += value
                } else {
                    // « 1½ » collé
                    let digits = part.filter(\.isNumber)
                    if let value = Double(digits) { total += value }
                    if let f = part.last.flatMap({ fractions[$0] }) { total += f }
                }
            }
            if total > 0 {
                amount = total
                text = String(text[match.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Unité
        var unit = ""
        for candidate in units {
            let pattern = "^(?i)" + candidate.pattern + "(?=\\s|$|\\.)\\.?\\s*"
            if let match = text.range(of: pattern, options: .regularExpression) {
                unit = candidate.unit
                text = String(text[match.upperBound...])
                break
            }
        }

        // « de », « d' »
        if let match = text.range(of: #"^(?i)(de |d'|d’|des )"#, options: .regularExpression) {
            text = String(text[match.upperBound...])
        }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedIngredient(raw: line, amount: amount, unit: unit, name: name.isEmpty ? line : name.prefix(1).uppercased() + name.dropFirst())
    }

    /// Nom simplifié pour comparer deux articles (« Oignons » = « oignon rouge » non, « oignon » oui).
    static func normalize(_ name: String) -> String {
        var value = name.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_BE"))
        value = value.components(separatedBy: CharacterSet(charactersIn: ",(")).first ?? value
        value = value.trimmingCharacters(in: .whitespaces)
        if value.hasSuffix("s") || value.hasSuffix("x") { value.removeLast() }
        return value
    }

    /// Additionne deux quantités si elles ont la même unité (« 2 » + « 1 » = « 3 »).
    static func merge(_ a: String?, _ b: String?) -> String? {
        guard let a, !a.isEmpty else { return b }
        guard let b, !b.isEmpty else { return a }
        let pa = parse(a + " x"), pb = parse(b + " x")
        if let x = pa.amount, let y = pb.amount, pa.unit == pb.unit {
            let number = format(x + y)
            return pa.unit.isEmpty ? number : "\(number) \(pa.unit)"
        }
        return "\(a) + \(b)"
    }

    static func format(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 { return String(Int(value.rounded())) }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_BE")
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Lit une page de recette et en extrait titre, image, portions, temps, ingrédients et étapes.
///
/// La plupart des sites publient ces informations dans un bloc schema.org « Recipe » (JSON-LD) ;
/// à défaut, on se rabat sur les balises Open Graph (titre et image).
enum RecipeImporter {
    enum ImportError: LocalizedError {
        case badURL, unreadable

        var errorDescription: String? {
            switch self {
            case .badURL: return "Ce lien n'est pas valide."
            case .unreadable: return "Impossible de lire cette page."
            }
        }
    }

    static func importRecipe(from link: String, author: String) async throws -> Recipe {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true else {
            throw ImportError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("fr-BE,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }

        var recipe = Recipe(url: url.absoluteString, title: "", createdByName: author)
        if let node = findRecipeNode(in: html) {
            fill(&recipe, from: node, base: url)
        }
        if recipe.title.isEmpty {
            recipe.title = meta("og:title", in: html) ?? tagContent("title", in: html) ?? url.host() ?? "Recette"
        }
        if recipe.imageURL.isEmpty, let image = meta("og:image", in: html) {
            recipe.imageURL = URL(string: image, relativeTo: url)?.absoluteString ?? image
        }
        recipe.title = decodeEntities(recipe.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return recipe
    }

    // MARK: JSON-LD

    private static func findRecipeNode(in html: String) -> [String: Any]? {
        let pattern = #"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        for match in regex.matches(in: html, range: range) {
            guard let r = Range(match.range(at: 1), in: html) else { continue }
            let json = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let node = searchRecipe(object) { return node }
        }
        return nil
    }

    private static func searchRecipe(_ object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if isRecipe(dict["@type"]) { return dict }
            if let graph = dict["@graph"], let found = searchRecipe(graph) { return found }
            if let main = dict["mainEntity"], let found = searchRecipe(main) { return found }
        } else if let array = object as? [Any] {
            for element in array { if let found = searchRecipe(element) { return found } }
        }
        return nil
    }

    private static func isRecipe(_ type: Any?) -> Bool {
        if let s = type as? String { return s.lowercased() == "recipe" }
        if let list = type as? [String] { return list.contains { $0.lowercased() == "recipe" } }
        return false
    }

    private static func fill(_ recipe: inout Recipe, from node: [String: Any], base: URL) {
        recipe.title = node["name"] as? String ?? ""
        if let image = imageString(node["image"]) {
            recipe.imageURL = URL(string: image, relativeTo: base)?.absoluteString ?? image
        }
        if let yield = node["recipeYield"] {
            let text: String
            if let list = yield as? [Any] { text = list.map { "\($0)" }.joined(separator: " ") } else { text = "\(yield)" }
            if let n = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap({ Int($0) }).first, n > 0, n < 50 {
                recipe.servings = n
            }
        }
        let minutes = duration(node["totalTime"]) ?? {
            let sum = (duration(node["prepTime"]) ?? 0) + (duration(node["cookTime"]) ?? 0)
            return sum > 0 ? sum : nil
        }()
        recipe.totalMinutes = minutes
        recipe.ingredients = (node["recipeIngredient"] as? [Any] ?? node["ingredients"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map { decodeEntities(stripTags($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        recipe.steps = instructions(node["recipeInstructions"])
        if let keywords = node["recipeCategory"] as? String { recipe.tags = [keywords] }
    }

    private static func imageString(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let list = value as? [Any] { return list.lazy.compactMap { imageString($0) }.first }
        if let dict = value as? [String: Any] { return dict["url"] as? String ?? dict["contentUrl"] as? String }
        return nil
    }

    private static func instructions(_ value: Any?) -> [String] {
        if let s = value as? String {
            return stripTags(s).components(separatedBy: CharacterSet.newlines)
                .map { decodeEntities($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let list = value as? [Any] {
            return list.flatMap { element -> [String] in
                if let s = element as? String { return [decodeEntities(stripTags(s))] }
                if let dict = element as? [String: Any] {
                    if let items = dict["itemListElement"] { return instructions(items) }
                    if let text = dict["text"] as? String ?? dict["name"] as? String { return [decodeEntities(stripTags(text))] }
                }
                return []
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        }
        return []
    }

    /// Durée ISO 8601 (« PT1H20M ») en minutes.
    private static func duration(_ value: Any?) -> Int? {
        guard let s = (value as? String)?.uppercased(), s.hasPrefix("P") else { return nil }
        let parts = s.split(separator: "T", maxSplits: 1).map(String.init)
        let datePart = parts.first ?? ""
        let timePart = parts.count > 1 ? parts[1] : ""
        func number(_ suffix: String, in text: String) -> Int {
            guard let r = text.range(of: "(\\d+)" + suffix, options: .regularExpression) else { return 0 }
            return Int(text[r].dropLast()) ?? 0
        }
        let minutes = number("D", in: datePart) * 1440 + number("H", in: timePart) * 60 + number("M", in: timePart)
        return minutes > 0 ? minutes : nil
    }

    // MARK: HTML

    private static func meta(_ property: String, in html: String) -> String? {
        let patterns = [
            #"<meta[^>]+(?:property|name)=["']\#(property)["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']\#(property)["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(match.range(at: 1), in: html) else { continue }
            return decodeEntities(String(html[r]))
        }
        return nil
    }

    private static func tagContent(_ tag: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<\(tag)[^>]*>([^<]+)</\(tag)>", options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    static func decodeEntities(_ s: String) -> String {
        var result = s
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&#039;": "'", "&lt;": "<", "&gt;": ">",
                        "&nbsp;": " ", "&eacute;": "é", "&egrave;": "è", "&ecirc;": "ê", "&agrave;": "à", "&ccedil;": "ç",
                        "&ocirc;": "ô", "&icirc;": "î", "&ucirc;": "û", "&oelig;": "œ", "&rsquo;": "’", "&hellip;": "…"]
        for (key, value) in entities { result = result.replacingOccurrences(of: key, with: value) }
        // Entités numériques « &#233; »
        while let range = result.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let digits = result[range].dropFirst(2).dropLast()
            let replacement = Int(digits).flatMap { UnicodeScalar($0) }.map { String(Character($0)) } ?? ""
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
