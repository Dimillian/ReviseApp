import SwiftData
import SwiftUI

struct DocumentsListView: View {
  private let thesaurus = Thesaurus()

  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Document.lastEdited, order: .reverse) private var documents: [Document]

  @Binding var path: NavigationPath

  @State private var generatingTitle = false

  var body: some View {
    List {
      ForEach(documents) { document in
        NavigationLink(value: document) {
          VStack(alignment: .leading) {
            Text(document.title)
              .font(.literata(size: 16, relativeTo: .body))
            HStack(spacing: 0) {
              Text(
                document.lastEdited, format: .relative(presentation: .numeric, unitsStyle: .narrow)
              )
              let versionCount = document.branches.flatMap { $0.versions }.count
              let wordCount = document.currentBranch?.currentVersion?.wordCount ?? 0
              let branchCount = document.branches.count
              if versionCount > 0 {
                Text("  •  ")
                Text(
                  "\(wordCount) \(wordCount == 1 ? "word" : "words")  •  \(versionCount) \(versionCount == 1 ? "version" : "versions")  •  \(branchCount) \(branchCount == 1 ? "branch" : "branches")"
                )
              }
            }
            .font(.inter(size: 12, relativeTo: .caption))
            .foregroundColor(.textSecondary)
          }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
      .onDelete(perform: deleteDocuments)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(Color.background)
    .toolbar {
      titleView
      newDocumentButton
    }
    .navigationBarTitleDisplayMode(.inline)
  }

  private var titleView: some ToolbarContent {
    ToolbarItem(placement: .title) {
      Text("Drafts")
        .font(.inter(size: 24, relativeTo: .title))
        .fontWeight(.bold)
    }
  }

  private var newDocumentButton: some ToolbarContent {
    ToolbarItem(placement: .navigationBarTrailing) {
      Button(action: createNewDocument) {
        if generatingTitle {
          ProgressView()
        } else {
          Image(systemName: "plus")
        }
      }
    }
  }

  private func createNewDocument() {
    Task { @MainActor in
      generatingTitle = true
      let title = (try? await thesaurus.initialTitle()) ?? "Untitled"

      let document = Document(title: title)
      modelContext.insert(document)

      let mainBranch = Branch(name: Branch.main, document: document)
      modelContext.insert(mainBranch)

      let initialVersion = Version(text: "", branch: mainBranch, changeType: .manual)
      modelContext.insert(initialVersion)

      mainBranch.currentVersion = initialVersion
      document.branches.append(mainBranch)
      document.currentBranch = mainBranch

      do {
        try modelContext.save()
        generatingTitle = false
        path.append(document)
      } catch {
        print("Failed to save document: \(error)")
        generatingTitle = false
      }
    }
  }

  private func deleteDocuments(at offsets: IndexSet) {
    for index in offsets {
      let document = documents[index]
      modelContext.delete(document)
    }
    try? modelContext.save()
  }
}
