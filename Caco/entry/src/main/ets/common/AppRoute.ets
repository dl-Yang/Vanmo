export enum AppTab {
  Library = 'library',
  Files = 'files',
  Search = 'search',
  Settings = 'settings'
}

export interface TabDescriptor {
  tab: AppTab;
  title: string;
  icon: string;
}

export const AppTabs: TabDescriptor[] = [
  { tab: AppTab.Library, title: '媒体库', icon: 'library' },
  { tab: AppTab.Files, title: '文件', icon: 'files' },
  { tab: AppTab.Search, title: '搜索', icon: 'search' },
  { tab: AppTab.Settings, title: '设置', icon: 'settings' }
];

export enum RouteName {
  Index = 'pages/Index',
  MediaDetail = 'pages/MediaDetail',
  Player = 'pages/Player'
}
