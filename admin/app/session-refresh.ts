export class RefreshCoordinator<T> {
  private readonly pending = new Map<string, Promise<T>>();

  run(key: string, refresh: () => Promise<T>): Promise<T> {
    const existing = this.pending.get(key);
    if (existing) return existing;

    const operation = Promise.resolve()
      .then(refresh)
      .finally(() => {
        if (this.pending.get(key) === operation) {
          this.pending.delete(key);
        }
      });
    this.pending.set(key, operation);
    return operation;
  }

  clear(key: string) {
    this.pending.delete(key);
  }

  has(key: string) {
    return this.pending.has(key);
  }
}

export function shouldExpireSessionAfterRefresh(status?: number) {
  return status === 401 || status === 403;
}
