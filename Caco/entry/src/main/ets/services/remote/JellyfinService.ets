import { ConnectionType } from '../../domain/Connection';
import { EmbyService } from './EmbyService';

export class JellyfinService extends EmbyService {
  constructor() {
    super(ConnectionType.Jellyfin);
  }
}
