export enum ColorTheme {
  System = 'system',
  Light = 'light',
  Dark = 'dark'
}

export interface AppSettings {
  colorTheme: ColorTheme;
  autoDownloadMetadata: boolean;
  subtitleFontSize: number;
  subtitleDelay: number;
  preferredPlaybackRate: number;
}

export interface SettingsStore {
  read(): Promise<AppSettings>;
  update(settings: AppSettings): Promise<void>;
}

export class InMemorySettingsStore implements SettingsStore {
  private settings: AppSettings = {
    colorTheme: ColorTheme.System,
    autoDownloadMetadata: true,
    subtitleFontSize: 18,
    subtitleDelay: 0,
    preferredPlaybackRate: 1
  };

  async read(): Promise<AppSettings> {
    return { ...this.settings };
  }

  async update(settings: AppSettings): Promise<void> {
    this.settings = { ...settings };
  }
}

export const settingsStore: SettingsStore = new InMemorySettingsStore();
