import SwiftUI

struct PumpSyncScreen<Content: View>: View {
  private let spacing: CGFloat
  private let content: Content

  init(spacing: CGFloat = 24, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: spacing) {
        content
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 120)
    }
    .background(Color(.systemGroupedBackground))
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
      .padding(.vertical, 8)
      .glassEffect(.regular, in: .rect(cornerRadius: 28))
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

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .foregroundStyle(.primary)
        Text(value)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
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

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .foregroundStyle(.primary)

        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }

      Spacer(minLength: 0)

      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
    .padding(.vertical, 6)
  }
}

struct GlassDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 42)
  }
}

struct GlassPrimaryLabel: View {
  let title: String
  let systemImage: String

  var body: some View {
    Label(title, systemImage: systemImage)
      .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
  }
}
