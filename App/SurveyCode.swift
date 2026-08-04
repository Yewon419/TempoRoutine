// 템포루틴 — 사전 설문 참여 코드 리딤 (핸드오프 v1.6 §3 / §9 3-8)
//
// 설계 원칙(문서 §3 확정안 그대로):
//   - 코드는 랜덤 40비트 불투명 문자열이다. 응답이 인코딩돼 있지 않아 앱이 디코딩할 것도 없다.
//   - 서버가 돌려주는 것은 { theme } 뿐. 프로필·응답 내용은 오지 않는다.
//   - 기기 UUID를 보내지 않는다 — 사용 여부만 서버가 마킹하므로 설문 응답과 이 기기가 연결되지 않는다.
//   - **리딤 실패가 온보딩을 막지 않는다.** 실패하면 설문 미실시 분기로 그냥 넘어간다.
//
// 이 파일이 앱의 유일한 외부 통신 경로다. 기록 데이터는 어느 경우에도 나가지 않는다.

import Foundation

enum RedeemOutcome: Equatable {
    case unlocked
    case alreadyUsed
    case unknownCode
    case malformed
    case networkFailed

    /// 사용자에게 보여줄 한 문장 — 실패도 벌하지 않는 톤(§3.3)
    var message: String {
        switch self {
        case .unlocked:      "선행 테마가 열렸어요."
        case .alreadyUsed:   "이미 사용한 코드예요."
        case .unknownCode:   "확인되지 않는 코드예요. 다시 한 번 봐주세요."
        case .malformed:     "코드 형식이 달라요. TEMPO- 뒤 8자리를 확인해주세요."
        case .networkFailed: "지금은 확인할 수 없어요. 나중에 설정에서 다시 시도할 수 있어요."
        }
    }
}

enum SurveyCode {
    private static let unlockedKey = "precursorThemeUnlocked"
    private static let endpoint = URL(string: "https://temporoutine-survey.temporoutine-survey.workers.dev/redeem")!

    /// 선행 테마 자격. 테마 아트는 아직 없어서(핸드오프 §8-4 미해결) 지금은 자격만 기록한다.
    static var isPrecursorUnlocked: Bool {
        get { UserDefaults.standard.bool(forKey: unlockedKey) }
        set { UserDefaults.standard.set(newValue, forKey: unlockedKey) }
    }

    /// 입력 정규화 — 대소문자·하이픈 유무·혼동 문자(I·L→1, O→0)를 흡수한다(서버 규칙과 동형)
    static func normalize(_ raw: String) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "TEMPO-", with: "")
            .replacingOccurrences(of: "TEMPO ", with: "")
            .filter { !$0.isWhitespace && $0 != "-" }
            .map { ch -> Character in
                switch ch {
                case "I", "L": "1"
                case "O": "0"
                default: ch
                }
            }
        let body = String(cleaned)
        guard body.count == 8 else { return nil }
        let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        guard body.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return "TEMPO-\(body)"
    }

    static func redeem(_ raw: String) async -> RedeemOutcome {
        guard let code = normalize(raw) else { return .malformed }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONEncoder().encode(["code": code])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .networkFailed }
            switch http.statusCode {
            case 200:
                // 반환은 { theme: "precursor" } — 값이 그대로여야 자격으로 인정한다
                let body = try? JSONDecoder().decode([String: String].self, from: data)
                guard body?["theme"] == "precursor" else { return .networkFailed }
                isPrecursorUnlocked = true
                return .unlocked
            case 404: return .unknownCode
            case 409: return .alreadyUsed
            case 400: return .malformed
            default:  return .networkFailed
            }
        } catch {
            return .networkFailed
        }
    }
}
