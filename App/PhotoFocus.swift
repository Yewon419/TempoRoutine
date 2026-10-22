// 템포루틴 — 한 줄 기록 사진의 보일 위치·바로 찍기 (2026-10-14 베타 "사진 첨부시 미리보기에 보여질 위치
// 조정하게 해주고, 바로 촬영해서넣기도 추가")
//
// 위치는 자르기가 아니라 **초점**(사진 안의 한 점, 0~1)으로 둔다 — 같은 사진이 오늘 카드(가로 띠)와
// 나의 템포 폴라로이드(정사각)에 서로 다른 비율로 잘려 나가서, 한 비율로 잘라 저장하면 다른 쪽이 어긋난다.
// 초점은 채우기(fill) 배치에서 그 점이 틀 가운데 오도록 옮기되 사진 가장자리 밖은 보이지 않게 막는다.

import SwiftUI
import TempoCore
import UIKit

/// 채우기 배치 계산 — 틀을 빈틈없이 덮는 크기에서, 초점이 틀 가운데 오도록 원점을 옮기고 가장자리로 막는다.
enum PhotoFill {
    static func frame(image: CGSize, container: CGSize, focus: CGPoint) -> CGRect {
        guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale: CGFloat = max(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        let x: CGFloat = min(0, max(container.width - size.width, container.width / 2 - focus.x * size.width))
        let y: CGFloat = min(0, max(container.height - size.height, container.height / 2 - focus.y * size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

/// 위치 시트 대상 = 사진 파일 이름
struct PhotoFocusTarget: Identifiable {
    let id: String
}

/// 초점 기준 채우기 사진. 넘친 그림은 잘리고, 히트 영역도 넘치지 않게 그림 자체는 터치를 받지 않는다
/// (repo CLAUDE.md — scaledToFill 히트 영역 넘침 함정).
struct FocusedPhoto: View {
    let image: UIImage
    let focus: CGPoint

    var body: some View {
        GeometryReader { geo in
            let rect: CGRect = PhotoFill.frame(image: image.size, container: geo.size, focus: focus)
            Image(uiImage: image)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
        .clipped()
    }
}

/// 사진을 넣은 직후·사진 위 조정 버튼에서 뜨는 시트. 사진 전체를 보여주고 눌러 끈 자리가 초점이 된다.
/// 아래에 실제로 나가는 두 표면(오늘 카드 · 나의 템포 폴라로이드)을 같은 초점으로 미리 보여준다.
struct PhotoFocusSheet: View {
    let image: UIImage
    let onSave: (CGPoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var focus: CGPoint

    init(image: UIImage, initial: CGPoint, onSave: @escaping (CGPoint) -> Void) {
        self.image = image
        self.onSave = onSave
        _focus = State(initialValue: initial)
    }

    var body: some View {
        InkSheetScaffold(eyebrow: Loc.str("보일 위치"), saveTitle: Loc.str("완료"), saveEnabled: true,
                         phase: nil, onCancel: { dismiss() },
                         onSave: { onSave(focus); dismiss() }) {
            Text("보이고 싶은 곳을 눌러 주세요")
                .font(.almanacBody(.subheadline, size: 14))
                .foregroundStyle(Ink.text.opacity(0.7))
            picker
            InkSection(eyebrow: Loc.str("오늘 한 줄")) {
                FocusedPhoto(image: image, focus: focus)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            }
            InkSection(eyebrow: Loc.str("나의 템포")) {
                FocusedPhoto(image: image, focus: focus)
                    .frame(width: 160, height: 160)
                    .frame(maxWidth: .infinity)
            }
        } footer: {
            EmptyView()
        }
    }

    /// 사진 전체(맞춤) + 초점 표식. 끌어도 따라온다.
    private var picker: some View {
        let ratio: CGFloat = image.size.height > 0 ? image.size.width / image.size.height : 1
        return Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxHeight: 360)
            .overlay {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(alignment: .topLeading) {
                            focusMark
                                .position(x: focus.x * geo.size.width, y: focus.y * geo.size.height)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard geo.size.width > 0, geo.size.height > 0 else { return }
                            focus = CGPoint(x: min(1, max(0, value.location.x / geo.size.width)),
                                            y: min(1, max(0, value.location.y / geo.size.height)))
                        })
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(Loc.str("보일 위치"))
    }

    private var focusMark: some View {
        ZStack {
            Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 34, height: 34)
            Circle().fill(Color.white).frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.45), radius: 3)
        .allowsHitTesting(false)
    }
}

/// 카메라로 바로 찍기 — UIImagePickerController(.camera) 래퍼. 찍으면 그 사진, 취소면 nil.
struct CameraCapture: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    @MainActor static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
