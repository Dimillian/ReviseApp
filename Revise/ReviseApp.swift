//
//  ReviseApp.swift
//  Revise
//
//  Created by Thomas Ricouard on 01/09/2025.
//

import SwiftUI

@main
struct ReviseApp: App {
  @State private var document = Document(id: UUID().uuidString)
  
  var body: some Scene {
    WindowGroup {
      EditorView(document: document)
    }
  }
}
