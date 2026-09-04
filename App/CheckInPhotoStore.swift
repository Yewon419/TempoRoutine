// 템포루틴 — 한 줄 기록 사진 (2026-09-04 베타 "오늘 한줄 밑에 사진 넣기 추가", "사진은 최대 한장")
//
// 저장은 **파일**, 기록에는 파일 이름만 둔다(`DailyCheckIn.photoName`).
// 이미지 바이트를 @Model에 넣으면 스토어가 부풀고, DailyCheckIn은 CloudKit으로 미러되는 층이라
// (§5.2) 레코드 하나가 수 MB가 된다. 그래서 사진은 **이 기기 안에만** 둔다:
// - 동기화 DTO(DailyCheckInDTO)에 photoName을 넣지 않는다 → 다른 기기로 넘어가지 않는다.
// - 내보내기 봉투에도 안 실린다 → 백업 파일에 사진이 들어가지 않는다(평문 JSON이다).
// 이 두 가지는 의도된 한계다. 바꾸려면 CKAsset·번들 내보내기 설계가 따로 필요하다.
//
// 원본을 그대로 두지 않고 긴 변 1600pt·JPEG 0.8로 줄여 넣는다 — 일기 한 장에 원본 4000px는 과하다.

import SwiftUI
import UIKit

enum CheckInPhotoStore {
    /// 가장 긴 변 상한(pt) — 화면에 크게 띄워도 이 정도면 충분하다
    private static let maxDimension: CGFloat = 1600

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("CheckInPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for name: String) -> URL? {
        directory?.appendingPathComponent(name)
    }

    /// 고른 사진을 줄여서 저장하고 파일 이름을 돌려준다. 실패하면 nil(기록은 건드리지 않는다).
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data),
              let jpeg = downscaled(image).jpegData(compressionQuality: 0.8) else { return nil }
        let name = UUID().uuidString + ".jpg"
        guard let url = url(for: name) else { return nil }
        do {
            try jpeg.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func image(named name: String?) -> UIImage? {
        guard let name, let url = url(for: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func delete(_ name: String?) {
        guard let name, let url = url(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 전체 삭제·앱 초기화 — 기록이 사라지면 사진도 남을 이유가 없다
    static func purgeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
