import AVFoundation
import AVKit
import SwiftUI

/// A muted, looping, autoplaying video that fills its box (aspect-fill, no
/// controls): screen backgrounds and hero video.
struct PaywallFillVideo: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                PaywallPlayerLayer(player: player)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if player == nil {
                let p = AVPlayer(url: url)
                p.isMuted = true
                p.actionAtItemEnd = .none
                player = p
            }
            player?.play()
        }
        .onDisappear { player?.pause() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let player, let item = note.object as? AVPlayerItem, item === player.currentItem else { return }
            player.seek(to: .zero)
            player.play()
        }
        .allowsHitTesting(false)
    }
}

#if os(iOS) || os(tvOS) || os(visionOS)
import UIKit

final class PaywallPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// An AVPlayerLayer that fills its frame.
struct PaywallPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PaywallPlayerView {
        let v = PaywallPlayerView()
        v.playerLayer.videoGravity = .resizeAspectFill
        v.playerLayer.player = player
        return v
    }

    func updateUIView(_ v: PaywallPlayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}
#elseif os(macOS)
import AppKit

final class PaywallPlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = playerLayer
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { nil }
}

/// An AVPlayerLayer that fills its frame.
struct PaywallPlayerLayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PaywallPlayerView {
        let v = PaywallPlayerView()
        v.playerLayer.player = player
        return v
    }

    func updateNSView(_ v: PaywallPlayerView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
    }
}
#else
/// watchOS has no player layer: the system player, as big as it goes.
struct PaywallPlayerLayer: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayer(player: player).disabled(true)
    }
}
#endif
