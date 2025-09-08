import FoundationModels
import SwiftUI

struct UnavailableView: View {
  var availability: SystemLanguageModel.Availability {
    SystemLanguageModel.default.availability
  }

  var availabilityDescription: String {
    switch availability {
    case .available:
      return "Foundation Models are available"
    case .unavailable(let reason):
      switch reason {
      case .appleIntelligenceNotEnabled:
        return "Apple Intelligence is not enabled in Settings"
      case .deviceNotEligible:
        return "Device is not eligible for Foundation Models"
      case .modelNotReady:
        return "Foundation Models are not ready"
      default:
        return "Foundation Models are not available"
      }
    }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        ContentUnavailableView(
          "Foundation Models Unavailable",
          systemImage: "exclamationmark.triangle",
          description: Text(
            "This app requiere a device supporting Apple Intelligence and the Foundation Models framework.\n Make sure Apple Intelligence is enabled in Settings."
          ))
        Text(availabilityDescription)
          .font(.callout)
          .foregroundStyle(.textSecondary)
        Button("Open Settings") {
          UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        }
        .buttonStyle(.glassProminent)
      }
      .padding(.top, 64)
    }
  }
}
