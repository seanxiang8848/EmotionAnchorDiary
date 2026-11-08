import CryptoKit
import Foundation
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

    // MARK: - AI 直连（OpenAI 兼容协议）

    private let endpoint = URL(string: "https://api.deepseek.com/v1/chat/completions")!

    private func makeConfig(baseURL: String = "https://api.deepseek.com/v1") -> APIConfig {
        APIConfig.validated(provider: .deepseek, baseURLString: baseURL, model: "deepseek-chat")!
    }

    private func makeService(
        config: APIConfig? = nil,
        key: String? = "test-key",
        handler: @escaping (URLRequest) async throws -> (Data, URLResponse)
    ) -> DiaryAIService {
        DiaryAIService(
            configProvider: { config ?? self.makeConfig() },
            apiKeyProvider: { key },
            sendRequest: handler
        )
    }

    private func chatResponse(content: String, url: URL) -> (Data, URLResponse) {
        let choice: [String: Any] = [
            "message": ["role": "assistant", "content": content],
            "finish_reason": "stop"
        ]
        let envelope: [String: Any] = ["choices": [choice]]
        let data = (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data()
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }

    private func analysisContent(goalID: UUID) -> String {
        """
        {"emotion":{"label":"开心","score":4,"intensity":0.7,"reason":"散步后身体松下来"},"empathy":"今天你出门走了走，身子松了一点。","suggestions":["趁状态好再走十分钟"],"goal_matches":[{"goal_id":"\(goalID.uuidString)","confidence":0.9,"evidence":"散步了三十分钟"}],"goal_updates":[],"new_goals":[]}
        """
    }

    func testAIServiceSendsOpenAICompatibleRequest() async throws {
        let goalID = UUID()
        var captured: URLRequest?
        let service = makeService { request in
            captured = request
            return self.chatResponse(content: self.analysisContent(goalID: goalID), url: request.url ?? self.endpoint)
        }

        _ = try await service.analyze(
            summary: "今天散步了三十分钟",
            moodTag: "平静",
            recentMoods: ["焦虑"],
            goals: [
                GoalContext(
                    id: goalID,
                    title: "每天散步",
                    keywords: ["散步"],
                    periodDays: 7,
                    targetDays: 3,
                    completedDays: 2
                )
            ]
        )

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 45)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "deepseek-chat")
        XCTAssertEqual(object["stream"] as? Bool, false)
        XCTAssertEqual((object["response_format"] as? [String: Any])?["type"] as? String, "json_object")

        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        let userContent = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(userContent.contains("今天散步了三十分钟"))
        XCTAssertTrue(userContent.contains(goalID.uuidString))
        XCTAssertTrue(userContent.contains("\"mood_tag\":\"平静\""))
    }

    func testAIServiceDecodesStructuredAnalysis() async throws {
        let goalID = UUID()
        let service = makeService { request in
            self.chatResponse(content: self.analysisContent(goalID: goalID), url: request.url ?? self.endpoint)
        }

        let result = try await service.analyze(
            summary: "今天散步了三十分钟，心情不错",
            moodTag: "平静",
            recentMoods: [],
            goals: []
        )

        XCTAssertEqual(result.emotion.label, "开心")
        XCTAssertEqual(result.emotion.score, 4, accuracy: 0.001)
        XCTAssertEqual(result.emotion.intensity, 0.7, accuracy: 0.001)
        XCTAssertEqual(result.empathy, "今天你出门走了走，身子松了一点。")
        XCTAssertEqual(result.suggestions, ["趁状态好再走十分钟"])
        XCTAssertEqual(result.goalMatches.count, 1)
        XCTAssertEqual(result.goalMatches.first?.goalID, goalID)
        XCTAssertEqual(result.goalMatches.first?.evidence, "散步了三十分钟")
    }

    /// 容忍代码块包裹、情绪标签不在词表内、数字写成字符串
    func testAIServiceToleratesFenceAndLooseFields() async throws {
        let content = """
        ```json
        {"emotion":{"label":"有点焦虑","score":"2","intensity":"0.6","reason":"明天要汇报"},"empathy":"明天那场汇报悬在心上。","suggestions":"深呼吸\\n把要点写下来","goal_matches":[],"goal_updates":[],"new_goals":[{"title":"准备汇报","keywords":["汇报","PPT"],"period_days":"3","target_days":"2","confidence":"0.8","reason":"明确说要准备"}]}
        ```
        """
        let service = makeService { request in
            self.chatResponse(content: content, url: request.url ?? self.endpoint)
        }

        let result = try await service.analyze(summary: "明天要汇报", moodTag: "平静", recentMoods: [], goals: [])

        XCTAssertEqual(result.emotion.label, "焦虑")
        XCTAssertEqual(result.emotion.score, 2, accuracy: 0.001)
        XCTAssertEqual(result.suggestions, ["深呼吸", "把要点写下来"])
        XCTAssertEqual(result.newGoals.count, 1)
        XCTAssertEqual(result.newGoals.first?.title, "准备汇报")
        XCTAssertEqual(result.newGoals.first?.periodDays, 3)
        XCTAssertEqual(result.newGoals.first?.targetDays, 2)
    }

    func testAIRequiresAPIKeyBeforeSendingRequest() async {
        var requestWasSent = false
        let service = makeService(key: nil) { _ in
            requestWasSent = true
            throw URLError(.userAuthenticationRequired)
        }

        do {
            _ = try await service.analyze(summary: "摘要", moodTag: "平静", recentMoods: [], goals: [])
            XCTFail("缺少 API Key 时不应发送请求")
        } catch {
            XCTAssertEqual(error as? AIServiceError, AIServiceError.missingAPIKey)
            XCTAssertFalse(requestWasSent)
        }
    }

    func testAIOnlyAcceptsHTTPSEndpoints() {
        XCTAssertNotNil(APIConfig.validated(provider: .deepseek, baseURLString: "https://api.deepseek.com/v1", model: "deepseek-chat"))
        XCTAssertNil(APIConfig.validated(provider: .custom, baseURLString: "http://api.example.test/v1", model: "m"))
        XCTAssertNil(APIConfig.validated(provider: .custom, baseURLString: "https://api.example.test/v1", model: "   "))
        XCTAssertEqual(APIConfig.fallback.provider, .deepseek)
        XCTAssertEqual(APIConfig.fallback.chatCompletionsURL.absoluteString, "https://api.deepseek.com/v1/chat/completions")
    }

    func testAIServiceMapsUnauthorizedResponse() async throws {
        let service = makeService { request in
            let response = HTTPURLResponse(url: request.url ?? self.endpoint, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data("{\"error\":{\"message\":\"invalid api key\"}}".utf8), response)
        }

        do {
            _ = try await service.analyze(summary: "摘要", moodTag: "平静", recentMoods: [], goals: [])
            XCTFail("401 应抛出未授权错误")
        } catch {
            XCTAssertEqual(error as? AIServiceError, AIServiceError.unauthorized)
        }
    }

    /// 有的兼容网关不认 response_format，应在 400 后去掉它重试一次
    func testAIServiceRetriesWithoutJSONModeWhenRejected() async throws {
        let goalID = UUID()
        var attempts = 0
        let service = makeService { request in
            attempts += 1
            if attempts == 1 {
                let response = HTTPURLResponse(url: request.url ?? self.endpoint, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (Data("{\"error\":{\"message\":\"response_format not supported\"}}".utf8), response)
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            XCTAssertNil(body["response_format"])
            return self.chatResponse(content: self.analysisContent(goalID: goalID), url: request.url ?? self.endpoint)
        }

        let result = try await service.analyze(summary: "摘要", moodTag: "平静", recentMoods: [], goals: [])

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(result.emotion.label, "开心")
    }

    func testAIServiceThrowsOnInvalidContent() async throws {
        let service = makeService { request in
            self.chatResponse(content: "这不是 JSON", url: request.url ?? self.endpoint)
        }

        do {
            _ = try await service.analyze(summary: "摘要", moodTag: "平静", recentMoods: [], goals: [])
            XCTFail("内容不是 JSON 时应抛错")
        } catch {
            XCTAssertEqual(error as? AIServiceError, AIServiceError.invalidResponse)
        }
    }

    func testAIServicePropagatesNetworkFailure() async throws {
        let service = makeService { _ in throw URLError(.notConnectedToInternet) }

        do {
            _ = try await service.analyze(summary: "摘要", moodTag: "平静", recentMoods: [], goals: [])
            XCTFail("断网时应抛出网络错误")
        } catch {
            guard let aiError = error as? AIServiceError, case .network = aiError else {
                return XCTFail("应映射为网络错误，实际：\(error)")
            }
        }
    }

    /// 本地兜底文案要贴合用户自选心情
    func testLocalEmpathyMatchesSelectedMood() {
        let anxious = LocalEmpathy.analysis(moodTag: "焦虑")
        XCTAssertEqual(anxious.emotion.label, "焦虑")
        XCTAssertEqual(anxious.emotion.score, 2, accuracy: 0.001)
        XCTAssertFalse(anxious.empathy.isEmpty)
        XCTAssertFalse(anxious.suggestions.isEmpty)
    }

    func testAnalysisRoundTripsThroughStorageJSON() throws {
        let analysis = LocalEmpathy.analysis(moodTag: "开心")
        let json = try XCTUnwrap(analysis.storageJSON)
        let decoded = try DiaryAnalysisParser.parse(json)

        XCTAssertEqual(decoded.emotion.label, analysis.emotion.label)
        XCTAssertEqual(decoded.empathy, analysis.empathy)
        XCTAssertEqual(decoded.suggestions, analysis.suggestions)
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

    func testDiaryExportDocumentWritesUTF8PlainText() throws {
        let exportText = "心情：平静\n今天值得记下来。"
        let document = DiaryExportDocument(text: exportText)

        XCTAssertEqual(document.serializedData, Data(exportText.utf8))
    }

    private func makeCryptoManager() -> CryptoManager {
        CryptoManager(testKey: SymmetricKey(size: .bits256))
    }
}
