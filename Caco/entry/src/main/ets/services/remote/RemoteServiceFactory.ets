import { CacoError, CacoErrorCode } from '../../common/CacoError';
import { ConnectionType } from '../../domain/Connection';
import type { RemoteFileService } from './RemoteFileService';
import { EmbyService } from './EmbyService';
import { JellyfinService } from './JellyfinService';
import { LocalFolderService } from './LocalFolderService';
import { PlexService } from './PlexService';
import { SmbService } from './SmbService';
import { WebDavService } from './WebDavService';

export class RemoteServiceFactory {
  static make(type: ConnectionType): RemoteFileService {
    switch (type) {
      case ConnectionType.LocalFolder:
        return new LocalFolderService();
      case ConnectionType.Smb:
        return new SmbService();
      case ConnectionType.WebDav:
        return new WebDavService();
      case ConnectionType.Emby:
        return new EmbyService();
      case ConnectionType.Jellyfin:
        return new JellyfinService();
      case ConnectionType.Plex:
        return new PlexService();
      default:
        throw new CacoError(CacoErrorCode.Network, `${type} is not part of the HarmonyOS MVP`);
    }
  }
}
