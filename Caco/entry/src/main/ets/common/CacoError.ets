export enum CacoErrorCode {
  Unknown = 'unknown',
  Network = 'network',
  Persistence = 'persistence',
  Authentication = 'authentication',
  UnsupportedFormat = 'unsupportedFormat',
  Player = 'player',
  Permission = 'permission'
}

export class CacoError extends Error {
  readonly code: CacoErrorCode;
  readonly recoverySuggestion?: string;

  constructor(code: CacoErrorCode, message: string, recoverySuggestion?: string) {
    super(message);
    this.code = code;
    this.recoverySuggestion = recoverySuggestion;
  }
}
