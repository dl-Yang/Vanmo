import { EmptyStateView } from '../../components/EmptyStateView';
import { MediaPosterCard } from '../../components/MediaPosterCard';
import { VanmoColors, VanmoSpacing } from '../../common/Theme';
import { LibraryViewModel } from '../../viewmodels/LibraryViewModel';

@Component
export struct LibraryHomePage {
  @State private viewModel: LibraryViewModel = new LibraryViewModel();

  aboutToAppear(): void {
    this.viewModel.load();
  }

  build() {
    Scroll() {
      Column({ space: VanmoSpacing.lg }) {
        Text('媒体库')
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(VanmoColors.primaryText)
          .width('100%')

        if (this.viewModel.recentlyPlayed.length > 0) {
          Text('继续观看')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(VanmoColors.primaryText)
            .width('100%')
        }

        if (this.viewModel.items.length === 0) {
          EmptyStateView({
            title: '还没有媒体',
            message: '添加 Emby、WebDAV 或本地文件夹后，媒体会出现在这里。'
          })
        } else {
          Grid() {
            ForEach(this.viewModel.items, (item) => {
              GridItem() {
                MediaPosterCard({ item })
              }
            }, (item) => item.id)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(VanmoSpacing.md)
          .rowsGap(VanmoSpacing.lg)
        }
      }
      .padding(VanmoSpacing.md)
    }
    .backgroundColor(VanmoColors.background)
  }
}
