import SwiftUI

struct LogoView: View {
    var body: some View {
        Image("150rep_logo")
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 40)
    }
}

#Preview {
    LogoView()
}
