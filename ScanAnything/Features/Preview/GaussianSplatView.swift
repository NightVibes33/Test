import Metal
import MetalKit
import MetalSplatter
import simd
import SplatIO
import SwiftUI

struct GaussianSplatView: UIViewRepresentable {
    let url: URL

    @MainActor
    final class Coordinator {
        fileprivate var renderer: ScanAnythingSplatRenderer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.025, green: 0.025, blue: 0.03, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        view.isAccessibilityElement = true
        view.accessibilityLabel = "3D scan preview"
        view.accessibilityHint = "Drag to rotate and pinch to zoom."

        if let renderer = ScanAnythingSplatRenderer(view: view) {
            renderer.autoRotate = !context.environment.accessibilityReduceMotion
            context.coordinator.renderer = renderer
            view.delegate = renderer
            renderer.load(url)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.autoRotate =
            !context.environment.accessibilityReduceMotion
        context.coordinator.renderer?.loadIfNeeded(url)
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        uiView.isPaused = true
        uiView.delegate = nil
        coordinator.renderer = nil
    }
}

@MainActor
fileprivate final class ScanAnythingSplatRenderer: NSObject, @preconcurrency MTKViewDelegate {
    private weak var view: MTKView?
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var splatRenderer: SplatRenderer?
    private var loadedURL: URL?
    private var drawableSize = CGSize(width: 1, height: 1)
    private let inFlight = DispatchSemaphore(value: 2)

    var autoRotate = true

    private var yaw: Float = 0.2
    private var pitch: Float = -0.08
    private var distance: Float = 2.2

    init?(view: MTKView) {
        guard let device = view.device,
              let queue = device.makeCommandQueue()
        else { return nil }

        self.view = view
        self.device = device
        self.queue = queue
        super.init()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
    }

    func loadIfNeeded(_ url: URL) {
        guard loadedURL != url else { return }
        load(url)
    }

    func load(_ url: URL) {
        loadedURL = url
        splatRenderer = nil

        Task { [weak self] in
            guard let self, let view else { return }

            do {
                let renderer = try SplatRenderer(
                    device: device,
                    colorFormat: view.colorPixelFormat,
                    depthFormat: view.depthStencilPixelFormat,
                    sampleCount: view.sampleCount,
                    maxViewCount: 1,
                    maxSimultaneousRenders: 2
                )
                let reader = try AutodetectSceneReader(url)
                let points = try await reader.readAll()
                try Task.checkCancellation()

                let chunk = try SplatChunk(device: device, from: points)
                await renderer.addChunk(chunk)
                splatRenderer = renderer
            } catch {
                splatRenderer = nil
            }
        }
    }

    func draw(in view: MTKView) {
        guard let renderer = splatRenderer,
              renderer.isReadyToRender,
              let drawable = view.currentDrawable,
              drawableSize.width > 0,
              drawableSize.height > 0
        else { return }

        _ = inFlight.wait(timeout: .distantFuture)
        guard let commandBuffer = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }

        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }

        if autoRotate {
            yaw += 0.0025
        }

        let projection = perspective(
            fovy: 55 * .pi / 180,
            aspect: Float(drawableSize.width / drawableSize.height),
            near: 0.01,
            far: 100
        )
        let viewMatrix = translation(0, 0, -distance)
            * rotationMatrix(radians: pitch, axis: SIMD3<Float>(1, 0, 0))
            * rotationMatrix(radians: yaw, axis: SIMD3<Float>(0, 1, 0))
            * rotationMatrix(radians: .pi, axis: SIMD3<Float>(0, 0, 1))

        let viewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: drawableSize.width,
            height: drawableSize.height,
            znear: 0,
            zfar: 1
        )
        let descriptor = SplatRenderer.ViewportDescriptor(
            viewport: viewport,
            projectionMatrix: projection,
            viewMatrix: viewMatrix,
            screenSize: SIMD2(
                x: Int(drawableSize.width),
                y: Int(drawableSize.height)
            )
        )

        do {
            let rendered = try renderer.render(
                viewports: [descriptor],
                colorTexture: drawable.texture,
                colorStoreAction: .store,
                depthTexture: view.depthStencilTexture,
                rasterizationRateMap: nil,
                renderTargetArrayLength: 0,
                to: commandBuffer
            )
            if rendered {
                commandBuffer.present(drawable)
            }
            commandBuffer.commit()
        } catch {
            inFlight.signal()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }

    @objc
    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }

        let delta = gesture.translation(in: view)
        gesture.setTranslation(.zero, in: view)

        yaw += Float(delta.x) * 0.007
        pitch = min(max(pitch + Float(delta.y) * 0.007, -1.25), 1.25)
    }

    @objc
    private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.scale > 0 else { return }

        distance = min(max(distance / Float(gesture.scale), 0.55), 8.0)
        gesture.scale = 1
    }
}

private func rotationMatrix(
    radians: Float,
    axis: SIMD3<Float>
) -> simd_float4x4 {
    let axis = simd_normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = axis.x
    let y = axis.y
    let z = axis.z

    return simd_float4x4(columns: (
        SIMD4<Float>(ct + x*x*ci, y*x*ci + z*st, z*x*ci - y*st, 0),
        SIMD4<Float>(x*y*ci - z*st, ct + y*y*ci, z*y*ci + x*st, 0),
        SIMD4<Float>(x*z*ci + y*st, y*z*ci - x*st, ct + z*z*ci, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

private func translation(
    _ x: Float,
    _ y: Float,
    _ z: Float
) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

private func perspective(
    fovy: Float,
    aspect: Float,
    near: Float,
    far: Float
) -> simd_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / max(aspect, 0.01)
    let zs = far / (near - far)

    return simd_float4x4(columns: (
        SIMD4<Float>(xs, 0, 0, 0),
        SIMD4<Float>(0, ys, 0, 0),
        SIMD4<Float>(0, 0, zs, -1),
        SIMD4<Float>(0, 0, zs * near, 0)
    ))
}
