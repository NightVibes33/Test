import Metal
import MetalKit
import MetalSplatter
import simd
import SplatIO
import SwiftUI

struct GaussianSplatView: UIViewRepresentable {
    let url: URL

    final class Coordinator {
        var renderer: ScanAnythingSplatRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.025, green: 0.025, blue: 0.03, alpha: 1)
        view.preferredFramesPerSecond = 60

        if let renderer = ScanAnythingSplatRenderer(view: view) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
            renderer.load(url)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.loadIfNeeded(url)
    }
}

fileprivate final class ScanAnythingSplatRenderer: NSObject, MTKViewDelegate {
    private let view: MTKView
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var splatRenderer: SplatRenderer?
    private var loadedURL: URL?
    private var drawableSize = CGSize(width: 1, height: 1)
    private var rotation: Float = 0
    private let inFlight = DispatchSemaphore(value: 2)

    init?(view: MTKView) {
        guard let device = view.device,
              let queue = device.makeCommandQueue()
        else { return nil }
        self.view = view
        self.device = device
        self.queue = queue
        super.init()
    }

    func loadIfNeeded(_ url: URL) {
        guard loadedURL != url else { return }
        load(url)
    }

    func load(_ url: URL) {
        loadedURL = url
        splatRenderer = nil

        Task { [weak self] in
            guard let self else { return }
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
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        rotation += 0.0025

        let projection = perspective(
            fovy: 55 * .pi / 180,
            aspect: Float(drawableSize.width / drawableSize.height),
            near: 0.01,
            far: 100
        )
        let viewMatrix = translation(0, 0, -2.2)
            * rotationMatrix(radians: rotation, axis: SIMD3<Float>(0, 1, 0))
            * rotationMatrix(radians: .pi, axis: SIMD3<Float>(0, 0, 1))

        let viewport = MTLViewport(
            originX: 0,
            originY: 0,
            width: drawableSize.width,
            height: drawableSize.height,
            znear: 0,
            zfar: 1
        )
        let descriptor = ViewportDescriptor(
            viewport: viewport,
            projectionMatrix: projection,
            viewMatrix: viewMatrix,
            screenSize: SIMD2(x: Int(drawableSize.width), y: Int(drawableSize.height))
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
            if rendered { commandBuffer.present(drawable) }
        } catch {
            inFlight.signal()
            return
        }

        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }
}

private func rotationMatrix(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    let axis = simd_normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = axis.x, y = axis.y, z = axis.z
    return simd_float4x4(columns: (
        SIMD4<Float>(ct + x*x*ci, y*x*ci + z*st, z*x*ci - y*st, 0),
        SIMD4<Float>(x*y*ci - z*st, ct + y*y*ci, z*y*ci + x*st, 0),
        SIMD4<Float>(x*z*ci + y*st, y*z*ci - x*st, ct + z*z*ci, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    ))
}

private func perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
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
