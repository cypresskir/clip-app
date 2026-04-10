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
            .buttonStyle(ClipBorderedButtonStyle())
            .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: ClipTheme.smallRadius)
    }
}
