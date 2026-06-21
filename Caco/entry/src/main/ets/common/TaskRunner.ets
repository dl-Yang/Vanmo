export type AsyncTask<T> = () => Promise<T>;

export class TaskRunner {
  static async run<T>(label: string, task: AsyncTask<T>): Promise<T> {
    // Heavy scans and XML parsing will move to TaskPool after the PoC validates
    // the exact serialization boundaries for HarmonyOS worker tasks.
    return await task();
  }
}
