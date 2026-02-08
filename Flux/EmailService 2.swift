// EmailService.swift
import Foundation

final class EmailService {
    struct Config {
        let apiKey: String
        let senderEmail: String
    }

    func currentConfig() -> Config? {
        let d = UserDefaults.standard
        guard let apiKey = d.string(forKey: "SENDGRID_API_KEY"), !apiKey.isEmpty,
              let sender = d.string(forKey: "SENDGRID_SENDER_EMAIL"), !sender.isEmpty else { return nil }
        return .init(apiKey: apiKey, senderEmail: sender)
    }

    func sendHTMLNewsletter(to recipient: String, subject: String, html: String, heroImageData: Data?) async throws {
        guard let cfg = currentConfig() else {
            throw NSError(domain: "Email", code: -1, userInfo: [NSLocalizedDescriptionKey: "Configuration d’envoi e‑mail manquante (SendGrid)"])
        }
        var body: [String: Any] = [
            "personalizations": [["to": [["email": recipient]]]],
            "from": ["email": cfg.senderEmail],
            "subject": subject,
            "content": [["type": "text/html", "value": html]]
        ]
        if let data = heroImageData {
            let b64 = data.base64EncodedString()
            body["attachments"] = [[
                "content": b64,
                "filename": "hero.png",
                "type": "image/png",
                "disposition": "inline",
                "content_id": "hero"
            ]]
        }

        var req = URLRequest(url: URL(string: "https://api.sendgrid.com/v3/mail/send")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "Email", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "SendGrid: échec de l’envoi"])
        }
    }
}


