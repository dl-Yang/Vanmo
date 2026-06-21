import { VanmoColors, VanmoSpacing } from '../common/Theme';

@Component
export struct EmptyStateView {
  title: string = '暂无内容';
  message: string = '连接媒体源后，这里会显示你的内容。';

  build() {
    Column({ space: VanmoSpacing.sm }) {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(VanmoColors.primaryText)

      Text(this.message)
        .fontSize(14)
        .fontColor(VanmoColors.secondaryText)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(VanmoSpacing.xl)
  }
}
