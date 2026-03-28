import Foundation
import AppKit
import MetalKit
import QuartzCore
import ScreenSaver

private struct FluxScreenSaverArticleSnapshot: Codable, Identifiable {
    let id: UUID
    let title: String
    let summary: String?
    let url: URL
    let imageURL: URL?
    let imageFileName: String?
    let feedTitle: String
    let faviconURL: URL?
    let faviconFileName: String?
    let publishedAt: Date?
}

private enum FluxScreenSaverStore {
    static let appGroupId = "group.com.adriendonot.fluxapp"
    static let sharedContainerFolder = "Library/Group Containers/group.com.adriendonot.fluxapp"
    static let publicSharedFolder = "/Users/Shared/FluxScreenSaver"
    static let rootFolderName = "Flux/ScreenSaver"
    static let articlesFileName = "articles.json"
    static let imagesFolderName = "images"
    static let faviconsFolderName = "favicons"

    static func rootDirectoryURL() -> URL? {
        let directory: URL
        if FileManager.default.fileExists(atPath: "/Users/Shared") {
            directory = URL(fileURLWithPath: publicSharedFolder, isDirectory: true)
        } else {
            let baseDirectory =
                FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(sharedContainerFolder, isDirectory: true)
            directory = baseDirectory.appendingPathComponent(rootFolderName, isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func articlesFileURL() -> URL? {
        rootDirectoryURL()?.appendingPathComponent(articlesFileName, isDirectory: false)
    }

    static func imageDirectoryURL() -> URL? {
        guard let rootDirectoryURL = rootDirectoryURL() else { return nil }
        let directory = rootDirectoryURL.appendingPathComponent(imagesFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func faviconDirectoryURL() -> URL? {
        guard let rootDirectoryURL = rootDirectoryURL() else { return nil }
        let directory = rootDirectoryURL.appendingPathComponent(faviconsFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class FluxScreenSaverContentModel {
    private(set) var articles: [FluxScreenSaverArticleSnapshot] = []
    private(set) var statusMessage = "Chargement…"
    private var lastLoadedAt: Date?

    func reloadIfNeeded(force: Bool = false) {
        if !force, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 20 {
            return
        }

        guard let fileURL = FluxScreenSaverStore.articlesFileURL() else {
            articles = []
            statusMessage = "Diagnostic: dossier d'actualites introuvable."
            lastLoadedAt = Date()
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            articles = []
            statusMessage = "Diagnostic: fichier absent a \(fileURL.path)"
            lastLoadedAt = Date()
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([FluxScreenSaverArticleSnapshot].self, from: data)
            articles = decoded
            statusMessage = "Diagnostic: \(decoded.count) article(s) lu(s) depuis \(fileURL.path)"
        } catch {
            articles = []
            statusMessage = "Diagnostic: lecture impossible. \(error.localizedDescription)"
        }
        lastLoadedAt = Date()
    }
}

private final class FluxScreenSaverRenderer: NSObject, MTKViewDelegate {
    struct Payload {
        let article: FluxScreenSaverArticleSnapshot
        let localImageURL: URL?
    }

    private struct Uniforms {
        var resolution: SIMD2<Float>
        var time: Float
        var transitionProgress: Float
        var glow: Float
        var currentScale: Float
        var nextScale: Float
        var currentOffset: SIMD2<Float>
        var nextOffset: SIMD2<Float>
        var currentHasTexture: UInt32
        var nextHasTexture: UInt32
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let startedAt = CACurrentMediaTime()
    private let textureLoader: MTKTextureLoader
    private let fallbackTexture: MTLTexture

    private var currentTexture: MTLTexture?
    private var nextTexture: MTLTexture?
    private var transitionStartTime: CFTimeInterval?
    private var currentScale: Float = 1.08
    private var nextScale: Float = 1.12
    private var currentOffset = SIMD2<Float>(0, 0)
    private var nextOffset = SIMD2<Float>(0, 0)

    init?(metalView: MTKView) {
        guard
            let device = metalView.device ?? MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue(),
            let library = try? device.makeDefaultLibrary(bundle: Bundle(for: FluxScreenSaverView.self)),
            let vertexFunction = library.makeFunction(name: "fluxSaverVertex"),
            let fragmentFunction = library.makeFunction(name: "fluxSaverFragment")
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        guard
            let samplerState = device.makeSamplerState(descriptor: samplerDescriptor),
            let fallbackTexture = FluxScreenSaverRenderer.makeFallbackTexture(device: device)
        else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipelineState
        self.samplerState = samplerState
        self.textureLoader = MTKTextureLoader(device: device)
        self.fallbackTexture = fallbackTexture

        super.init()

        metalView.device = device
        metalView.framebufferOnly = false
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.delegate = self
    }

    func setInitialArticle(_ payload: Payload?) {
        currentTexture = texture(for: payload)
        currentScale = randomScale()
        currentOffset = randomOffset()
    }

    func transition(to payload: Payload?) {
        nextTexture = texture(for: payload)
        nextScale = randomScale()
        nextOffset = randomOffset()
        transitionStartTime = CACurrentMediaTime()
    }

    func draw(in view: MTKView) {
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        let now = CACurrentMediaTime()
        var progress: Float = 1
        if let transitionStartTime {
            progress = min(Float((now - transitionStartTime) / 1.35), 1)
            if progress >= 1 {
                currentTexture = nextTexture ?? currentTexture
                nextTexture = nil
                currentScale = nextScale
                currentOffset = nextOffset
                self.transitionStartTime = nil
            }
        } else {
            progress = 0
        }

        var uniforms = Uniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: Float(now - startedAt),
            transitionProgress: progress,
            glow: 1,
            currentScale: currentScale,
            nextScale: nextScale,
            currentOffset: currentOffset,
            nextOffset: nextOffset,
            currentHasTexture: currentTexture == nil ? 0 : 1,
            nextHasTexture: nextTexture == nil ? 0 : 1
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentTexture(currentTexture ?? fallbackTexture, index: 0)
        encoder.setFragmentTexture(nextTexture ?? fallbackTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func texture(for payload: Payload?) -> MTLTexture? {
        if let localImageURL = payload?.localImageURL, let texture = loadTexture(from: localImageURL) {
            return texture
        }
        if let remoteURL = payload?.article.imageURL {
            cacheRemoteImage(remoteURL, fileName: payload?.article.imageFileName)
        }
        return nil
    }

    private func loadTexture(from fileURL: URL) -> MTLTexture? {
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .generateMipmaps: true
        ]
        return try? textureLoader.newTexture(URL: fileURL, options: options)
    }

    private func cacheRemoteImage(_ url: URL, fileName: String?) {
        let targetFileName = fileName ?? "\(UUID().uuidString).jpg"
        guard let directory = FluxScreenSaverStore.imageDirectoryURL() else { return }
        let destination = directory.appendingPathComponent(targetFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: destination.path) == false else { return }

        let task = URLSession.shared.downloadTask(with: url) { temporaryURL, _, _ in
            guard let temporaryURL else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.moveItem(at: temporaryURL, to: destination)
        }
        task.resume()
    }

    private func randomScale() -> Float {
        Float.random(in: 1.04...1.18)
    }

    private func randomOffset() -> SIMD2<Float> {
        SIMD2(Float.random(in: -0.06...0.06), Float.random(in: -0.05...0.05))
    }

    private static func makeFallbackTexture(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let pixels: [UInt8] = [
            24, 20, 42, 255, 52, 30, 68, 255, 41, 61, 114, 255, 20, 122, 142, 255,
            34, 24, 54, 255, 82, 41, 89, 255, 30, 83, 133, 255, 16, 138, 155, 255,
            18, 48, 76, 255, 38, 88, 124, 255, 90, 133, 185, 255, 34, 177, 163, 255,
            8, 86, 88, 255, 20, 124, 118, 255, 56, 158, 166, 255, 111, 213, 187, 255
        ]
        texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 16)
        return texture
    }
}

@objc(FluxScreenSaverView)
final class FluxScreenSaverView: ScreenSaverView {
    private let contentModel = FluxScreenSaverContentModel()
    private let backgroundImageView = NSImageView()
    private var metalView: MTKView?
    private var renderer: FluxScreenSaverRenderer?
    private var hasCompletedSetup = false
    private let overlayView = NSView()
    private let scrimLayer = CAGradientLayer()
    private let accentLine = CALayer()
    private let faviconImageView = NSImageView()
    private let feedLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(labelWithString: "")
    private var currentArticleID: UUID?

    private var currentIndex = 0
    private var lastArticleSwitchAt = CACurrentMediaTime()
    private let slideDuration: CFTimeInterval = 7.5

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        guard !hasCompletedSetup else { return }
        hasCompletedSetup = true

        animationTimeInterval = 1.0 / 30.0
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor

        setupMetalView()
        setupOverlay()
        loadArticles(force: true)
        showCurrentArticle()
    }

    override func startAnimation() {
        super.startAnimation()
        commonInit()
        loadArticles(force: true)
        showCurrentArticle()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        if now - lastArticleSwitchAt >= slideDuration {
            advanceArticle()
        } else if Int(now) % 20 == 0 {
            loadArticles(force: false)
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        commonInit()
        backgroundImageView.frame = bounds
        metalView?.frame = bounds
        overlayView.frame = bounds
        layoutOverlay()
    }

    override var hasConfigureSheet: Bool { false }

    private func setupMetalView() {
        backgroundImageView.frame = bounds
        backgroundImageView.autoresizingMask = [.width, .height]
        backgroundImageView.imageScaling = .scaleAxesIndependently
        backgroundImageView.isHidden = true
        addSubview(backgroundImageView)

        let metalView = MTKView(frame: bounds)
        metalView.autoresizingMask = [.width, .height]
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        metalView.alphaValue = 0.22
        addSubview(metalView)
        self.metalView = metalView
        self.renderer = FluxScreenSaverRenderer(metalView: metalView)
    }

    private func setupOverlay() {
        overlayView.frame = bounds
        overlayView.autoresizingMask = [.width, .height]
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(overlayView)

        scrimLayer.colors = [
            NSColor.black.withAlphaComponent(0.54).cgColor,
            NSColor.black.withAlphaComponent(0.18).cgColor,
            NSColor.clear.cgColor
        ]
        scrimLayer.locations = [0, 0.22, 1]
        scrimLayer.startPoint = CGPoint(x: 0.02, y: 0.04)
        scrimLayer.endPoint = CGPoint(x: 0.58, y: 0.82)
        overlayView.layer?.addSublayer(scrimLayer)

        faviconImageView.imageScaling = .scaleProportionallyUpOrDown
        faviconImageView.wantsLayer = true
        faviconImageView.layer?.cornerRadius = 8
        faviconImageView.layer?.masksToBounds = true
        overlayView.addSubview(faviconImageView)

        configureLabel(feedLabel, fontSize: 18, weight: .semibold, color: NSColor.white.withAlphaComponent(0.82))
        configureLabel(titleLabel, fontSize: 48, weight: .bold, color: .white)
        configureLabel(summaryLabel, fontSize: 20, weight: .regular, color: NSColor.white.withAlphaComponent(0.82))
        configureLabel(footerLabel, fontSize: 16, weight: .regular, color: NSColor.white.withAlphaComponent(0.74))
        titleLabel.maximumNumberOfLines = 7
        summaryLabel.maximumNumberOfLines = 2
        footerLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byWordWrapping
        summaryLabel.lineBreakMode = .byWordWrapping

        if let titleFont = NSFont(name: "Georgia-Bold", size: 48) {
            titleLabel.font = titleFont
        }
        if let feedFont = NSFont(name: "AvenirNext-DemiBold", size: 18) {
            feedLabel.font = feedFont
        }
        if let summaryFont = NSFont(name: "AvenirNext-Regular", size: 20) {
            summaryLabel.font = summaryFont
        }
        if let footerFont = NSFont(name: "AvenirNext-Regular", size: 16) {
            footerLabel.font = footerFont
        }
        [feedLabel, titleLabel, summaryLabel, footerLabel].forEach {
            $0.shadow = {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
                shadow.shadowBlurRadius = 10
                shadow.shadowOffset = CGSize(width: 0, height: -2)
                return shadow
            }()
        }

        [feedLabel, titleLabel, summaryLabel, footerLabel].forEach(overlayView.addSubview)
        layoutOverlay()
    }

    private func configureLabel(_ label: NSTextField, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingTail
        label.textColor = color
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        label.alignment = .left
    }

    private func layoutOverlay() {
        scrimLayer.frame = overlayView.bounds

        let horizontalPadding = max(52, bounds.width * 0.065)
        let bottomPadding = max(44, bounds.height * 0.08)
        let textWidth = min(bounds.width * 0.62, 980)
        let footerHeight: CGFloat = 24
        let summaryHeight: CGFloat = 56
        let feedHeight: CGFloat = 24
        let titleHeight = min(max(bounds.height * 0.24, 150), 220)

        footerLabel.frame = CGRect(x: horizontalPadding, y: bottomPadding + 12, width: textWidth, height: footerHeight)
        summaryLabel.frame = CGRect(
            x: horizontalPadding,
            y: footerLabel.frame.maxY + 10,
            width: textWidth,
            height: summaryHeight
        )
        titleLabel.frame = CGRect(
            x: horizontalPadding,
            y: summaryLabel.frame.maxY,
            width: textWidth,
            height: titleHeight
        )
        faviconImageView.frame = CGRect(
            x: horizontalPadding,
            y: titleLabel.frame.maxY + 10,
            width: 24,
            height: 24
        )
        feedLabel.frame = CGRect(
            x: horizontalPadding + 36,
            y: titleLabel.frame.maxY + 10,
            width: textWidth - 36,
            height: feedHeight
        )
    }

    private func loadArticles(force: Bool) {
        contentModel.reloadIfNeeded(force: force)
        if currentIndex >= contentModel.articles.count {
            currentIndex = 0
        }
    }

    private func advanceArticle() {
        guard contentModel.articles.isEmpty == false else { return }
        currentIndex = (currentIndex + 1) % contentModel.articles.count
        lastArticleSwitchAt = CACurrentMediaTime()
        showCurrentArticle(transitioning: true)
    }

    private func showCurrentArticle(transitioning: Bool = false) {
        guard contentModel.articles.isEmpty == false else {
            feedLabel.stringValue = "Flux Wall"
            titleLabel.stringValue = contentModel.statusMessage
            summaryLabel.stringValue = " "
            footerLabel.stringValue = FluxScreenSaverStore.articlesFileURL()?.path ?? "Aucun chemin disponible"
            faviconImageView.image = nil
            backgroundImageView.image = nil
            metalView?.alphaValue = 1
            renderer?.setInitialArticle(nil)
            return
        }

        let article = contentModel.articles[currentIndex]
        let imageURL = localImageURL(for: article)
        let payload = FluxScreenSaverRenderer.Payload(
            article: article,
            localImageURL: imageURL
        )

        currentArticleID = article.id
        feedLabel.stringValue = article.feedTitle.uppercased()
        titleLabel.stringValue = article.title
        summaryLabel.stringValue = article.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? article.summary!
            : " "
        footerLabel.stringValue = Self.footerText(for: article)
        backgroundImageView.image = nil
        metalView?.alphaValue = 1
        faviconImageView.image = localFaviconImage(for: article) ?? fallbackFaviconImage(for: article)
        if localFaviconImage(for: article) == nil, let remoteFaviconURL = preferredFaviconURL(for: article) {
            cacheRemoteFavicon(remoteFaviconURL, fileName: article.faviconFileName, articleID: article.id)
        }

        if transitioning {
            renderer?.transition(to: payload)
        } else {
            renderer?.setInitialArticle(payload)
        }

        animateOverlay()
    }

    private func animateOverlay() {
        [faviconImageView, feedLabel, titleLabel, summaryLabel, footerLabel].forEach {
            $0.alphaValue = 0.0
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            faviconImageView.animator().alphaValue = 1
            feedLabel.animator().alphaValue = 1
            titleLabel.animator().alphaValue = 1
            summaryLabel.animator().alphaValue = 1
            footerLabel.animator().alphaValue = 1
        }
    }

    private func localImageURL(for article: FluxScreenSaverArticleSnapshot) -> URL? {
        guard
            let imageFileName = article.imageFileName,
            let directory = FluxScreenSaverStore.imageDirectoryURL()
        else {
            return nil
        }
        let fileURL = directory.appendingPathComponent(imageFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    private static func relativeText(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func footerText(for article: FluxScreenSaverArticleSnapshot) -> String {
        let source = article.url.host?.replacingOccurrences(of: "www.", with: "") ?? "flux"
        if let publishedAt = article.publishedAt {
            return "\(source)  •  \(relativeText(from: publishedAt))"
        }
        return source
    }

    private func localFaviconImage(for article: FluxScreenSaverArticleSnapshot) -> NSImage? {
        guard
            let fileName = article.faviconFileName,
            let directory = FluxScreenSaverStore.faviconDirectoryURL()
        else {
            return nil
        }
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        return NSImage(contentsOf: fileURL)
    }

    private func preferredFaviconURL(for article: FluxScreenSaverArticleSnapshot) -> URL? {
        if let host = article.url.host,
           let serviceURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") {
            return serviceURL
        }
        return article.faviconURL
    }

    private func cacheRemoteFavicon(_ url: URL, fileName: String?, articleID: UUID) {
        let targetFileName = fileName ?? "\(UUID().uuidString)-favicon.png"
        guard let directory = FluxScreenSaverStore.faviconDirectoryURL() else { return }
        let destination = directory.appendingPathComponent(targetFileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: destination.path) {
            if currentArticleID == articleID {
                faviconImageView.image = NSImage(contentsOf: destination)
            }
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard
                let self,
                let data,
                let image = NSImage(data: data)
            else { return }

            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let tiffData = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiffData),
               let pngData = rep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: destination, options: .atomic)
            }

            DispatchQueue.main.async {
                guard self.currentArticleID == articleID else { return }
                self.faviconImageView.image = image
            }
        }
        task.resume()
    }

    private func fallbackFaviconImage(for article: FluxScreenSaverArticleSnapshot) -> NSImage? {
        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        let letter = String((article.feedTitle.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "F")).uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let attributed = NSAttributedString(string: letter, attributes: attributes)
        let textSize = attributed.size()
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 1,
            width: textSize.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)
        image.unlockFocus()
        return image
    }
}
