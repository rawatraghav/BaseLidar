import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            ARViewControllerRepresentable()
                .edgesIgnoringSafeArea(.all)
        }
    }
}
