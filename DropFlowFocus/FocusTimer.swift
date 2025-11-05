import Foundation
import SwiftUI

struct FocusView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var vm = FocusVM()
    
    var body: some View {
        ZStack {
            AppBackground()
            
            VStack(spacing: 32) {
                NeonRingTimer(progress: vm.progress, mode: vm.mode)
                    .frame(width: 260, height: 260)
                    .overlay(
                        Text(vm.timeString)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    )
                
                // Controls
                HStack(spacing: 32) {
                    Button { vm.toggle() } label: {
                        Image(systemName: vm.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.neonCyan)
                    }
                    Button { vm.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                // Music picker
                Picker("Music", selection: $vm.music) {
                    ForEach(Settings.Music.allCases, id: \.self) { m in
                        Text(m.rawValue.capitalized).tag(m)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
            }
        }
        .onChange(of: vm.isRunning) { _ in
            // vm.playSound()
        }
    }
}

import Foundation
import AVFoundation

class FocusVM: ObservableObject {
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var mode: TimerMode = .pomodoro
    @Published var music: Settings.Music = .cosmicWaves
    @Published var timeString = "25:00"

    private var timer: Timer?
    private var startTime = Date()
    private var workSeconds: Int { mode == .pomodoro ? 25*60 : 60*60 }
    private var breakSeconds: Int { mode == .pomodoro ? 5*60 : 10*60 }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        isRunning = true
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.update()
        }
        SoundPlayer.shared.play("\(music.rawValue).mp3")
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        // SoundPlayer.shared.stop()
    }

    func reset() {
        stop()
        progress = 0
        timeString = mode == .pomodoro ? "25:00" : "60:00"
    }

    private func update() {
        let elapsed = Date().timeIntervalSince(startTime)
        progress = min(elapsed / Double(workSeconds), 1.0)
        let remaining = max(workSeconds - Int(elapsed), 0)
        let m = remaining / 60
        let s = remaining % 60
        timeString = String(format: "%02d:%02d", m, s)

        if progress >= 1.0 {
            stop()
            // SoundPlayer.shared.play("burst.wav")
            // Rain animation can be triggered via NotificationCenter
        }
    }
}
