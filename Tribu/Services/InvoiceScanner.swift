import SwiftUI
import Vision
import VisionKit

/// Ce que la reconnaissance de texte a trouvé sur une facture.
struct InvoiceReading {
    var vendor = ""
    var amount: Double?
    var issueDate: Date?
    var dueDate: Date?
    var iban = ""
    var communication = ""
}

enum InvoiceReader {
    /// Lit le texte de l'image (français) puis cherche montant, dates, IBAN et communication structurée.
    static func read(_ image: UIImage) async -> InvoiceReading {
        guard let cgImage = image.cgImage else { return InvoiceReading() }
        let lines: [String] = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["fr-FR", "nl-NL", "en-US"]
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
        return parse(lines)
    }

    static func parse(_ lines: [String]) -> InvoiceReading {
        var reading = InvoiceReading()
        let text = lines.joined(separator: "\n")

        // Fournisseur : première ligne parlante.
        reading.vendor = lines.first { line in
            let letters = line.filter(\.isLetter).count
            return letters >= 3 && !line.lowercased().contains("facture") && !line.contains("@")
        }?.trimmingCharacters(in: .whitespaces) ?? ""

        // Communication structurée belge : +++123/4567/89012+++ (contrôle modulo 97).
        if let range = text.range(of: #"\+{3}\s?\d{3}\s?/\s?\d{4}\s?/\s?\d{5}\s?\+{3}"#, options: .regularExpression) {
            let digits = text[range].filter(\.isNumber)
            if digits.count == 12, let base = Int(digits.prefix(10)), let check = Int(digits.suffix(2)) {
                let expected = base % 97 == 0 ? 97 : base % 97
                if expected == check {
                    let d = Array(digits)
                    reading.communication = "+++\(String(d[0..<3]))/\(String(d[3..<7]))/\(String(d[7..<12]))+++"
                }
            }
        }

        // IBAN belge.
        if let range = text.range(of: #"BE\s?\d{2}(\s?\d{4}){3}"#, options: .regularExpression) {
            let raw = text[range].filter { $0.isNumber || $0.isLetter }
            reading.iban = stride(from: 0, to: raw.count, by: 4).map { i -> String in
                let start = raw.index(raw.startIndex, offsetBy: i)
                let end = raw.index(start, offsetBy: min(4, raw.count - i))
                return String(raw[start..<end])
            }.joined(separator: " ")
        }

        // Montants : on privilégie les lignes « total », « à payer », « montant ».
        let amountPattern = #"(\d{1,3}(?:[ .]\d{3})*|\d+)[,.](\d{2})\s?(?:€|EUR)?"#
        func amounts(in line: String) -> [Double] {
            guard let regex = try? NSRegularExpression(pattern: amountPattern) else { return [] }
            return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
                guard let r1 = Range(match.range(at: 1), in: line), let r2 = Range(match.range(at: 2), in: line) else { return nil }
                let whole = line[r1].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
                return Double("\(whole).\(line[r2])")
            }
        }
        let keywords = ["à payer", "a payer", "total", "montant", "te betalen", "solde"]
        for (index, line) in lines.enumerated() where keywords.contains(where: { line.lowercased().contains($0) }) {
            let candidates = amounts(in: line) + (index + 1 < lines.count ? amounts(in: lines[index + 1]) : [])
            if let best = candidates.max() { reading.amount = max(reading.amount ?? 0, best) }
        }
        if reading.amount == nil {
            reading.amount = lines.flatMap(amounts).filter { $0 < 100_000 }.max()
        }

        // Dates jj/mm/aaaa : la plus ancienne = émission, celle près de « échéance » = échéance.
        let datePattern = #"(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})"#
        func dates(in line: String) -> [Date] {
            guard let regex = try? NSRegularExpression(pattern: datePattern) else { return [] }
            return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
                guard let d = Range(match.range(at: 1), in: line), let m = Range(match.range(at: 2), in: line),
                      let y = Range(match.range(at: 3), in: line),
                      let day = Int(line[d]), let month = Int(line[m]), var year = Int(line[y]) else { return nil }
                if year < 100 { year += 2000 }
                guard (1...31).contains(day), (1...12).contains(month), (2000...2100).contains(year) else { return nil }
                return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
            }
        }
        for (index, line) in lines.enumerated() where ["échéance", "echeance", "avant le", "payer avant", "vervaldag"].contains(where: { line.lowercased().contains($0) }) {
            reading.dueDate = (dates(in: line) + (index + 1 < lines.count ? dates(in: lines[index + 1]) : [])).first
            if reading.dueDate != nil { break }
        }
        let allDates = lines.flatMap(dates).sorted()
        reading.issueDate = allDates.first { $0 != reading.dueDate }
        return reading
    }
}

/// Scanner de documents d'Apple (détection et recadrage de la feuille).
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 { parent.onScan(scan.imageOfPage(at: 0)) }
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
