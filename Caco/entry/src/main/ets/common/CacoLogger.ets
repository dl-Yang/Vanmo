export class CacoLogger {
  static info(message: string): void {
    console.info(`[Caco] ${message}`);
  }

  static warn(message: string): void {
    console.warn(`[Caco] ${message}`);
  }

  static error(message: string): void {
    console.error(`[Caco] ${message}`);
  }
}
