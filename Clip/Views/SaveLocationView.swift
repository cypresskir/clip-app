import SwiftUI

struct SaveLocationView: View {
    @EnvironmentObject var downloadViewModel: DownloadViewModel

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            Text(downloadViewModel.saveDirectory.abbreviatingWithTilde)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Change...") {
                downloadViewModel.chooseSaveDirectory()
            }
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

}
