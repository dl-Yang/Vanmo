import SwiftUI

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }

    func posterStyle(width: CGFloat, height: CGFloat) -> some View {
        frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func hideAfterDelay(_ seconds: TimeInterval, isHidden: Binding<Bool>) -> some View {
        onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isHidden.wrappedValue = true
                }
            }
        }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
