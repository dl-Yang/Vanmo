import { EmptyStateView } from '../../components/EmptyStateView';
import { MediaPosterCard } from '../../components/MediaPosterCard';
import { VanmoColors, VanmoSpacing } from '../../common/Theme';
import { LibraryViewModel } from '../../viewmodels/LibraryViewModel';

@Component
export struct FavoritesPage {
  @State private viewModel: LibraryViewModel = new LibraryViewModel();

  aboutToAppear(): void {
    this.viewModel.load();
  }

  build() {
    Column({ space: VanmoSpacing.md }) {
      Text('收藏')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(VanmoColors.primaryText)
        .width('100%')

      if (this.viewModel.favorites.length === 0) {
        EmptyStateView({
          title: '暂无收藏',
          message: '在详情页标记喜欢后，会在这里集中展示。'
        })
      } else {
        Grid() {
          ForEach(this.viewModel.favorites, (item) => {
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
    .backgroundColor(VanmoColors.background)
  }
}
