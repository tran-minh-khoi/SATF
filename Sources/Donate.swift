import AppKit
import SwiftUI

/// Thông tin ủng hộ. Mã QR (assets/donate-qr.png) mở trang ủng hộ trên mktechvn.com:
/// Ko-fi, PayPal, GitHub và chuyển khoản trong nước ở cùng một chỗ.
enum Donate {
    /// Mọi cách ủng hộ (Ko-fi, PayPal, GitHub, chuyển khoản) ở cùng một trang
    static let supportPage = URL(string: "https://mktechvn.com/support")!
}

final class DonateWindowController {
    static let shared = DonateWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: DonateView())
            w.contentView = host
            w.setContentSize(host.fittingSize)   // vừa khít nội dung
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct DonateView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var appeared = false
    @State private var beat = false

    private var qr: NSImage? {
        Bundle.main.url(forResource: "donate-qr", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.donate)
                        .scaleEffect(beat ? 1.15 : 0.9)
                        .offset(x: 4, y: 2)
                }
                .scaleEffect(appeared ? 1 : 0.7)

            VStack(spacing: 6) {
                Text(L("Support SATF", "Ủng hộ SATF"))
                    .font(.system(size: 18, weight: .bold))
                Text(L("SATF is free and open source. If it saves you time, a small coffee keeps it going. Thank you!",
                       "SATF miễn phí và mã nguồn mở. Nếu app giúp bạn tiết kiệm thời gian, một ly cà phê nhỏ sẽ giúp mình làm tiếp. Cảm ơn bạn!"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let qr {
                Image(nsImage: qr)
                    .interpolation(.none)   // QR phải sắc nét để quét
                    .resizable()
                    .frame(width: 170, height: 170)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
            }

            Text(L("Scan, or open the page: Ko-fi, PayPal or bank transfer", "Quét mã hoặc mở trang: Ko-fi, PayPal hay chuyển khoản"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button { NSWorkspace.shared.open(Donate.supportPage) } label: {
                Label(L("Open the support page", "Mở trang ủng hộ"), systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button { NSWorkspace.shared.open(URL(string: "https://github.com/tran-minh-khoi/SATF")!) } label: {
                Label(L("Or give SATF a star on GitHub", "Hoặc tặng SATF một ngôi sao trên GitHub"), systemImage: "star")
                    .font(.system(size: 12))
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(width: 360)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { beat = true }
        }
    }
}
