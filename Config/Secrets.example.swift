import Foundation

// ⚠️ BU DOSYAYI KOPYALA → "Secrets.swift" olarak kaydet ve gerçek değerleri gir.
// Secrets.swift'i .gitignore'a ekle (repoya gönderme).
//
// Whoop developer.whoop.com → Dashboard → Create App:
//   - Redirect URI olarak aşağıdaki redirectURI'yi ekle (custom scheme).
//   - Xcode → Info → URL Types'a aynı scheme'i ekle (ör. "bearing").
//
// Kişisel kullanımda client_secret'ı uygulamaya gömmek kabul edilebilir; yine de
// mümkünse Keychain'de tut. Bu bir kişisel araç, yayınlanan bir ürün değil.

enum WhoopSecrets {
    static let clientID = "BURAYA_CLIENT_ID"
    static let clientSecret = "BURAYA_CLIENT_SECRET"
    static let redirectURI = "bearing://whoop-callback"
}
