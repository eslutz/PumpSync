import SwiftUI

struct InsulinConcentrationView: View {
  @Environment(AppServices.self) private var services

  var body: some View {
    InsulinConcentrationForm(concentration: Binding(
      get: { services.insulinConcentrationStore.concentration },
      set: { services.insulinConcentrationStore.concentration = $0 }
    ))
  }
}

private struct InsulinConcentrationForm: View {
  @Binding var concentration: InsulinConcentration

  var body: some View {
    Form {
      Section {
        Picker("Insulin Concentration", selection: $concentration) {
          ForEach(InsulinConcentration.allCases) { choice in Text(choice.title).tag(choice) }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        Text(InsulinConcentrationPresentation.effect(for: concentration))
          .font(.body)
          .foregroundStyle(Color.primary)
          .fixedSize(horizontal: false, vertical: true)
      } header: {
        Text("Current Setting")
          .foregroundStyle(Color.primary)
      }
      .headerProminence(.increased)

      Section {
        Text("Applies to the next sync. A running sync keeps its starting setting. It does not change pump settings or previously imported Apple Health records.")
          .fixedSize(horizontal: false, vertical: true)
        NavigationLink {
          InsulinConversionExplanation(concentration: concentration)
        } label: {
          Label {
            Text("How Insulin Conversion Works")
              .fixedSize(horizontal: false, vertical: true)
          } icon: {
            Image(systemName: "info.circle")
          }
        }
      }
    }
    .navigationTitle("Insulin Concentration")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct InsulinConversionExplanation: View {
  let concentration: InsulinConcentration

  var body: some View {
    List {
      Section("Current Selection") {
        LabeledContent("Insulin Concentration") { Text(concentration.title).foregroundStyle(Color.primary) }
        Text(InsulinConcentrationPresentation.effect(for: concentration))
      }
      Section("Conversion Only") {
        Text("PumpSync assumes all source insulin data uses a U-100 baseline. The selected concentration changes how those insulin amounts are converted before saving them to Apple Health. Carbohydrates remain in grams.")
      }
      Section("Apple Health Only") {
        Text("Changes apply to the next sync. A sync already running keeps its starting setting. Previously imported Apple Health data is not changed. PumpSync does not change your pump settings.")
      }
      Section("Not Sure?") {
        Text("If you are unsure, verify your current selection before changing it. Confirm it against your insulin prescription, pump configuration, or care team.")
      }
    }
    .headerProminence(.increased)
    .navigationTitle("Insulin Conversion")
    .navigationBarTitleDisplayMode(.inline)
  }
}

enum InsulinConcentrationPresentation {
  static func effect(for concentration: InsulinConcentration) -> String {
    String(localized: "Current selection: \(concentration.title). PumpSync multiplies insulin amounts from U-100 baseline source data by \(concentration.healthMultiplierFactor) before saving them to Apple Health.")
  }
}

#if DEBUG
#Preview("Concentration U-200") {
  NavigationStack { InsulinConcentrationForm(concentration: .constant(.u200)) }
}
#endif
