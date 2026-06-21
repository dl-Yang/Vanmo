import { EmptyStateView } from '../../components/EmptyStateView';
import { VanmoColors, VanmoSpacing } from '../../common/Theme';
import { ConnectionsViewModel } from '../../viewmodels/ConnectionsViewModel';

@Component
export struct FilePage {
  @State private viewModel: ConnectionsViewModel = new ConnectionsViewModel();

  aboutToAppear(): void {
    this.viewModel.load();
  }

  build() {
    Column({ space: VanmoSpacing.lg }) {
      Text('文件')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(VanmoColors.primaryText)
        .width('100%')

      if (this.viewModel.connections.length === 0) {
        EmptyStateView({
          title: '添加媒体源',
          message: 'WebDAV、Emby、Jellyfin、Plex 和 SMB 将在这里统一管理。'
        })
      } else {
        ForEach(this.viewModel.connections, (connection) => {
          Row() {
            Column() {
              Text(connection.name)
                .fontSize(17)
                .fontColor(VanmoColors.primaryText)
              Text(`${connection.type} · ${connection.host}`)
                .fontSize(13)
                .fontColor(VanmoColors.secondaryText)
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(VanmoSpacing.md)
          .backgroundColor(VanmoColors.surface)
          .borderRadius(14)
        }, (connection) => connection.id)
      }
    }
    .padding(VanmoSpacing.md)
    .backgroundColor(VanmoColors.background)
  }
}
