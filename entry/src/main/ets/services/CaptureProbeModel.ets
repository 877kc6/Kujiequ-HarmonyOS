export interface ProbeRequest {
  runId: string;
  expiresAt: number;
  cancelled: boolean;
}
export interface ProbeStatus {
  runId: string;
  phase: string;
  code: number;
  packets: number;
  bytes: number;
  cleaned: boolean;
  updatedAt: number;
}
export function validProbeRequest(request: ProbeRequest, runId: string, now: number): boolean {
  return !!request && /^[a-fA-F0-9-]{36}$/.test(runId) && request.runId === runId &&
    request.cancelled === false && Number.isFinite(request.expiresAt) &&
    request.expiresAt > now && request.expiresAt <= now + 90000;
}
export function validProbeStatus(status: ProbeStatus, runId: string): boolean {
  return !!status && status.runId === runId &&
    ['preparing', 'reading', 'passed', 'no_packet', 'failed', 'cancelled', 'cleanup_failed'].includes(status.phase) &&
    Number.isFinite(status.code) && Number.isFinite(status.packets) && Number.isFinite(status.bytes) &&
    status.packets >= 0 && status.bytes >= 0 && typeof status.cleaned === 'boolean' && Number.isFinite(status.updatedAt);
}
export function probeTerminal(phase: string): boolean {
  return ['passed', 'no_packet', 'failed', 'cancelled', 'cleanup_failed'].includes(phase);
}
export function probeLabel(phase: string): string {
  switch (phase) {
    case 'starting': return '正在请求启动系统 VPN';
    case 'waiting_extension': return '系统调用已返回，等待扩展启动';
    case 'authorizing': return '等待系统 VPN 授权';
    case 'preparing': return '正在创建诊断网卡';
    case 'reading': return '正在发送并核对测试包';
    case 'passed': return '测试包已捕获，诊断网卡已清理';
    case 'no_packet': return '未收到匹配测试包，诊断网卡已清理';
    case 'failed': return '诊断未通过';
    case 'cancelled': return '诊断已取消';
    case 'cleanup_failed': return '网卡清理未确认，请在系统中关闭此 VPN';
    case 'stopping': return '正在停止，等待清理回执';
    case 'unconfirmed': return '未收到完整回执，请检查系统 VPN 状态';
    default: return '尚未运行';
  }
}
