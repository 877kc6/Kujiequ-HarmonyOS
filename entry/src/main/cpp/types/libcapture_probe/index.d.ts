export interface ProbeResult {
  code: number;
  packets: number;
  bytes: number;
}
export const run: (fd: number, marker: string) => Promise<ProbeResult>;
export const cancel: () => void;

export const runTcp: (fd: number, marker: string) => Promise<ProbeResult>;

export const prepareInternet: () => number;
export const closeInternet: () => void;
export const runInternet: (fd: number, marker: string) => Promise<ProbeResult>;

export const runHttps: (fd: number, marker: string) => Promise<ProbeResult>;
export const confirmHttps: () => void;
