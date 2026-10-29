import AppKit
import SwiftUI

/// Thông tin ủng hộ. Mã VietQR (assets/donate-vietqr.png) tạo từ đúng tài khoản này.
enum Donate {
    static let bank = "MB Bank"
    static let account = "0335337802"
    static let owner = "Tran Minh Khoi"
    /// Link ủng hộ quốc tế (Ko-fi, Buy Me a Coffee…). nil = ẩn tab Quốc tế.
    static let internationalURL: URL? = nil
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
            w.contentView = NSHostingView(rootView: DonateView())
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
    @State private var copied = false
    @State private var beat = false

    private var qr: NSImage? {
        Bundle.main.url(forResource: "donate-vietqr", withExtension: "png").flatMap(NSImage.init(contentsOf:))
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
                    .frame(width: 190, height: 190)
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
            }

            VStack(spacing: 2) {
                Text(L("Scan with any banking app (VietQR)", "Quét bằng app ngân hàng bất kỳ (VietQR)"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("\(Donate.bank) · \(Donate.account)").font(.system(size: 13, weight: .semibold, design: .rounded))
                    Button {
                        Clipboard.copyText(Donate.account)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { copied = false } }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help(L("Copy account number", "Copy số tài khoản"))
                }
                Text(Donate.owner).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if let url = Donate.internationalURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label(L("Support from abroad", "Ủng hộ từ nước ngoài"), systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

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
