import { VanmoColors, VanmoSpacing } from '../common/Theme';
import { PlayerViewModel } from '../viewmodels/PlayerViewModel';

@Entry
@Component
struct Player {
  @State private viewModel: PlayerViewModel = new PlayerViewModel();

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Text('Player Surface')
          .fontSize(18)
          .fontColor(VanmoColors.secondaryText)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#000000')

      Row({ space: VanmoSpacing.md }) {
        Button('暂停')
          .onClick(() => this.viewModel.pause())
        Button('播放')
          .onClick(() => this.viewModel.play())
      }
      .padding(VanmoSpacing.lg)
    }
    .backgroundColor('#000000')
  }
}
