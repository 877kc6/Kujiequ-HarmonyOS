export interface ProbeResult {
  code: number;
  packets: number;
  bytes: number;
}
export const run: (fd: number, marker: string) => Promise<ProbeResult>;
export const cancel: () => void;
