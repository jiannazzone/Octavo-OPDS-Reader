import SwiftUI
import UIKit

/// The progress bar's scrubber (decision 35): the system's slider, moving
/// freely across the whole book. Holding still narrows its range around the
/// finger (`ReaderScrubberLine`), which is why it's UIKit: SwiftUI's `Slider`
/// doesn't say where its knob is, and the dots have to line up with it.
struct ReaderScrubber: UIViewRepresentable {
    @Binding var value: Double
    /// Where each contents entry starts.
    var chapters: [Double]
    var total: Int?
    /// Let go on `chapter`'s start, if it caught there, else on the value.
    var released: (_ chapter: Double?) -> Void
    /// The touch was taken away: the page stays where it is.
    var cancelled: () -> Void

    func makeUIView(context: Context) -> ReaderScrubberSlider {
        ReaderScrubberSlider()
    }

    func updateUIView(_ slider: ReaderScrubberSlider, context: Context) {
        slider.onChange = { value = $0 }
        slider.onRelease = released
        slider.onCancel = cancelled
        slider.update(chapters: chapters, total: total)
        if !slider.isTracking, !slider.isZoomed { slider.value = Float(value) }
    }
}

final class ReaderScrubberSlider: UISlider {
    /// How long the finger has to hold still before the line zooms in.
    private static let holdDelay = 0.35
    private static let zoomDuration = 0.22
    /// The finger counts as still within this, in points.
    private static let stillPoints = 1.5
    /// The least time between ticks while passing chapters.
    private static let tickSpacing = 0.06

    var onChange: ((Double) -> Void)?
    var onRelease: ((Double?) -> Void)?
    var onCancel: (() -> Void)?
    private(set) var isZoomed = false

    private var chapters: [Double] = []
    private var total: Int?
    private let marks = CALayer()
    private let dots = CAShapeLayer()
    private let bars = CAShapeLayer()
    private let fade = CAGradientLayer()
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private var speed = ReaderScrubberSpeed()
    private var link: CADisplayLink?
    private var zoom: (from: ClosedRange<Float>, to: ClosedRange<Float>, start: CFTimeInterval, holding: Float)?
    private var stillAt: Float = 0
    private var lastFrame: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var lastChapter: Int?
    private var caught: Double?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(began), for: .touchDown)
        addTarget(self, action: #selector(changed), for: .valueChanged)
        addTarget(self, action: #selector(released), for: [.touchUpInside, .touchUpOutside])
        addTarget(self, action: #selector(cancelled), for: .touchCancel)
        marks.addSublayer(dots)
        marks.addSublayer(bars)
        layer.insertSublayer(marks, at: 0)
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        fade.locations = [0, 0.1, 0.9, 1]
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.redrawMarks() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not used") }

    func update(chapters: [Double], total: Int?) {
        guard chapters != self.chapters || total != self.total else { return }
        self.chapters = chapters
        self.total = total
        redrawMarks()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        redrawMarks()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        redrawMarks()
    }

    // MARK: The line

    private var knobWidth: CGFloat {
        thumbRect(forBounds: bounds, trackRect: trackRect(forBounds: bounds), value: value).width
    }

    private var line: ReaderScrubberLine {
        ReaderScrubberLine(chapters: chapters, total: total, travel: max(Double(bounds.width - knobWidth), 0))
    }

    private var shownRange: ClosedRange<Double> {
        Double(minimumValue)...Double(maximumValue)
    }

    private func setShownRange(_ range: ClosedRange<Float>) {
        minimumValue = range.lowerBound
        maximumValue = range.upperBound
    }

    /// Where `fraction` falls on the line, in the slider's own points.
    private func position(of fraction: Double, on line: ReaderScrubberLine) -> CGFloat {
        knobWidth / 2 + CGFloat((fraction - shownRange.lowerBound) / ReaderScrubberLine.length(of: shownRange) * line.travel)
    }

    private func redrawMarks() {
        guard bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        marks.frame = bounds
        let line = line
        let y = trackRect(forBounds: bounds).maxY + 5
        let dotPath = UIBezierPath()
        let barPath = UIBezierPath()
        let dotPositions = isZoomed ? line.pageDots(in: shownRange) : line.chapterDots
        for dot in dotPositions {
            dotPath.append(UIBezierPath(ovalIn: CGRect(x: position(of: dot, on: line) - 1.25, y: y, width: 2.5, height: 2.5)))
        }
        if isZoomed {
            for bar in line.chapterBars(in: shownRange) {
                barPath.append(UIBezierPath(roundedRect: CGRect(x: position(of: bar, on: line) - 1.25, y: y - 3, width: 2.5, height: 9), cornerRadius: 1.25))
            }
            fade.frame = marks.bounds
        }
        marks.mask = isZoomed ? fade : nil
        dots.fillColor = UIColor.tertiaryLabel.resolvedColor(with: traitCollection).cgColor
        bars.fillColor = tintColor.resolvedColor(with: traitCollection).cgColor
        dots.path = dotPath.cgPath
        bars.path = barPath.cgPath
        CATransaction.commit()
    }

    // MARK: Tracking

    @objc private func began() {
        selection.prepare()
        impact.prepare()
        stillAt = value
        speed.reset()
        lastChapter = line.chapterIndex(at: Double(value))
        waitForHold()
        startLink()
    }

    @objc private func changed() {
        // The slider eases toward the finger, and goes on a moment after it
        // lifts. Past that, the place has been chosen.
        guard isTracking else { return }
        // The line is still narrowing: the finger hasn't said anything yet.
        if let zoom, zoom.to != Self.wholeBook {
            value = zoom.holding
            return
        }
        let raw = Double(value)
        let line = line
        let perPoint = ReaderScrubberLine.length(of: shownRange) / max(line.travel, 1)
        if abs(raw - Double(stillAt)) / perPoint >= Self.stillPoints {
            waitForHold()
            stillAt = value
        }
        let quick = speed.moved(to: raw / perPoint, at: CACurrentMediaTime())
        if isZoomed, zoom == nil, quick {
            zoomOutFollowingTheFinger()
        } else if isZoomed {
            catchChapter(near: raw, on: line)
        } else {
            tickPassingChapters(at: raw, on: line)
        }
        onChange?(caught ?? Double(value))
    }

    @objc private func released() {
        let chapter = caught
        endTracking()
        onRelease?(chapter)
    }

    @objc private func cancelled() {
        endTracking()
        onCancel?()
    }

    private func endTracking() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(holdEnded), object: nil)
        caught = nil
        guard isZoomed else {
            stopLink()
            return
        }
        animateZoom(to: Self.wholeBook, holding: value)
    }

    private func catchChapter(near raw: Double, on line: ReaderScrubberLine) {
        guard let chapter = line.caughtChapter(near: raw, in: shownRange) else {
            caught = nil
            return
        }
        value = Float(chapter)
        if caught != chapter {
            caught = chapter
            selection.selectionChanged()
        }
    }

    private func tickPassingChapters(at raw: Double, on line: ReaderScrubberLine) {
        let chapter = line.chapterIndex(at: raw)
        guard chapter != lastChapter else { return }
        lastChapter = chapter
        let now = CACurrentMediaTime()
        guard now - lastTick >= Self.tickSpacing else { return }
        lastTick = now
        selection.selectionChanged()
    }

    // MARK: Zooming

    private static let wholeBook: ClosedRange<Float> = 0...1

    private func waitForHold() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(holdEnded), object: nil)
        if !isZoomed { perform(#selector(holdEnded), with: nil, afterDelay: Self.holdDelay) }
    }

    @objc private func holdEnded() {
        guard isTracking, !isZoomed, let zoomed = line.zoomed(around: Double(value), in: shownRange) else { return }
        impact.impactOccurred()
        animateZoom(to: Float(zoomed.lowerBound)...Float(zoomed.upperBound), holding: value)
    }

    /// A quick move: the knob follows the finger across the whole book at once.
    private func zoomOutFollowingTheFinger() {
        setShownRange(Self.wholeBook)
        isZoomed = false
        zoom = nil
        caught = nil
        lastChapter = line.chapterIndex(at: Double(value))
        waitForHold()
        redrawMarks()
    }

    private func animateZoom(to target: ClosedRange<Float>, holding: Float) {
        isZoomed = true
        guard !UIAccessibility.isReduceMotionEnabled else {
            finishZoom(at: target, holding: holding)
            return
        }
        zoom = (minimumValue...maximumValue, target, CACurrentMediaTime(), holding)
        startLink()
    }

    private func finishZoom(at target: ClosedRange<Float>, holding: Float) {
        zoom = nil
        setShownRange(target)
        value = holding
        if target == Self.wholeBook {
            isZoomed = false
            if isTracking { waitForHold() } else { stopLink() }
        } else if isTracking {
            // Held still right on a chapter's start.
            catchChapter(near: Double(value), on: line)
            if let caught { onChange?(caught) }
        }
        redrawMarks()
    }

    private func startLink() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frameFired))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastFrame = CACurrentMediaTime()
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    override func removeFromSuperview() {
        stopLink()
        super.removeFromSuperview()
    }

    @objc private func frameFired() {
        let now = CACurrentMediaTime()
        let elapsed = now - lastFrame
        lastFrame = now
        if let zoom {
            let progress = min((now - zoom.start) / Self.zoomDuration, 1)
            guard progress < 1 else {
                finishZoom(at: zoom.to, holding: zoom.holding)
                return
            }
            let eased = Float(progress * progress * (3 - 2 * progress))
            setShownRange((zoom.from.lowerBound + (zoom.to.lowerBound - zoom.from.lowerBound) * eased)...(zoom.from.upperBound + (zoom.to.upperBound - zoom.from.upperBound) * eased))
            value = zoom.holding
            redrawMarks()
            return
        }
        guard isZoomed, isTracking else { return }
        let ratio = (Double(value) - shownRange.lowerBound) / ReaderScrubberLine.length(of: shownRange)
        guard let slid = ReaderScrubberLine.slid(shownRange, knobAt: ratio, elapsed: elapsed) else { return }
        setShownRange(Float(slid.lowerBound)...Float(slid.upperBound))
        value = Float(slid.lowerBound + ratio * ReaderScrubberLine.length(of: slid))
        onChange?(Double(value))
        redrawMarks()
    }

    // MARK: VoiceOver

    override func accessibilityIncrement() {
        super.accessibilityIncrement()
        adjustedByVoiceOver()
    }

    override func accessibilityDecrement() {
        super.accessibilityDecrement()
        adjustedByVoiceOver()
    }

    private func adjustedByVoiceOver() {
        onChange?(Double(value))
        onRelease?(nil)
    }
}
