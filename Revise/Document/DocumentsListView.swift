import SwiftUI

struct DocumentsListView: View {
  private let thesaurus = Thesaurus()

  @Environment(DocumentStore.self) private var documentStore

  @Binding var path: NavigationPath

  @State private var generatingTitle = false

  var body: some View {
    List {
      ForEach(documentStore.documents) { document in
        NavigationLink(value: document) {
          VStack(alignment: .leading) {
            Text(document.title)
              .font(.literata(size: 16, relativeTo: .body))
          }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      }
      .onDelete(perform: { indexSet in
        for index in indexSet {
          let document = documentStore.documents[index]
          documentStore.deleteDocument(document)
        }
      })
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
      Button(action: {
        Task {
          generatingTitle = true
          let title = try? await thesaurus.initialTitle()
          let document = documentStore.createDocument(withTitle: title)
          generatingTitle = false
          path.append(document)
        }
      }) {
        if generatingTitle {
          ProgressView()
        } else {
          Image(systemName: "plus")
        }
      }
    }
  }
}
