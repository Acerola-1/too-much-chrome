import SwiftUI

// MARK: 概念⑤ 群鸟降落（Boids 集群模拟）
// TimelineView 提供帧时钟，Flock 是非 Observable 的引用类型——
// 每帧在闭包里直接步进模拟并读取位置渲染，不触发额外的状态失效。
// 力模型与 HTML 版同参：聚集 / 分离 / 对齐 + 漩涡切向力 + 分层归位导向。

struct ConceptBoidsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flock = Flock()
    @State private var captured = 0
    @State private var capturedMB = 0
    @State private var toast = false

    var body: some View {
        ConceptFrame(info: .boids, captured: captured, capturedMB: capturedMB) {
            TimelineView(.animation(minimumInterval: nil, paused: flock.done)) { timeline in
                let _ = flock.step(timeline.date.timeIntervalSinceReferenceDate)
                ZStack {
                    IconGrid { app in
                        let boid = flock.boids[app.id]
                        Group {
                            if boid.landed {
                                IconCell(app: app)
                            } else if boid.spawned {
                                IconCell(app: app)
                                    .offset(
                                        x: boid.pos.x - boid.slot.x,
                                        y: boid.pos.y - boid.slot.y
                                    )
                                    .rotationEffect(.degrees(min(16, max(-16, boid.vel.x * 1.6))))
                            } else {
                                IconCell(app: app).opacity(0)
                            }
                        }
                    }
                    .frame(width: GridGeom.width, height: GridGeom.height)

                    if toast {
                        ToastView(text: "集群已归位")
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
            }
            .clipped()
        }
        .onAppear(perform: setup)
        .task {
            guard !reduceMotion else { return }
            await waitForLanding()
            do {
                try await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeOut(duration: 0.2)) { toast = true }
                try await Task.sleep(for: .milliseconds(1000))
                withAnimation(.easeIn(duration: 0.25)) { toast = false }
            } catch {
                // 任务取消（切换 / 重播）
            }
        }
    }

    private func setup() {
        flock.reset(slotRadius: max(GridGeom.width, GridGeom.height) * 0.62)
        if reduceMotion {
            flock.forceLandAll()
            captured = SampleData.count
            capturedMB = SampleData.sumMB
        } else {
            // 落地事件先进缓冲，再由轮询任务搬到 @State，
            // 避免「视图更新期间修改状态」
            flock.onLand = { [weak flock] app in
                flock?.pendingLandings.append(app)
            }
        }
    }

    private func waitForLanding() async {
        while !flock.done {
            drainPendingLandings()
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
        }
        drainPendingLandings()
    }

    private func drainPendingLandings() {
        let landed = flock.pendingLandings
        guard !landed.isEmpty else { return }
        flock.pendingLandings.removeAll()
        for app in landed {
            captured += 1
            capturedMB += app.totalMB
        }
    }
}

// MARK: - 模拟内核

final class Flock {
    struct Boid {
        let app: SampleApp
        let slot: CGPoint        // 网格中心坐标系下的槽位中心
        var pos: CGPoint
        var vel: CGPoint
        let spawnAt: TimeInterval
        let seekAt: TimeInterval
        var spawned = false
        var landed = false
    }

    private(set) var boids: [Boid] = []
    private(set) var done = false
    var pendingLandings: [SampleApp] = []
    var onLand: ((SampleApp) -> Void)?

    private var start: TimeInterval?
    private var last: TimeInterval?

    /// 初始即填充，避免 TimelineView 首帧先于 onAppear 求值时空数组越界
    init() {
        reset(slotRadius: max(GridGeom.width, GridGeom.height) * 0.62)
    }

    func reset(slotRadius: CGFloat) {
        boids = SampleData.apps.map { app in
            let slot = GridGeom.slotOffset(app.id)
            let slotPoint = CGPoint(x: slot.width, y: slot.height)
            let angle = Double.random(in: 0..<(2 * .pi))
            let r = Double(slotRadius)
            let seek = 0.82
                + hypot(Double(slotPoint.x), Double(slotPoint.y)) / Double(slotRadius) * 0.42
            return Boid(
                app: app,
                slot: slotPoint,
                pos: CGPoint(x: r * cos(angle), y: r * sin(angle)),
                vel: CGPoint(x: -3.4 * cos(angle), y: -3.4 * sin(angle)),
                spawnAt: 0.16 + Double(app.id) * 0.014,
                seekAt: seek
            )
        }
        start = nil
        last = nil
        done = false
        pendingLandings.removeAll()
    }

    func forceLandAll() {
        for i in boids.indices {
            boids[i].spawned = true
            boids[i].landed = true
        }
        done = true
    }

    /// 单帧步进（dt 秒；力常数按 60fps 帧长标定，f 为帧长倍率）
    func step(_ now: TimeInterval) {
        if start == nil {
            start = now
            last = now
            return
        }
        guard let s = start, let l = last else { return }
        let dt = min(0.032, now - l)
        last = now
        let el = now - s
        let f = dt / (1.0 / 60.0)

        // 未落地个体的质心
        var cx = 0.0, cy = 0.0, n = 0
        for b in boids where b.spawned && !b.landed {
            cx += b.pos.x
            cy += b.pos.y
            n += 1
        }
        if n > 0 {
            cx /= Double(n)
            cy /= Double(n)
        }

        for i in boids.indices {
            boids[i].spawned = boids[i].spawned || el >= boids[i].spawnAt
            guard boids[i].spawned && !boids[i].landed else { continue }
            var b = boids[i]

            // 聚集
            var ax = (cx - b.pos.x) * 0.0026
            var ay = (cy - b.pos.y) * 0.0026

            // 分离 + 对齐
            var alignX = 0.0, alignY = 0.0, alignN = 0
            for o in boids where o.spawned && !o.landed {
                let dx = b.pos.x - o.pos.x
                let dy = b.pos.y - o.pos.y
                let d = (dx * dx + dy * dy).squareRoot()
                if d < 46 && d > 0.001 {
                    let push = (46 - d) / 46 * 0.55
                    ax += dx / d * push
                    ay += dy / d * push
                }
                if d < 80 {
                    alignX += o.vel.x
                    alignY += o.vel.y
                    alignN += 1
                }
            }
            if alignN > 0 {
                ax += (alignX / Double(alignN) - b.vel.x) * 0.045
                ay += (alignY / Double(alignN) - b.vel.y) * 0.045
            }

            let seeking = el > b.seekAt
            if seeking {
                // 归位导向
                ax += (b.slot.x - b.pos.x) * 0.016 * f
                ay += (b.slot.y - b.pos.y) * 0.016 * f
            } else {
                // 漩涡切向力 + 弱中心吸引（中心即原点）
                let tx = -b.pos.y
                let ty = b.pos.x
                let m = max(1.0, (tx * tx + ty * ty).squareRoot())
                ax += tx / m * 0.06 * f
                ay += ty / m * 0.06 * f
                ax += -b.pos.x * 0.0009
                ay += -b.pos.y * 0.0009
            }

            b.vel.x += ax * f
            b.vel.y += ay * f

            // 速度限幅
            let sp = max(0.001, (b.vel.x * b.vel.x + b.vel.y * b.vel.y).squareRoot())
            let maxSpeed = seeking ? 7.5 : 6.0
            if sp > maxSpeed {
                b.vel.x = b.vel.x / sp * maxSpeed
                b.vel.y = b.vel.y / sp * maxSpeed
            }
            if sp < 1.1 {
                b.vel.x = b.vel.x / sp * 1.1
                b.vel.y = b.vel.y / sp * 1.1
            }

            b.pos.x += b.vel.x * f
            b.pos.y += b.vel.y * f

            let dSlotX = b.pos.x - b.slot.x
            let dSlotY = b.pos.y - b.slot.y
            let dSlot = (dSlotX * dSlotX + dSlotY * dSlotY).squareRoot()
            if seeking && dSlot < 4 {
                b.landed = true
                onLand?(b.app)
            }
            boids[i] = b
        }

        // 硬性收尾：超时仍未归位的直接落定
        if el > 3.2 {
            for i in boids.indices where boids[i].spawned && !boids[i].landed {
                boids[i].landed = true
                onLand?(boids[i].app)
            }
        }

        if boids.allSatisfy({ !$0.spawned || $0.landed }) {
            done = true
        }
    }
}
