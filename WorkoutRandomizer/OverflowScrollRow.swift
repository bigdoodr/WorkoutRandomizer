//  OverflowScrollRow.swift
//  Bodyweight WorkoutRandomizer
//
//  A horizontally-scrolling row of chips with chevrons for stepping through content that does
//  not fit — and no chevrons at all when everything does.
//
//  Nothing tells it which rows overflow. It measures its own chips against its own width at
//  runtime, so the same row shows chevrons on a small phone or at a large Dynamic Type size and
//  none on a wider screen. New chips added to the catalog are handled for free.
//
//  The chevrons sit *beside* the scroll area rather than on top of it. Overlaying them was
//  simpler, but it left short chips like "All" and "Beginner" sitting half-under a chevron, so
//  they now claim real width and the scroll area shrinks to match.
//
//  Both slots are reserved for the whole life of an overflowing row, and both chevrons are
//  always drawn — the one that cannot go any further is simply dimmed and disabled.
//
//  That symmetry is load-bearing, not decoration. Opening a slot only when its direction became
//  scrollable meant the first forward tap changed the row's width mid-scroll: revealing a chip
//  made the leading chevron appear, which narrowed the scroll area, which pushed that same chip
//  straight back off the trailing edge and cost a second tap to recover. With both slots always
//  present the scroll area never resizes, so one tap always reveals exactly one chip. Keeping
//  the disabled chevron visible also stops the reserved leading slot reading as stray
//  whitespace, which is what hiding it would look like.

import SwiftUI

/// Frames of each chip, keyed by position and measured in the scroll area's own coordinate
/// space — so they describe where a chip currently sits *on screen*, not where it sits in the
/// content. Keyed by Int rather than by the item so the key stays non-generic and the item type
/// is unconstrained: callers pass strings, enums, ints or their own structs.
private struct ChipFramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct RowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct OverflowScrollRow<Item, Chip: View>: View {
    let items: [Item]
    var spacing: CGFloat = 8
    @ViewBuilder var chip: (Item) -> Chip

    /// Width claimed by one chevron, including breathing room either side of the 26pt button.
    private static var slotWidth: CGFloat { 38 }

    @State private var spaceID = UUID()
    @State private var chipFrames: [Int: CGRect] = [:]
    @State private var viewportWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var rowWidth: CGFloat = 0

    /// Whether this row needs to scroll at all. Measured against the width that would remain
    /// with *both* slots open, so the answer can't change once they appear — which is what would
    /// otherwise let the row oscillate between scrollable and not.
    private var overflows: Bool {
        rowWidth > 0 && contentWidth > rowWidth - 2 * Self.slotWidth + 1
    }

    /// A chip is off the leading edge if it starts left of zero, off the trailing edge if it
    /// ends past the scroll area's width. The 1pt slack keeps rounding from flickering them.
    private var canScrollBack: Bool {
        overflows && chipFrames.values.contains { $0.minX < -1 }
    }
    private var canScrollForward: Bool {
        overflows && viewportWidth > 0 && chipFrames.values.contains { $0.maxX > viewportWidth + 1 }
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                chevronSlot(forward: false, proxy: proxy)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            chip(item)
                                .id(index)
                                .background(
                                    GeometryReader { geometry in
                                        Color.clear.preference(
                                            key: ChipFramesKey.self,
                                            value: [index: geometry.frame(in: .named(spaceID))]
                                        )
                                    }
                                )
                        }
                    }
                    .padding(.vertical, 2)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: ContentWidthKey.self, value: geometry.size.width)
                        }
                    )
                }
                .coordinateSpace(name: spaceID)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ViewportWidthKey.self, value: geometry.size.width)
                    }
                )

                chevronSlot(forward: true, proxy: proxy)
            }
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: RowWidthKey.self, value: geometry.size.width)
                }
            )
            .onPreferenceChange(ChipFramesKey.self) { chipFrames = $0 }
            .onPreferenceChange(ViewportWidthKey.self) { viewportWidth = $0 }
            .onPreferenceChange(ContentWidthKey.self) { contentWidth = $0 }
            .onPreferenceChange(RowWidthKey.self) { rowWidth = $0 }
            // Only the dimming animates now — the widths are fixed for the life of the row.
            .animation(.easeInOut(duration: 0.2), value: canScrollBack)
            .animation(.easeInOut(duration: 0.2), value: canScrollForward)
        }
    }

    @ViewBuilder
    private func chevronSlot(forward: Bool, proxy: ScrollViewProxy) -> some View {
        let isEnabled = forward ? canScrollForward : canScrollBack
        ZStack {
            if overflows {
                Button {
                    step(forward: forward, proxy: proxy)
                } label: {
                    Image(systemName: forward ? "chevron.right" : "chevron.left")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.gray.opacity(0.12)))
                        .overlay(Circle().strokeBorder(Color.gray.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.25)
                .accessibilityLabel(forward ? "Scroll forward" : "Scroll back")
            }
        }
        .frame(width: overflows ? Self.slotWidth : 0)
    }

    /// Advances by exactly one chip: the first one hanging off the edge is brought flush against
    /// it. Predictable, and it never leaves a chip half-cut the way a fixed-distance scroll does.
    private func step(forward: Bool, proxy: ScrollViewProxy) {
        let ordered = chipFrames.sorted { $0.key < $1.key }
        withAnimation(.easeInOut(duration: 0.25)) {
            if forward {
                if let next = ordered.first(where: { $0.value.maxX > viewportWidth + 1 }) {
                    proxy.scrollTo(next.key, anchor: .trailing)
                }
            } else {
                if let previous = ordered.last(where: { $0.value.minX < -1 }) {
                    proxy.scrollTo(previous.key, anchor: .leading)
                }
            }
        }
    }
}
