import { CacoError, CacoErrorCode } from '../../common/CacoError';

export interface HttpRequestOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string | ArrayBuffer;
}

export class HttpClient {
  async requestText(uri: string, options: HttpRequestOptions = {}): Promise<string> {
    const response = await fetch(uri, {
      method: options.method ?? 'GET',
      headers: options.headers,
      body: options.body
    });

    if (!response.ok) {
      throw new CacoError(CacoErrorCode.Network, `HTTP ${response.status} for ${uri}`);
    }

    return await response.text();
  }

  async requestJson<T>(uri: string, options: HttpRequestOptions = {}): Promise<T> {
    const text = await this.requestText(uri, options);
    return JSON.parse(text) as T;
  }
}

export const httpClient = new HttpClient();
