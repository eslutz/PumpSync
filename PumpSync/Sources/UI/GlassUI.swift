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
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: spacing) {
        content
      }
      .frame(maxWidth: 760, alignment: .topLeading)
      .frame(maxWidth: .infinity, alignment: .top)
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 24)
    }
    .scrollDismissesKeyboard(.interactively)
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
          .accessibilityAddTraits(.isHeader)
          .foregroundStyle(.primary)
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

private struct RowIconColumn: ViewModifier {
  @ScaledMetric(relativeTo: .title3) private var width = 28

  func body(content: Content) -> some View {
    content
      .font(.title3)
      .fixedSize()
      .frame(width: width, alignment: .center)
      .accessibilityHidden(true)
  }
}

extension View {
  func rowIconColumn() -> some View {
    modifier(RowIconColumn())
  }
}

struct GlassStatusRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let title: String
  let value: String
  let systemImage: String
  var tint: Color = .accentColor
  var showsProgress = false
  var truncatesValue = false

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(spacing: 14))
    layout {
      Image(systemName: systemImage)
        .rowIconColumn()
        .foregroundStyle(tint)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .foregroundStyle(.primary)
        Text(value)
          .lineLimit(truncatesValue ? 1 : nil)
          .truncationMode(.middle)
          .font(.subheadline)
          .foregroundStyle(Color.pumpSyncSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      .layoutPriority(1)

      if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }

      if showsProgress && !reduceMotion {
        ProgressView()
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(value)
  }
}

struct GlassNavigationRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
      if !dynamicTypeSize.isAccessibilitySize {
        Image(systemName: systemImage)
          .rowIconColumn()
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .foregroundStyle(.primary)

        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(Color.pumpSyncSecondaryText)
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
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .padding(.vertical, 6)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(subtitle ?? "")
    .accessibilityHint("Opens \(title)")
  }
}

struct GlassDivider: View {
  @ScaledMetric(relativeTo: .title3) private var iconWidth = 28
  var leadingPadding: CGFloat? = nil

  var body: some View {
    Divider()
      .padding(.leading, leadingPadding ?? iconWidth + 14)
  }
}

struct GlassPrimaryLabel: View {
  let title: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .rowIconColumn()
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      Text(title)
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)

      Spacer(minLength: 0)
    }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
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
      .frame(minHeight: 44)
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

struct LabeledMenuPickerRow<Content: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let title: String
  let systemImage: String
  @ViewBuilder let content: () -> Content

  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      stacked
    } else {
      HStack(spacing: 0) {
        icon.padding(.trailing, 14)
        Text(title).fixedSize(horizontal: false, vertical: true)
          .accessibilityHidden(true)
        Spacer(minLength: 8)
        content()
      }
    }
  }

  private var stacked: some View {
    VStack(alignment: .leading, spacing: 8) {
      icon
      Text(title).accessibilityHidden(true)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var icon: some View {
    Image(systemName: systemImage)
      .rowIconColumn()
      .foregroundStyle(.tint)
  }
}

// The system picker supplies its indicator and selected-item checkmarks.
struct NativeMenuPicker<Selection: Hashable, Options: View>: View {
  let title: String
  @Binding var selection: Selection
  private let options: Options

  init(_ title: String, selection: Binding<Selection>, @ViewBuilder options: () -> Options) {
    self.title = title
    _selection = selection
    self.options = options()
  }

  var body: some View {
    Picker(title, selection: $selection) { options }
      .pickerStyle(.menu)
      .tint(.primary)
      .buttonStyle(NativeMenuPickerButtonStyle())
      .labelsHidden()
      .font(.subheadline)
      .fixedSize(horizontal: true, vertical: true)
      .frame(minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
  }
}

private struct NativeMenuPickerButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(minHeight: 44, alignment: .leading)
      .contentShape(Rectangle())
  }
}

// The rendered system secondary label nearly failed ordinary-text contrast on
// grouped surfaces in the design-review audit. Retain hierarchy with an
// adaptive primary-label color at a stronger opacity in both appearances.
extension Color {
  static var pumpSyncSecondaryText: Color { Color.primary.opacity(0.8) }
  static var pumpSyncDestructiveAction: Color {
    Color(uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.4, blue: 0.38, alpha: 1)
        : UIColor(red: 0.65, green: 0.04, blue: 0.07, alpha: 1)
    })
  }
}
