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
          InsulinConversionExplanation()
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
  var body: some View {
    List {
      Section("How Conversion Works") {
        explanation("Source insulin", systemImage: "drop.fill",
          detail: "All source insulin amounts use a U-100 baseline.")
        explanation("Apply the concentration", systemImage: "multiply.circle",
          detail: "PumpSync multiplies source insulin amounts by the factor for your selected concentration.")
        explanation("Save to Apple Health", systemImage: "heart.fill",
          detail: "The converted insulin amount is saved to Apple Health. Carbohydrates remain in grams.")
      }
      Section("Conversion Factors") {
        ForEach(InsulinConcentration.allCases) { concentration in
          LabeledContent(concentration.title) {
            Text("×\(concentration.healthMultiplierFactor)")
              .monospacedDigit()
              .foregroundStyle(Color.primary)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(concentration.title)
          .accessibilityValue("Multiply by \(concentration.healthMultiplierFactor)")
        }
      }
      Section("When Changes Apply") {
        explanation("Next sync", systemImage: "clock.arrow.circlepath",
          detail: "A sync already running keeps its starting setting. Previously imported Apple Health data is unchanged.")
        explanation("Pump settings stay the same", systemImage: "checkmark.shield",
          detail: "PumpSync converts data for Apple Health. It does not change your pump settings.")
      }
      Section {
        explanation("Not sure?", systemImage: "questionmark.circle",
          detail: "Confirm your concentration against your insulin prescription, pump configuration, or care team before changing it.")
      }
    }
    .headerProminence(.increased)
    .navigationTitle("Insulin Conversion")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func explanation(_ title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline)
        Text(detail).fixedSize(horizontal: false, vertical: true)
      }
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
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
