import { UiTheme } from '../services/UiTheme';
import { Role, WidgetData, Gauge, SignInfo } from '../models/Models';
import { KuroApi } from '../services/KuroApi';
import { Session } from '../services/Session';

@Component
export struct GameData {
  @StorageLink('immersiveEnabled') materialEnabled: boolean = true;
  @StorageLink('materialThickness') materialThickness: number = 2;
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @Prop @Watch('onRefreshVersion') refreshVersion: number = 0;
  @State accountConnected: boolean = false;
  @State roles: Role[] = [];
  @State selected: number = 0;
  @State gameId: number = 3;
  @State data: WidgetData = {};
  @State info: SignInfo = { isSigIn: false, sigInNum: 0 };
  @State infoReady: boolean = false;
  @State busy: boolean = false;
  @State signing: boolean = false;
  @State message: string = '';
  private sequence: number = 0;
  private loadedAt: number = 0;
  private loadedAccount: string = '';
  onScrollDirection: (hidden: boolean) => void = (_hidden: boolean): void => {};
  private scrollDistance: number = 0;
  private scrollNavigation(offset: number): void {
    if ((offset > 0) !== (this.scrollDistance > 0)) { this.scrollDistance = 0; }
    this.scrollDistance += offset;
    if (Math.abs(this.scrollDistance) > 18) { this.onScrollDirection(this.scrollDistance > 0); this.scrollDistance = 0; }
  }
  private onRefreshVersion(): void { if (!this.signing && (this.loadedAccount !== Session.userId || Date.now() - this.loadedAt > 60000)) { this.load(); } }
  aboutToAppear(): void { this.onRefreshVersion(); }
  aboutToDisappear(): void { this.sequence++; this.busy = false; }
  private async load(): Promise<void> {
    if (this.busy) { return; }
    const seq = ++this.sequence;
    this.accountConnected = Session.token.length > 0; this.message = '';
    if (!this.accountConnected) { this.roles = []; this.data = {}; this.infoReady = false; this.busy = false; return; }
    if (this.loadedAccount !== Session.userId) { this.data = {}; this.roles = []; this.infoReady = false; }
    this.busy = true;
    try {
      const roles = await KuroApi.roles(this.gameId);
      if (seq !== this.sequence) { return; }
      const previous = this.roles[this.selected]?.roleId;
      this.roles = roles ?? [];
      const index = this.roles.findIndex((item: Role): boolean => item.roleId === previous);
      this.selected = index >= 0 ? index : 0;
      if (this.roles.length > 0) { await this.loadRole(seq); }
    } catch (e) { if (seq === this.sequence) { this.message = (e as Error).message; } }
    finally { if (seq === this.sequence) { this.busy = false; } }
  }
  private async loadRole(seq: number): Promise<void> {
    const role = this.roles[this.selected];
    if (!role) { return; }
    let nextData: WidgetData | undefined = undefined;
    let nextInfo: SignInfo | undefined = undefined;
    const errors: string[] = [];
    const dataTask = KuroApi.widget(role).then((result: WidgetData): void => { nextData = result; })
      .catch((e: Error): void => { errors.push('游戏数据：' + e.message); });
    const signTask = KuroApi.signInfo(role).then((result: SignInfo): void => { nextInfo = result; })
      .catch((e: Error): void => { errors.push('签到状态：' + e.message); });
    await Promise.all([dataTask, signTask]);
    if (seq !== this.sequence) { return; }
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseInOut }, () => {
      if (nextData) { this.data = nextData; }
      if (nextInfo) { this.info = nextInfo; this.infoReady = true; }
      else { this.infoReady = false; }
      this.message = errors.join('\n');
    });
    this.loadedAt = Date.now(); this.loadedAccount = Session.userId;
  }

  private async cycleRole(): Promise<void> {
    if (this.busy || this.signing || this.roles.length === 0) { return; }
    this.data = {}; this.infoReady = false;
    this.selected = (this.selected + 1) % this.roles.length; const seq = ++this.sequence;
    this.busy = true; this.message = ''; try { await this.loadRole(seq); } finally { if (seq === this.sequence) { this.busy = false; } }
  }
  private async sign(): Promise<void> {
    if (this.signing || this.busy || !this.infoReady || this.info.isSigIn || !this.roles[this.selected]) { return; }
    this.signing = true;
    const role = this.roles[this.selected];
    try {
      await KuroApi.sign(role);
      this.info = { isSigIn: true, sigInNum: this.info.sigInNum + 1 };
      this.message = '签到成功，奖励请在游戏中查收';
    } catch (e) {
      this.message = (e as Error).message;
      // A timed-out mutation may have committed. Reconcile via a read, never retry automatically.
      try { const info = await KuroApi.signInfo(role); if (info) { this.info = info; this.infoReady = true; } } catch (_) { this.infoReady = false; }
    } finally { this.signing = false; }
  }
  @Builder
  gauge(value: Gauge, accent: string) {
    Column({ space: 7 }) {
      Row() {
        Text(value.name).fontColor(UiTheme.secondary(this.darkTheme)).fontSize(13).fontWeight(FontWeight.Medium)
        Blank()
        if (value.cur !== undefined && value.cur !== null && value.total && value.total > 0 && value.cur >= value.total) {
          Text('已满').fontColor(accent).fontSize(11).fontWeight(FontWeight.Medium)
        }
      }.width('100%')
      Text(value.cur === undefined || value.cur === null ? '—' : `${value.cur} / ${value.total ?? '—'}`)
        .fontSize(23).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
      if (value.cur !== undefined && value.cur !== null && value.total && value.total > 0) {
        Progress({ value: value.cur, total: value.total, type: ProgressType.Linear }).style({ strokeWidth: 4, enableSmoothEffect: true }).color(accent).width('100%')
      }
      if (value.refreshTimeStamp && value.refreshTimeStamp > 0) {
        Text('回满 ' + new Date(value.refreshTimeStamp * 1000).toLocaleString()).fontSize(10).fontColor(UiTheme.muted(this.darkTheme))
      }
    }.padding({ left: 15, right: 15, top: 12, bottom: 12 }).backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(16)
      .width('100%').alignItems(HorizontalAlign.Start)
  }
  build() {
    Stack() {
    Scroll() {
      Column({ space: 11 }) {
        Row() {
          Column({ space: 3 }) {
            Text('数据终端').fontSize(26).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
            Text('游戏数据 · 每日签到').fontSize(12).fontColor(UiTheme.muted(this.darkTheme))
          }.alignItems(HorizontalAlign.Start)
          Blank()
          Stack() { if (this.busy) { LoadingProgress().width(18).height(18) } }.width(22).height(22)
          Button(this.gameId === 3 ? '鸣潮  ▾' : '战双  ▾').constraintSize({ minHeight: 40 }).backgroundColor('#16D9C9').fontColor('#29251A').fontSize(13).fontWeight(FontWeight.Medium).enabled(!this.busy && !this.signing)
            .onClick(() => { this.gameId = this.gameId === 3 ? 2 : 3; this.roles = []; this.data = {}; this.infoReady = false; this.load(); }).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
        }.width('100%')
        if (!this.accountConnected) {
          Column({ space: 12 }) {
            Text('连接库街区账号').fontColor(UiTheme.primary(this.darkTheme)).fontSize(17).fontWeight(FontWeight.Bold)
            Text('登录后同步绑定角色、游戏数据和签到状态。').fontColor(UiTheme.secondary(this.darkTheme)).fontSize(13).width('100%')
            Button('登录库街区').constraintSize({ minHeight: 44 }).fontColor('#29251A').backgroundColor('#16D9C9').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' })).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
          }.padding(18).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18).alignItems(HorizontalAlign.Start)
        } else {
          if (this.busy && this.roles.length === 0) {
            ForEach([0, 1, 2, 3], (index: number) => {
              Column({ space: 10 }) {
                Row().width('36%').height(10).backgroundColor(UiTheme.control(this.darkTheme)).borderRadius(5)
                Row().width('62%').height(20).backgroundColor(UiTheme.control(this.darkTheme)).borderRadius(6)
                Row().width('100%').height(4).backgroundColor(UiTheme.control(this.darkTheme)).borderRadius(2)
              }.alignItems(HorizontalAlign.Start).padding(15).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(16)
            }, (index: number): string => 'loading_' + index)
          }
          if (this.roles.length > 0) {
            Row() {
              Column({ space: 5 }) {
                Text('当前角色').fontSize(11).fontColor('#C8C3B4')
                Text(this.roles[this.selected].roleName).fontSize(19).fontColor('#FFFFFF').fontWeight(FontWeight.Bold).maxLines(1)
                Text(`UID ${this.roles[this.selected].roleId}  ·  ${this.roles[this.selected].serverName}`).fontSize(11).fontColor('#D4D1C8').maxLines(1)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (this.roles.length > 1) {
                Button('切换').constraintSize({ minHeight: 38 }).fontSize(12).fontColor('#F4D77A').backgroundColor('#3E4139')
                  .onClick(() => this.cycleRole()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
              }
            }.width('100%').padding({ left: 17, right: 13, top: 14, bottom: 14 }).backgroundColor('#30352F').borderRadius(18)
            if (this.data.energyData) { this.gauge(this.data.energyData, '#D6AE43') }
            if (this.data.livenessData) { this.gauge(this.data.livenessData, '#72A896') }
            if (this.data.storeEnergyData) { this.gauge(this.data.storeEnergyData, '#8F9FD0') }
            if (this.data.towerData) { this.gauge(this.data.towerData, '#C18A68') }
            if (this.data.weeklyData) { this.gauge(this.data.weeklyData, '#8F9FD0') }
            Row() {
              Column({ space: 6 }) {
                Text(this.infoReady ? (this.info.isSigIn ? '今日已签到' : '每日签到') : '签到状态待确认').fontColor(UiTheme.primary(this.darkTheme)).fontSize(15).fontWeight(FontWeight.Bold)
                Text(this.infoReady ? `本月累计 ${this.info.sigInNum ?? 0} 天` : '刷新数据后查看').fontSize(11).fontColor(UiTheme.muted(this.darkTheme))
              }.alignItems(HorizontalAlign.Start)
              Blank()
              Button(this.signing ? '提交中…' : (this.info.isSigIn && this.infoReady ? '已签到' : '立即签到')).constraintSize({ minHeight: 40 })
                .enabled(this.infoReady && !this.info.isSigIn && !this.signing && !this.busy).backgroundColor(this.infoReady && this.info.isSigIn ? '#EAF2ED' : '#16D9C9')
                .fontColor(this.infoReady && this.info.isSigIn ? '#54836D' : '#29251A').fontSize(13).fontWeight(FontWeight.Medium)
                .onClick(() => this.sign()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
            }.padding({ left: 15, right: 12, top: 12, bottom: 12 }).width('100%').backgroundColor(this.darkTheme ? '#FF2D2A22' : '#FFFFFDF7').borderRadius(16)
              .border({ width: 1, color: this.darkTheme ? '#FF524832' : '#F0E7D1' })
          } else if (!this.busy) {
            Column({ space: 8 }) {
              Text('还没有绑定角色').fontSize(16).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
              Text('请先在官方库街区绑定游戏角色，再回来刷新数据。').fontColor(UiTheme.secondary(this.darkTheme)).fontSize(12).width('100%')
            }.padding(17).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18).alignItems(HorizontalAlign.Start)
          }
          Button('刷新数据').constraintSize({ minHeight: 40 }).enabled(!this.busy && !this.signing).fontSize(13)
            .fontColor(UiTheme.secondary(this.darkTheme)).backgroundColor(UiTheme.control(this.darkTheme)).onClick(() => this.load()).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
        }
        if (this.message) { Text(this.message).fontSize(12).fontColor(UiTheme.errorText(this.darkTheme)).width('100%').padding(11).backgroundColor(UiTheme.errorSurface(this.darkTheme)).borderRadius(12) }
        Text('签到按中国时区结算 · 接口异常时请前往官方入口确认').fontColor('#9AA1AA').fontSize(10).width('100%').textAlign(TextAlign.Center)
      }.padding({ left: 18, right: 18, top: 15, bottom: 120 }).width('100%')
    }.onScroll((xOffset: number, yOffset: number) => this.scrollNavigation(yOffset)).onScrollEdge((edge: Edge) => { if (edge === Edge.Top) { this.onScrollDirection(false); } }).align(Alignment.TopStart).width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme))
    }.width('100%').height('100%')
  }
}
