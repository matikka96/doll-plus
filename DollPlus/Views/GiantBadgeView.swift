//
//  GiantBadgeView.swift
//  Doll
//
//  Created by xiaogd on 2023/1/11.
//

import SwiftUI
import Utils

class GiantBadgeViewController: ObservableObject {
    // Toggle this to zero so animation can start over again
    @Published var animationFlag = false
}

let giantBadgeSize = NSSize(width: 500, height: 400)
let giantBadgeYOffset: CGFloat = 10

struct GiantBadgeView: View {

    @ObservedObject var controller: GiantBadgeViewController

    @State private var pulseCount: Double = 0

    var body: some View {
        VStack {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: giantBadgeSize.width / 2))
                .foregroundColor(.red)
                .rotationEffect(.degrees(90))
                .modifier(ArrowPulseEffect(pulseCount: pulseCount))
                .offset(y: giantBadgeYOffset)

            Spacer()
        }
        .frame(width: giantBadgeSize.width, height: giantBadgeSize.height)
        .onReceive(controller.$animationFlag) { _ in
            ArrowFrameMeter.begin(duration: ArrowPulse.duration)
            // A new animation for each step makes the arrow choppy (#64).
            withAnimation(.linear(duration: ArrowPulse.duration)) {
                pulseCount = pulseCount.rounded(.down) + 1
            }
        }
    }
}

private struct ArrowPulseEffect: ViewModifier, Animatable {
    var pulseCount: Double

    var animatableData: Double {
        get { pulseCount }
        set { pulseCount = newValue }
    }

    func body(content: Content) -> some View {
        ArrowFrameMeter.recordFrame()
        let time = (pulseCount - pulseCount.rounded(.down)) * ArrowPulse.duration
        return content.scaleEffect(ArrowPulse.scale(at: time), anchor: .top)
    }
}
