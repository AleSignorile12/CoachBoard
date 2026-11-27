import SwiftUI
import UIKit

/// Marks a row as part of a glass card. It draws nothing itself: ListCardCorners finds it and puts one pane of
/// Liquid Glass behind the whole card (all its rows), as Apple suggests for larger components, instead of one pane per row.
struct CardFill: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker { Marker() }
    func updateUIView(_ uiView: Marker, context: Context) {}

    final class Marker: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("not used") }
    }
}

extension View {
    /// Liquid Glass card behind every row in this section (or row).
    func cardBackground() -> some View {
        listRowBackground(CardFill())
            // The line between rows runs across the whole card, not only under the text.
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

/// iOS 26 rounds the first and last cell of every list card with a fixed 26 pt corner, and SwiftUI has no setting
/// for it. This invisible helper finds the list next to it and gives those corners a slightly tighter radius,
/// again whenever rows scroll in or the list changes. It also puts the glass pane behind each card whose rows use
/// `cardBackground()`.
struct ListCardCorners: UIViewRepresentable {
    static let radius: CGFloat = 18

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) { uiView.applySoon() }

    final class Probe: UIView {
        private weak var list: UICollectionView?
        private var observations: [NSKeyValueObservation] = []
        /// One glass pane per card, by section number.
        private var panes: [Int: UIView] = [:]
        /// Which sections are glass cards, learned from their visible rows. Forgotten when the list's content changes.
        private var cardSections: [Int: Bool] = [:]

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isHidden = true
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard list == nil, let found = nearestList() else { return }
            list = found
            let update: (UICollectionView) -> Void = { [weak self] _ in self?.applySoon() }
            observations = [
                found.observe(\.contentOffset) { list, _ in update(list) },
                found.observe(\.contentSize) { [weak self] list, _ in
                    self?.cardSections = [:]
                    update(list)
                },
                found.observe(\.bounds) { list, _ in update(list) },
            ]
            apply()
        }

        /// The list this background belongs to: the first collection view found going up from here.
        private func nearestList() -> UICollectionView? {
            var ancestor = superview
            while let view = ancestor {
                if let match = Self.firstList(in: view) { return match }
                ancestor = view.superview
            }
            return nil
        }

        private static func firstList(in view: UIView) -> UICollectionView? {
            var queue = [view]
            while !queue.isEmpty {
                let next = queue.removeFirst()
                if let list = next as? UICollectionView { return list }
                queue.append(contentsOf: next.subviews)
            }
            return nil
        }

        func applySoon() {
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        /// Keeps whichever corners iOS rounded (top, bottom or all four) and only changes how round they are.
        private func apply() {
            guard let list else { return }
            let radius = UICornerRadius.fixed(ListCardCorners.radius)
            placePanes(in: list)
            for cell in list.visibleCells {
                let corners = cell.layer.maskedCorners
                guard !corners.isEmpty else { continue }
                cell.cornerConfiguration = .corners(
                    topLeftRadius: corners.contains(.layerMinXMinYCorner) ? radius : nil,
                    topRightRadius: corners.contains(.layerMaxXMinYCorner) ? radius : nil,
                    bottomLeftRadius: corners.contains(.layerMinXMaxYCorner) ? radius : nil,
                    bottomRightRadius: corners.contains(.layerMaxXMaxYCorner) ? radius : nil)
            }
        }

        /// Sizes a glass pane to each card on screen: from the top of its first row to the bottom of its last.
        /// The panes sit behind the rows inside the list, so they scroll with it.
        private func placePanes(in list: UICollectionView) {
            var onScreen = Set<Int>()
            for cell in list.visibleCells {
                guard let section = list.indexPath(for: cell)?.section else { continue }
                if cardSections[section] == nil { cardSections[section] = Self.isCard(cell) }
                if cardSections[section] == true { onScreen.insert(section) }
            }
            for (section, pane) in panes where !onScreen.contains(section) {
                pane.isHidden = true
            }
            let layout = list.collectionViewLayout
            for section in onScreen where section < list.numberOfSections {
                let rows = list.numberOfItems(inSection: section)
                let frame = (0..<rows)
                    .compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: section))?.frame }
                    .reduce(CGRect.null) { $0.union($1) }
                guard !frame.isNull else { continue }
                let pane = panes[section] ?? makePane(in: list, section: section)
                if pane.isHidden || pane.frame == .zero {
                    pane.frame = frame
                    pane.isHidden = false
                } else if pane.frame != frame {
                    // Rows added or removed: the card grows or shrinks with them.
                    UIView.animate(withDuration: 0.3) { pane.frame = frame }
                }
            }
        }

        /// One card's pane: clear Liquid Glass, so the court and the blues show through bent at the edges, with a
        /// very light blur under it so the lines behind are just a little softer.
        private func makePane(in list: UICollectionView, section: Int) -> UIView {
            let shape = UICornerConfiguration.corners(radius: .fixed(ListCardCorners.radius))
            let pane = UIView()
            pane.isUserInteractionEnabled = false
            let blur = SoftBlur(amount: 0.5)
            blur.frame = pane.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blur.clipsToBounds = true
            blur.cornerConfiguration = shape
            pane.addSubview(blur)
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
            glass.frame = pane.bounds
            glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            glass.cornerConfiguration = shape
            pane.addSubview(glass)
            // Behind the rows, whatever order the list adds its cells in.
            pane.layer.zPosition = -1
            list.insertSubview(pane, at: 0)
            panes[section] = pane
            return pane
        }

        private static func isCard(_ cell: UIView) -> Bool {
            var queue = [cell]
            while !queue.isEmpty {
                let next = queue.removeFirst()
                if next is CardFill.Marker { return true }
                queue.append(contentsOf: next.subviews)
            }
            return false
        }
    }
}

/// A blur weaker than any UIBlurEffect style: a regular blur shown at low opacity, so the background behind
/// is only a little softer. No animation is involved, so it stays the same across tab switches and app launches.
final class SoftBlur: UIVisualEffectView {
    init(amount: CGFloat) {
        super.init(effect: UIBlurEffect(style: .regular))
        alpha = amount
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
