import { VanmoColors, VanmoRadius, VanmoSpacing } from '../common/Theme';
import type { MediaItem } from '../domain/MediaItem';

@Component
export struct MediaPosterCard {
  item: MediaItem;

  build() {
    Column({ space: VanmoSpacing.xs }) {
      Stack() {
        if (this.item.posterUri) {
          Image(this.item.posterUri)
            .width('100%')
            .height(180)
            .objectFit(ImageFit.Cover)
        } else {
          Text(this.item.title.substring(0, 1))
            .fontSize(36)
            .fontColor(VanmoColors.secondaryText)
        }
      }
      .width('100%')
      .height(180)
      .backgroundColor(VanmoColors.surfaceElevated)
      .borderRadius(VanmoRadius.md)

      Text(this.item.title)
        .fontSize(14)
        .fontColor(VanmoColors.primaryText)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }
}
