import SwiftUI

struct EqualizerView: View {
    @EnvironmentObject private var player: MusicPlayer

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(MusicPlayer.equalizerBands.enumerated()), id: \.offset) { index, band in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(band.label)
                                Spacer()
                                Text("\(Int(player.equalizerGains[index])) dB")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(
                                value: Binding(
                                    get: { player.equalizerGains[index] },
                                    set: { player.setEqualizerGain($0, at: index) }
                                ),
                                in: -12...12,
                                step: 1
                            )
                            .tint(.purple)
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    HStack {
                        Text("Equalizador de 10 bandas")
                        Spacer()
                        Button("Redefinir") { player.resetEqualizer() }
                            .textCase(nil)
                    }
                } footer: {
                    Text("Os ganhos são aplicados ao áudio local pelo AVAudioEngine. Ajuste cada frequência entre −12 dB e +12 dB.")
                }

                Section("Volume") {
                    VStack(alignment: .leading) {
                        Text("Volume: \(Int(player.volume * 100))%")
                        Slider(value: $player.volume, in: 0...1)
                            .tint(.purple)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Equalizador")
        }
    }
}
