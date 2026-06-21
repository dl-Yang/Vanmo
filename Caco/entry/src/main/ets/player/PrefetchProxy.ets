import { CacoError, CacoErrorCode } from '../common/CacoError';

export interface StreamRange {
  start: number;
  end?: number;
}

export interface RemoteRangeFetcher {
  contentLength(streamId: string): Promise<number | undefined>;
  fetchRange(streamId: string, range: StreamRange): Promise<ArrayBuffer>;
}

export interface PrefetchSession {
  streamId: string;
  sourceUri: string;
  createdAt: number;
}

export class PrefetchProxy {
  private readonly sessions: Map<string, PrefetchSession> = new Map();

  register(sourceUri: string): PrefetchSession {
    const streamId = `${Date.now()}-${this.sessions.size}`;
    const session: PrefetchSession = {
      streamId,
      sourceUri,
      createdAt: Date.now()
    };
    this.sessions.set(streamId, session);
    return session;
  }

  localUriFor(session: PrefetchSession): string {
    return `http://127.0.0.1:0/stream/${session.streamId}`;
  }

  resolve(streamId: string): PrefetchSession {
    const session = this.sessions.get(streamId);
    if (!session) {
      throw new CacoError(CacoErrorCode.Network, `Prefetch session not found: ${streamId}`);
    }

    return session;
  }
}

export const prefetchProxy = new PrefetchProxy();
