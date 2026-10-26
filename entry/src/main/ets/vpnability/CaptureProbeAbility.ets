import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { run, runTcp, runInternet, runHttps, confirmHttps, prepareInternet, closeInternet, cancel } from 'libcapture_probe.so';
import { CaptureProbeStore } from '../services/CaptureProbeStore';
import { ProbeStatus, validProbeRequest } from '../services/CaptureProbeModel';

export default class CaptureProbeAbility extends VpnExtensionAbility {
  private stopped: boolean = false;
  private monitor: number = -1;
  private store?: CaptureProbeStore;
  private runId: string = '';
  private connection?: vpnExtension.VpnConnection;
  private status: ProbeStatus = { runId: '', phase: 'preparing', code: 0, packets: 0, bytes: 0, cleaned: false, updatedAt: 0 };

  onCreate(want: Want): void {
    this.store = new CaptureProbeStore(this.context.filesDir);
    const id = want.parameters?.probeRunId;
    this.runId = typeof id === 'string' ? id : '';
    this.status.runId = this.runId;
    this.execute();
  }
  onDestroy(): void {
    this.stopped = true;
    cancel();
    if (this.monitor >= 0) { clearInterval(this.monitor); this.monitor = -1; }
    // execute owns the create -> native read -> destroy sequence. Never race
    // destroy against a pending create, which could leave a late-created VPN.
  }
  private allowed(): boolean {
    const request = this.store?.request();
    return !this.stopped && !!request && validProbeRequest(request, this.runId, Date.now());
  }
  private publish(): void {
    this.status.updatedAt = Date.now();
    this.store?.writeStatus(this.status);
  }
  private async execute(): Promise<void> {
    let created = false;
    try {
      if (!this.allowed()) { this.status.phase = 'cancelled'; return; }
      const mode = this.store?.request()?.mode;
      this.status.mode = mode === 'https' ? 'https' : mode === 'internet' ? 'internet' : (mode === 'tcp' ? 'tcp' : 'udp');
      this.publish();
      this.connection = vpnExtension.createVpnConnection(this.context);
      const bundleName = this.context.applicationInfo.name;
      if (!bundleName) { throw new Error('Missing own application identity'); }
      const config: vpnExtension.VpnConfig = {
        addresses: [{ address: { address: '198.18.0.1', family: 1 }, prefixLength: 30 }],
        routes: [{ interface: '', destination: { address: { address: '198.18.0.2', family: 1 }, prefixLength: 32 },
          gateway: { address: '0.0.0.0', family: 1 }, hasGateway: false, isDefaultRoute: false }],
        mtu: 1400, isIPv4Accepted: true, isIPv6Accepted: false, isBlocking: false,
        trustedApplications: [bundleName]
      };
      const fd = await this.connection.create(config);
      created = true;
      if (!this.allowed()) { this.status.phase = 'cancelled'; return; }
      if ((this.status.mode === 'internet' || this.status.mode === 'https')) {
        const upstreamFd = prepareInternet();
        await this.connection.protect(upstreamFd);
        if (!this.allowed()) { this.status.phase = 'cancelled'; return; }
      }
      this.status.phase = 'reading'; this.publish();
      this.monitor = setInterval(() => {
        if (!this.allowed()) { this.stopped = true; cancel(); }
        else if (this.status.mode === 'https' && this.store?.request()?.httpsPassed === true) { confirmHttps(); }
      }, 100);
      const result = this.status.mode === 'https' ? await runHttps(fd, 'kujiequ_https:' + this.runId) : this.status.mode === 'internet' ? await runInternet(fd, 'kujiequ_internet:' + this.runId) : this.status.mode === 'tcp' ?
        await runTcp(fd, 'kujiequ_tcp:' + this.runId) : await run(fd, 'kujiequ_probe:' + this.runId);
      this.status.code = result.code; this.status.packets = result.packets; this.status.bytes = result.bytes;
      this.status.phase = !this.allowed() || result.code === 2 ? 'cancelled' :
        (result.code === 0 ? 'passed' : (result.code === 1 ? (result.packets > 0 ? 'incomplete' : 'no_packet') : 'failed'));
    } catch (error) {
      this.status.phase = this.stopped ? 'cancelled' : 'failed';
      const code = (error as BusinessError).code;
      this.status.code = typeof code === 'number' ? code : -1;
    } finally {
      if (this.monitor >= 0) { clearInterval(this.monitor); this.monitor = -1; }
      cancel();
      closeInternet();
      // Destroy even when create rejected: the system may have partially set up.
      try {
        if (this.connection) { await this.connection.destroy(); }
        this.status.cleaned = true;
      } catch (_) {
        this.status.cleaned = false;
        this.status.phase = 'cleanup_failed';
      }
      if (!created && this.status.phase === 'passed') { this.status.phase = 'failed'; }
      // Publish only to this run; do not overwrite a newer test's report.
      try { if (this.store?.request()?.runId === this.runId) { this.publish(); } } catch (_) {}
      try {
        await vpnExtension.stopVpnExtensionAbility({ bundleName: this.context.applicationInfo.name, abilityName: 'CaptureProbeAbility' });
      } catch (_) { /* VPN destruction above is separately reported. */ }
    }
  }
}
