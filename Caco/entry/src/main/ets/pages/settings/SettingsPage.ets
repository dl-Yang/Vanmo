import { settingsStore, type AppSettings } from '../../data/SettingsStore';
import { VanmoColors, VanmoSpacing } from '../../common/Theme';

@Component
export struct SettingsPage {
  @State private settings?: AppSettings;

  aboutToAppear(): void {
    settingsStore.read().then((value) => {
      this.settings = value;
    });
  }

  build() {
    Column({ space: VanmoSpacing.lg }) {
      Text('设置')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(VanmoColors.primaryText)
        .width('100%')

      this.settingRow('自动下载元数据', this.settings?.autoDownloadMetadata ? '开启' : '关闭')
      this.settingRow('字幕字号', `${this.settings?.subtitleFontSize ?? 18}`)
      this.settingRow('默认倍速', `${this.settings?.preferredPlaybackRate ?? 1}x`)

      Text('Settings 页面尚缺 Figma 设计，当前为迁移骨架。')
        .fontSize(13)
        .fontColor(VanmoColors.mutedText)
        .width('100%')
    }
    .padding(VanmoSpacing.md)
    .backgroundColor(VanmoColors.background)
  }

  @Builder
  private settingRow(title: string, value: string) {
    Row() {
      Text(title)
        .fontSize(17)
        .fontColor(VanmoColors.primaryText)
      Blank()
      Text(value)
        .fontSize(15)
        .fontColor(VanmoColors.secondaryText)
    }
    .width('100%')
    .padding(VanmoSpacing.md)
    .backgroundColor(VanmoColors.surface)
    .borderRadius(14)
  }
}
