import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// 横向页面条：点击打开详情，拖拽页面可重排。
@MainActor
struct PageStrip: View {
    @ObservedObject var session: ScanSession
    let onSelect: (UUID) -> Void

    @State private var showExport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("页面 \(session.pageCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Button {
                    showExport = true
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(session.pageCount == 0)
                .accessibilityLabel("导出页面")
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(session.document.pages.enumerated()), id: \.element.id) { index, page in
                        Button { onSelect(page.id) } label: { thumbnail(page) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("第 \(index + 1) 页，共 \(session.pageCount) 页")
                            .accessibilityValue(accessibilityState(for: page.state))
                            .accessibilityHint("轻点两下编辑页面，可拖拽或使用详情中的排序按钮")
                            .draggable(page.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let raw = items.first,
                                      let source = UUID(uuidString: raw) else {
                                    return false
                                }
                                session.movePage(id: source, before: page.id)
                                return true
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 76)
        }
        .padding(.vertical, 8)
        .background(.black.opacity(0.55))
        .sheet(isPresented: $showExport) {
            ExportSheet(session: session)
        }
    }

    private func accessibilityState(for state: PageState) -> String {
        switch state {
        case .processing: return "处理中"
        case .done: return "已完成"
        case .failed: return "处理失败"
        }
    }

    @ViewBuilder
    private func thumbnail(_ page: ScanPage) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.5))
            if let image = page.correctedImage ?? session.images.workingImage(for: page.id) {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .scaledToFill()
                    .opacity(page.correctedImage == nil ? 0.4 : 1)
            } else {
                Image(systemName: "doc.text").foregroundStyle(.white.opacity(0.7))
            }
            if page.state == .processing {
                ProgressView().tint(.white)
            } else if page.state == .failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 58, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.85), lineWidth: 1.5)
        }
    }
}

/// 页面详情：滤镜、重新裁剪、重拍、删除。
@MainActor
struct PageDetailView: View {
    @ObservedObject var session: ScanSession
    let pageID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let page = session.page(id: pageID) {
                    VStack(spacing: 14) {
                        imageView(page)

                        Picker("滤镜", selection: filterBinding) {
                            ForEach(PageFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { pageActions(page) }
                            VStack(spacing: 12) { pageActions(page) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    ContentUnavailableView("页面已删除", systemImage: "doc")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showEditor) { editorSheet }
        .confirmationDialog("删除这一页？", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                session.delete(id: pageID)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    @ViewBuilder
    private func pageActions(_ page: ScanPage) -> some View {
        Button("前移") { session.movePage(id: pageID, by: -1) }
            .disabled(session.document.pages.first?.id == pageID)
        Button("后移") { session.movePage(id: pageID, by: 1) }
            .disabled(session.document.pages.last?.id == pageID)
        Button("重新裁剪") { showEditor = true }
            .disabled(page.state == .processing)
        Button("重拍") {
            session.beginRetake(pageID: pageID)
            dismiss()
        }
        .disabled(page.state == .processing)
        Button("删除", role: .destructive) { showDeleteConfirmation = true }
    }

    private var title: String {
        let index = session.document.pages.firstIndex { $0.id == pageID }
        return "第 \((index ?? 0) + 1) 页"
    }

    private var filterBinding: Binding<PageFilter> {
        Binding(get: { session.page(id: pageID)?.filter ?? .original },
                set: { session.setFilter($0, for: pageID) })
    }

    @ViewBuilder
    private func imageView(_ page: ScanPage) -> some View {
        if let corrected = page.correctedImage,
           let display = PageFilterRenderer.shared.apply(page.filter, to: corrected) {
            Image(uiImage: UIImage(cgImage: display))
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
        } else {
            ZStack {
                Color.black
                if page.state == .failed {
                    Text("处理失败").foregroundStyle(.white)
                } else {
                    ProgressView("处理中…").tint(.white)
                }
            }
        }
    }

    @ViewBuilder
    private var editorSheet: some View {
        if let page = session.page(id: pageID),
           let working = session.images.workingImage(for: pageID) {
            CornerEditorView(image: working,
                             workingSize: page.workingSize,
                             detectedQuad: page.detectedQuad,
                             initialQuad: page.quad) { quad in
                session.updateQuad(pageID: pageID, quad: quad)
            }
        } else {
            Text("无法载入工作图").padding()
        }
    }
}

/// 手动裁剪：四个可拖角点 + 放大镜；重置到检测框或 6% 内缩框。
@MainActor
struct CornerEditorView: View {
    let image: CGImage
    let workingSize: CGSize
    let detectedQuad: Quad
    let onConfirm: (Quad) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quad: Quad
    @State private var dragStart: Quad?
    @State private var activeCorner: Int?

    init(image: CGImage,
         workingSize: CGSize,
         detectedQuad: Quad,
         initialQuad: Quad? = nil,
         onConfirm: @escaping (Quad) -> Void) {
        self.image = image
        self.workingSize = workingSize
        self.detectedQuad = detectedQuad
        self.onConfirm = onConfirm
        _quad = State(initialValue: initialQuad ?? detectedQuad)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let fitted = CornerEditorGeometry.fittedRect(imageSize: workingSize,
                                                             viewSize: proxy.size)
                ZStack {
                    Color.black
                    Image(uiImage: UIImage(cgImage: image))
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)

                    quadPath(viewSize: proxy.size)
                        .stroke(.green, lineWidth: 2)

                    ForEach(0..<4, id: \.self) { index in
                        handle(index: index, viewSize: proxy.size)
                    }

                    if let activeCorner {
                        loupe(corner: quad.corners[activeCorner],
                              fitted: fitted,
                              viewSize: proxy.size)
                    }
                }
            }
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("手动裁剪")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func quadPath(viewSize: CGSize) -> Path {
        var path = Path()
        let points = quad.corners.map {
            CornerEditorGeometry.viewPoint(fromImage: $0,
                                           imageSize: workingSize,
                                           viewSize: viewSize)
        }
        guard points.count == 4 else { return path }
        path.addLines(points)
        path.closeSubpath()
        return path
    }

    private func handle(index: Int, viewSize: CGSize) -> some View {
        let imagePoint = quad.corners[index]
        let point = CornerEditorGeometry.viewPoint(fromImage: imagePoint,
                                                   imageSize: workingSize,
                                                   viewSize: viewSize)
        let names = ["左上角", "右上角", "右下角", "左下角"]
        let stepX = max(1, workingSize.width / 100)
        let stepY = max(1, workingSize.height / 100)
        return Circle()
            .fill(activeCorner == index ? Color.yellow : Color.white)
            .frame(width: 28, height: 28)
            .overlay { Circle().stroke(.green, lineWidth: 2) }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(point)
            .gesture(dragGesture(index: index, viewSize: viewSize))
            .accessibilityLabel(names[index])
            .accessibilityValue("横坐标 \(Int(imagePoint.x))，纵坐标 \(Int(imagePoint.y))")
            .accessibilityHint("轻扫调整水平位置，也可使用方向移动操作")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: nudgeCorner(index, dx: stepX, dy: 0)
                case .decrement: nudgeCorner(index, dx: -stepX, dy: 0)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "向左移动") { nudgeCorner(index, dx: -stepX, dy: 0) }
            .accessibilityAction(named: "向右移动") { nudgeCorner(index, dx: stepX, dy: 0) }
            .accessibilityAction(named: "向上移动") { nudgeCorner(index, dx: 0, dy: -stepY) }
            .accessibilityAction(named: "向下移动") { nudgeCorner(index, dx: 0, dy: stepY) }
    }

    private func nudgeCorner(_ index: Int, dx: CGFloat, dy: CGFloat) {
        let current = quad.corners[index]
        let destination = CornerEditorGeometry.clamp(
            CGPoint(x: current.x + dx, y: current.y + dy), to: workingSize)
        quad = CornerEditorGeometry.dragging(quad, index: index, to: destination,
                                             imageSize: workingSize)
    }

    private func dragGesture(index: Int, viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = quad
                    activeCorner = index
                }
                guard let start = dragStart else { return }
                let startView = CornerEditorGeometry.viewPoint(
                    fromImage: start.corners[index],
                    imageSize: workingSize,
                    viewSize: viewSize)
                let movedView = CGPoint(x: startView.x + value.translation.width,
                                        y: startView.y + value.translation.height)
                let imagePoint = CornerEditorGeometry.clamp(
                    CornerEditorGeometry.imagePoint(fromView: movedView,
                                                    imageSize: workingSize,
                                                    viewSize: viewSize),
                    to: workingSize)
                // 非凸/退化位置被拒绝：角点停在最后一个合法位置。
                quad = CornerEditorGeometry.dragging(quad,
                                                     index: index,
                                                     to: imagePoint,
                                                     imageSize: workingSize)
            }
            .onEnded { _ in
                dragStart = nil
                activeCorner = nil
            }
    }

    private func loupe(corner: CGPoint, fitted: CGRect, viewSize: CGSize) -> some View {
        let anchor = CornerEditorGeometry.viewPoint(fromImage: corner,
                                                    imageSize: workingSize,
                                                    viewSize: viewSize)
        let side: CGFloat = 110
        let zoom: CGFloat = 2.5
        let inset = side / 2 + 8
        let x = min(max(anchor.x, inset), max(inset, viewSize.width - inset))
        let proposedY = anchor.y > side + 40
            ? anchor.y - side / 2 - 24
            : anchor.y + side / 2 + 24
        let y = min(max(proposedY, inset), max(inset, viewSize.height - inset))
        let relative = CGPoint(x: anchor.x - fitted.minX,
                               y: anchor.y - fitted.minY)

        return ZStack {
            Color.black
            Image(uiImage: UIImage(cgImage: image))
                .resizable()
                .frame(width: fitted.width * zoom, height: fitted.height * zoom)
                .offset(x: (fitted.width / 2 - relative.x) * zoom,
                        y: (fitted.height / 2 - relative.y) * zoom)
            Circle().stroke(.white, lineWidth: 2)
            Rectangle().fill(.green).frame(width: 1, height: side * 0.35)
            Rectangle().fill(.green).frame(width: side * 0.35, height: 1)
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .position(x: x, y: y)
    }

    private var bottomBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { bottomButtons }
            VStack(spacing: 12) { bottomButtons }
        }
        .padding()
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var bottomButtons: some View {
        Button("检测框") { quad = detectedQuad }
        Button("内缩 6%") { quad = Quad.insetDefault(for: workingSize) }
        Button("取消") { dismiss() }
        Button("应用") {
            onConfirm(quad)
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .disabled(!CornerEditorGeometry.isConfirmable(quad, imageSize: workingSize))
    }
}
