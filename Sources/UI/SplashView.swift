import SwiftUI

struct SplashView: View {
    var body: some View {
        Image("LaunchImage")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) { SplashHint().padding(.bottom, 40) }
    }
}

struct SplashHint: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            Text("正在进入…").font(.footnote).foregroundStyle(.white)
        }
    }
}
