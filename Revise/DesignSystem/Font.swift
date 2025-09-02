import SwiftUI

extension Font {
  // MARK: - Custom Font Names
  private static let literataName = "Literata"
  private static let interName = "Inter"

  // MARK: - Literata Font
  static func literata(size: CGFloat = 17, relativeTo textStyle: TextStyle = .body) -> Font {
    .custom(literataName, size: size, relativeTo: textStyle)
  }

  // MARK: - Inter Font
  static func inter(size: CGFloat = 17, relativeTo textStyle: TextStyle = .body) -> Font {
    .custom(interName, size: size, relativeTo: textStyle)
  }
}
