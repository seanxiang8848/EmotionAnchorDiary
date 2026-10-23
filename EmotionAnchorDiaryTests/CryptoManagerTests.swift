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

    func testLocalDiarySummaryKeepsAtMostThreeSentences() {
        let text = "第一句。第二句！第三句？第四句。"

        XCTAssertEqual(LocalDiarySummarizer.summarize(text), "第一句。第二句。第三句")
    }

    func testLocalDiarySummaryRespectsCharacterLimit() {
        let text = String(repeating: "心", count: 350)

        XCTAssertEqual(LocalDiarySummarizer.summarize(text).count, 300)
    }

    func testEmotionCoachSendsSummaryAndDecodesResponse() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://ai.example.test/empathy"))
        let payload = Data("""
        {"mood":"被倾听","empathy":"谢谢你写下感受。","suggestions":["深呼吸"]}
        """.utf8)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: endpoint,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))

        let service = EmotionCoachService(
            endpointProvider: { endpoint },
            apiKeyProvider: { "test-key" },
            sendRequest: { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                let body = try XCTUnwrap(request.httpBody)
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                XCTAssertEqual(object["summary"], "仅发送的摘要")
                return (payload, response)
            }
        )

        let card = try await service.fetchEmpathyCard(summary: "仅发送的摘要")

        XCTAssertEqual(card.mood, "被倾听")
        XCTAssertEqual(card.empathy, "谢谢你写下感受。")
        XCTAssertEqual(card.suggestions, ["深呼吸"])
    }

    func testDiaryExportDecryptsFullTextAndSortsEntriesChronologically() throws {
        let crypto = makeCryptoManager()
        let earlierDate = Date(timeIntervalSince1970: 0)
        let laterDate = Date(timeIntervalSince1970: 60)
        let earlierText = "第一条日记的完整正文，保留所有内容。\n还有第二行。"
        let laterText = "第二条日记的完整正文。"
        let entries = [
            DiaryExportEntry(
                createdAt: laterDate,
                moodTag: "焦虑",
                encryptedBody: try crypto.encrypt(laterText)
            ),
            DiaryExportEntry(
                createdAt: earlierDate,
                moodTag: "开心",
                encryptedBody: try crypto.encrypt(earlierText)
            )
        ]

        let exportText = try DiaryExportFormatter.render(entries) {
            try crypto.decrypt($0)
        }

        XCTAssertEqual(
            exportText,
            "1970-01-01T00:00:00Z  心情：开心\n\(earlierText)\n\n---\n\n" +
                "1970-01-01T00:01:00Z  心情：焦虑\n\(laterText)"
        )
    }

    func testDiaryExportFailsWhenEncryptedBodyIsMissing() {
        let entry = DiaryExportEntry(createdAt: Date(), moodTag: nil, encryptedBody: nil)
        let crypto = makeCryptoManager()

        XCTAssertThrowsError(try DiaryExportFormatter.render([entry]) {
            try crypto.decrypt($0)
        })
    }

    private func makeCryptoManager() -> CryptoManager {
        CryptoManager(testKey: SymmetricKey(size: .bits256))
    }
}
