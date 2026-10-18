import CryptoKit
import XCTest
@testable import EmotionAnchorDiary

final class CryptoManagerTests: XCTestCase {

    /// 加密后再解密，必须还原出原文 —— 这是整个隐私方案的根基
    func testEncryptDecryptRoundTrip() throws {
        let crypto = makeCryptoManager()
        let text = "今天有点焦虑，但还是坚持完成了工作。"
        let cipher = try crypto.encrypt(text)
        let plain = try crypto.decrypt(cipher)
        XCTAssertEqual(plain, text)
    }

    /// 密文不允许包含可读的明文内容
    func testCipherTextDoesNotContainPlainText() throws {
        let crypto = makeCryptoManager()
        let text = "秘密心情"
        let cipher = try crypto.encrypt(text)
        let cipherString = String(decoding: cipher, as: UTF8.self)
        XCTAssertFalse(cipherString.contains(text))
    }

    /// 两次加密同一段文字，密文应当不同（AES.GCM 每次使用随机 nonce）
    func testEncryptionUsesRandomNonce() throws {
        let crypto = makeCryptoManager()
        let text = "同一段文字"
        let cipher1 = try crypto.encrypt(text)
        let cipher2 = try crypto.encrypt(text)
        XCTAssertNotEqual(cipher1, cipher2)
    }

    private func makeCryptoManager() -> CryptoManager {
        CryptoManager(testKey: SymmetricKey(size: .bits256))
    }
}
