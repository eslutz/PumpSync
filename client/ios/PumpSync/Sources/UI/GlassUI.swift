import SwiftUI

struct PumpSyncScreen<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let spacing: CGFloat
  private let content: Content

  init(spacing: CGFloat = 24, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: spacing) {
        content
      }
      .frame(maxWidth: 760, alignment: .topLeading)
      .frame(maxWidth: .infinity, alignment: .top)
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 120)
    }
    .background(Color(.systemGroupedBackground))
    .transaction { transaction in
      if reduceMotion {
        transaction.animation = nil
      }
    }
  }
}

struct GlassSection<Content: View>: View {
  private let title: String?
  private let content: Content

  init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        Text(title)
          .font(.headline)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 4)
      }

      VStack(alignment: .leading, spacing: 0) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(
        Color(.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
      )
    }
  }
}

struct GlassStatusRow: View {
  let title: String
  let value: String
  let systemImage: String
  var tint: Color = .accentColor

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(width: 28)
        .foregroundStyle(tint)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .foregroundStyle(.primary)
        Text(value)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .layoutPriority(1)

      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(value)
  }
}

struct GlassNavigationRow: View {
  let title: String
  let subtitle: String?
  let systemImage: String

  init(_ title: String, subtitle: String? = nil, systemImage: String) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
  }

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(width: 28)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .foregroundStyle(.primary)

        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 0)

      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .contentShape(Rectangle())
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(subtitle ?? "")
    .accessibilityHint("Opens \(title)")
  }
}

struct GlassDivider: View {
  var leadingPadding: CGFloat = 42

  var body: some View {
    Divider()
      .padding(.leading, leadingPadding)
  }
}

struct GlassPrimaryLabel: View {
  let title: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.title3)
        .frame(width: 28)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      Text(title)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)

      Spacer(minLength: 0)
    }
      .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(title)
  }
}

struct GroupedActionButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 18)
      .padding(.vertical, 16)
      .background(
        Color(.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : disabledOpacity)
  }

  private var disabledOpacity: Double {
    colorSchemeContrast == .increased ? 0.7 : 0.55
  }
}

struct GroupedRowActionButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.vertical, 6)
      .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : disabledOpacity)
  }

  private var disabledOpacity: Double {
    colorSchemeContrast == .increased ? 0.7 : 0.55
  }
}

struct GroupedInlineButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
      .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : disabledOpacity)
  }

  private var disabledOpacity: Double {
    colorSchemeContrast == .increased ? 0.7 : 0.55
  }
}
