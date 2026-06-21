import type { PlayerEngine } from './PlayerEngine';
import { IjkPlayerEngine } from './IjkPlayerEngine';
import { SystemPlayerEngine } from './SystemPlayerEngine';

const systemExtensions: string[] = ['mp4', 'mov', 'm4v'];

export enum PlayerEngineType {
  System = 'system',
  Ijk = 'ijk'
}

export class PlayerEngineFactory {
  static engineTypeForUri(uri: string): PlayerEngineType {
    const extension = uri.split('?')[0].split('.').pop()?.toLowerCase() ?? '';
    return systemExtensions.includes(extension) ? PlayerEngineType.System : PlayerEngineType.Ijk;
  }

  static make(uri: string): PlayerEngine {
    return this.engineTypeForUri(uri) === PlayerEngineType.System ?
      new SystemPlayerEngine() :
      new IjkPlayerEngine();
  }
}
