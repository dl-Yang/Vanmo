import UIAbility from '@ohos.app.ability.UIAbility';
import type Want from '@ohos.app.ability.Want';
import type AbilityConstant from '@ohos.app.ability.AbilityConstant';
import type window from '@ohos.window';
import { CacoLogger } from '../common/CacoLogger';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    CacoLogger.info('EntryAbility created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error, data) => {
      if (error.code) {
        CacoLogger.error(`Failed to load Index page: ${JSON.stringify(error)}`);
        return;
      }

      CacoLogger.info(`Index page loaded: ${JSON.stringify(data)}`);
    });
  }
}
