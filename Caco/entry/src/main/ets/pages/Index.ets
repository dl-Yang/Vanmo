import { AppTab } from '../common/AppRoute';
import { appState } from '../common/AppState';
import { VanmoColors } from '../common/Theme';
import { FilePage } from './files/FilePage';
import { LibraryHomePage } from './library/LibraryHomePage';
import { SearchPage } from './search/SearchPage';
import { SettingsPage } from './settings/SettingsPage';

@Entry
@Component
struct Index {
  @State private selectedTab: AppTab = appState.selectedTab;

  build() {
    Tabs({ barPosition: BarPosition.End }) {
      TabContent() {
        LibraryHomePage()
      }
      .tabBar('媒体库')

      TabContent() {
        FilePage()
      }
      .tabBar('文件')

      TabContent() {
        SearchPage()
      }
      .tabBar('搜索')

      TabContent() {
        SettingsPage()
      }
      .tabBar('设置')
    }
    .backgroundColor(VanmoColors.background)
    .barBackgroundColor(VanmoColors.surface)
  }
}
