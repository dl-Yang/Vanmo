import { EmptyStateView } from '../../components/EmptyStateView';
import { MediaPosterCard } from '../../components/MediaPosterCard';
import { VanmoColors, VanmoSpacing } from '../../common/Theme';
import { SearchViewModel } from '../../viewmodels/SearchViewModel';

@Component
export struct SearchPage {
  @State private viewModel: SearchViewModel = new SearchViewModel();

  build() {
    Column({ space: VanmoSpacing.md }) {
      Text('搜索')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(VanmoColors.primaryText)
        .width('100%')

      TextInput({ placeholder: '搜索标题、导演、演员', text: this.viewModel.query })
        .onChange((value) => {
          this.viewModel.updateQuery(value);
        })
        .backgroundColor(VanmoColors.surface)
        .fontColor(VanmoColors.primaryText)

      if (this.viewModel.results.length === 0) {
        EmptyStateView({
          title: '输入关键词',
          message: 'Search 页面尚缺 Figma 设计，当前只提供迁移骨架。'
        })
      } else {
        Grid() {
          ForEach(this.viewModel.results, (item) => {
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
