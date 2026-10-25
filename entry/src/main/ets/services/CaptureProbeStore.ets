import { fileIo } from '@kit.CoreFileKit';
import { ProbeRequest, ProbeStatus } from './CaptureProbeModel';

// VPN extensions may live in a different process. AppStorage is NOT IPC.
// Only two small files in this app's private filesDir are used; no packets/tokens.
export class CaptureProbeStore {
  private filesDir: string;
  constructor(filesDir: string) {
    this.filesDir = filesDir;
  }
  private write(name: string, text: string): void {
    const path = this.filesDir + '/' + name;
    const temporary = path + '.tmp';
    const file = fileIo.openSync(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try { fileIo.writeSync(file.fd, text); } finally { fileIo.closeSync(file); }
    fileIo.renameSync(temporary, path);
  }
  request(): ProbeRequest | undefined {
    try { return JSON.parse(fileIo.readTextSync(this.filesDir + '/capture_probe_request.json')) as ProbeRequest; }
    catch (_) { return undefined; }
  }
  status(): ProbeStatus | undefined {
    try { return JSON.parse(fileIo.readTextSync(this.filesDir + '/capture_probe_status.json')) as ProbeStatus; }
    catch (_) { return undefined; }
  }
  writeRequest(request: ProbeRequest): void { this.write('capture_probe_request.json', JSON.stringify(request)); }
  writeStatus(status: ProbeStatus): void { this.write('capture_probe_status.json', JSON.stringify(status)); }
  cancel(runId: string): void {
    const request = this.request();
    if (request?.runId === runId) { request.cancelled = true; this.writeRequest(request); }
  }
}
