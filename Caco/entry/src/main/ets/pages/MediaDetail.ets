import { EmptyStateView } from '../components/EmptyStateView';
import { VanmoColors, VanmoSpacing } from '../common/Theme';

@Entry
@Component
struct MediaDetail {
  build() {
    Scroll() {
      Column({ space: VanmoSpacing.lg }) {
        Stack() {
          Text('MediaDetail')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(VanmoColors.primaryText)
        }
        .width('100%')
        .height(260)
        .backgroundColor(VanmoColors.surfaceElevated)

        EmptyStateView({
          title: '媒体详情',
          message: '已登记 Figma 节点 203:2，后续按截图补齐背景、Logo、演职员和剧集列表。'
        })
      }
    }
    .backgroundColor(VanmoColors.background)
  }
}
