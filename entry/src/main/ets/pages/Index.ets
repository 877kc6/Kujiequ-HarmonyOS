import { router } from '@kit.ArkUI';
import { SafePage } from '../components/SafePage';
import { UiTheme } from '../services/UiTheme';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { Feed } from '../components/Feed';
import { GameData } from '../components/GameData';
import { LocalStore } from '../services/LocalStore';
import { Session } from '../services/Session';
import { KuroApi } from '../services/KuroApi';
import { Profile, SavedPost } from '../models/Models';

@Entry
@Component
struct Index {
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @StorageLink('immersiveEnabled') materialEnabled: boolean = true;
  @StorageLink('materialLevel') materialLevel: string = 'ADAPTIVE';
  @StorageLink('materialThickness') materialThickness: number = 2;
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @StorageLink('autoSignIn') autoSignIn: boolean = true;
  private composeOpening: boolean = false;
  private controller: HdsTabsController = new HdsTabsController();
  @StorageLink('safeBottom') safeBottom: number = 0;
  @State saved: SavedPost[] = [];
  @State hubMode: number = 0;
  @State profile: Profile = { userId: '', userName: '', headUrl: '' };
  @State loggedIn: boolean = false;
  @State version: number = 0;
  @State navigationHidden: boolean = false;
  private navigationDistance: number = 0;
  private setNavigationHidden(hidden: boolean): void {
    if (this.navigationHidden === hidden) { return; }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseInOut }, () => { this.navigationHidden = hidden; });
  }
  private scrollNavigation(offset: number): void {
    if ((offset > 0) !== (this.navigationDistance > 0)) { this.navigationDistance = 0; }
    this.navigationDistance += offset;
    if (Math.abs(this.navigationDistance) > 18) { this.setNavigationHidden(this.navigationDistance > 0); this.navigationDistance = 0; }
  }
  @State message: string = '';

  private profileAt: number = 0;
  private refreshSequence: number = 0;
  private profileBusy: boolean = false;
  private autoSignAccount: string = '';
  private lastBackAt: number = 0;
  onBackPress(): boolean {
    const now = Date.now();
    if (now - this.lastBackAt < 2000) { return false; }
    this.lastBackAt = now;
    this.getUIContext().getPromptAction().showToast({ message: '再返回一次退出库街区' });
    return true;
  }
  onPageShow(): void { this.composeOpening = false; this.profileAt = 0; this.refresh(); this.autoSignOnLaunch(); }
  private openCompose(): void {
    if (this.composeOpening) { return; }
    this.composeOpening = true;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Compose', params: { gameId: AppStorage.get<number>('feedGameId') || 3 } }, router.RouterMode.Single)
      .catch(() => { this.composeOpening = false; this.message = '编辑器打开失败，请重试'; });
  }
  private async autoSignOnLaunch(): Promise<void> {
    const userId = Session.userId;
    if (!this.autoSignIn || !Session.token || !userId || this.autoSignAccount === userId) { return; }
    this.autoSignAccount = userId;
    try {
      const roles = await KuroApi.roles(3);
      const role = roles && roles.length > 0 ? roles[0] : undefined;
      if (!role || userId !== Session.userId) { return; }
      const info = await KuroApi.signInfo(role);
      if (userId !== Session.userId || info.isSigIn) { return; }
      const chinaDay = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
      const attempt = `${userId}|3|${role.roleId}|${chinaDay}`;
      if (LocalStore.hasAutoSignAttempt(attempt)) { return; }
      await LocalStore.markAutoSignAttempt(attempt);
      if (userId !== Session.userId) { return; }
      try {
        await KuroApi.sign(role);
        const verified = await KuroApi.signInfo(role);
        if (verified.isSigIn) { this.getUIContext().getPromptAction().showToast({ message: '鸣潮今日签到完成' }); }
        else { this.getUIContext().getPromptAction().showToast({ message: '签到已提交，服务器尚未确认；今天不会自动重试' }); }
      } catch (_) {
        try {
          const verified = await KuroApi.signInfo(role);
          if (verified.isSigIn) { this.getUIContext().getPromptAction().showToast({ message: '鸣潮今日签到完成' }); }
          else { this.getUIContext().getPromptAction().showToast({ message: '签到结果未确认，今天不会自动重试' }); }
        } catch (_) { this.getUIContext().getPromptAction().showToast({ message: '签到状态暂时无法确认，今天不会自动重试' }); }
      }
    } catch (_) { /* Never sign unless login, role data and server status were read successfully. */ }
  }
  private async refresh(): Promise<void> {
    this.loggedIn = Session.token.length > 0; this.version++;
    const seq = ++this.refreshSequence;
    const userId = Session.userId;
    if (this.profile.userId !== userId) {
      this.profile = { userId: userId, userName: Session.userName, headUrl: '' };
      this.profileAt = 0;
      try { const cached = await LocalStore.profile(userId); if (cached && seq === this.refreshSequence) { this.profile = cached; } } catch (_) {}
    }
    this.message = AppStorage.get<string>('bootMessage') ?? '';
    try { this.saved = await LocalStore.saved(); } catch (e) { this.message = (e as Error).message; }
    if (this.loggedIn && !this.profileBusy && Date.now() - this.profileAt > 60000) {
      this.profileBusy = true;
      try {
        const data = await KuroApi.profile();
        if (data?.mine && userId === Session.userId) {
          this.profile = data.mine; this.profileAt = Date.now(); await LocalStore.saveProfile(data.mine);
        }
      } catch (e) { if (userId === Session.userId) { this.message = (e as Error).message; } }
      finally { this.profileBusy = false; }
    }
  }

  private async logout(): Promise<void> {
    try { await Session.logout(); this.autoSignAccount = ''; this.refresh(); }
    catch (e) { this.message = (e as Error).message; }
  }
  private openAccountList(kind: string): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/AccountList', params: { kind: kind } });
  }
  @Builder
  hubEntry(label: string, kind: string, hint: string) {
    Row({ space: 10 }) {
      Column({ space: 5 }) {
        Text(label).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme))
        Text(hint).fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(24).fontColor(UiTheme.muted(this.darkTheme))
    }.padding(16).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(16)
      .onClick(() => this.openAccountList(kind))
  }
  @Builder
  dynamic() {
    Column({ space: 12 }) {
      Row() {
        Text('动态').fontSize(26).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
        Blank()
        Text('关注与消息').fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
      }.width('100%').padding({ left: 20, right: 20, top: 12 })
      Row({ space: 8 }) {
        Button('关注与消息').fontColor(this.hubMode === 0 ? '#122828' : UiTheme.primary(this.darkTheme)).backgroundColor(this.hubMode === 0 ? '#16D9C9' : UiTheme.surface(this.darkTheme)).height(44).onClick(() => this.hubMode = 0)
        Button('本机收藏').fontColor(this.hubMode === 1 ? '#122828' : UiTheme.primary(this.darkTheme)).backgroundColor(this.hubMode === 1 ? '#16D9C9' : UiTheme.surface(this.darkTheme)).height(44).onClick(() => this.hubMode = 1)
      }.width('100%').padding({ left: 20, right: 20 })
      if (this.hubMode === 1) { Column() { this.favorites() }.width('100%').layoutWeight(1) }
      else {
        Scroll() {
          Column({ space: 10 }) {
            Text('关注、互动与收藏，都在这里。').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
            Row({ space: 10 }) {
              Column() { this.hubEntry('关注动态', 'following', '关注用户的新内容') }.layoutWeight(1)
              Column() { this.hubEntry('评论和回复', 'comments', '收到的互动') }.layoutWeight(1)
            }.width('100%')
            Row({ space: 10 }) {
              Column() { this.hubEntry('点赞', 'likes', '喜欢你的分享') }.layoutWeight(1)
              Column() { this.hubEntry('@我的', 'mentions', '被提及的内容') }.layoutWeight(1)
            }.width('100%')
            Row({ space: 10 }) {
              Column() { this.hubEntry('粉丝', 'fans', '查看粉丝列表') }.layoutWeight(1)
              Column() { this.hubEntry('历史评论', 'historyComments', '我发出的评论') }.layoutWeight(1)
            }.width('100%')
            Row({ space: 10 }) {
              Column() { this.hubEntry('官方收藏', 'collects', '账号收藏内容') }.layoutWeight(1)
              Column() { this.hubEntry('系统消息', 'system', '社区通知') }.layoutWeight(1)
            }.width('100%')
          }.padding({ left: 20, right: 20, bottom: 110 }).width('100%')
        }.layoutWeight(1).width('100%').onScroll((x: number, y: number) => this.scrollNavigation(y))
      }
    }.width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme))
  }
  @Builder
  favorites() {
    Stack() {
    Column({ space: 16 }) {
      Text('我的收藏').fontSize(28).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
      Text('保存在本机 · 不与官方收藏同步 · 最多 300 条').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
      if (this.saved.length === 0) { Text('在帖子详情点击收藏，把喜欢的内容留在这里。').fontSize(14).fontColor(UiTheme.secondary(this.darkTheme)).padding(30) }
      List({ space: 12 }) {
        ForEach(this.saved, (item: SavedPost) => {
          ListItem() {
            Column({ space: 8 }) {
              Text(item.postTitle || '社区动态').fontSize(18).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).width('100%')
              Text(`${item.gameId === 2 ? '战双帕弥什' : '鸣潮'} · ${item.userName}`).fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).width('100%')
            }.padding(20).backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18).width('100%')
              .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Post', params: { postId: item.postId } }))
          }
        }, (item: SavedPost): string => item.postId)
        ListItem() { Row().width('100%').height(110) }
      }.onScroll((scrollOffset: number, scrollState: ScrollState) => this.scrollNavigation(scrollOffset)).onReachStart(() => this.setNavigationHidden(false)).layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 20 }).backgroundColor(UiTheme.page(this.darkTheme))
    }.width('100%').height('100%')
  }
  @Builder
  account() {
    Stack() {
        Scroll() {
        Column({ space: 16 }) {
          Row() {
            Text('我的').fontSize(25).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
            Blank()
            Button('设置').constraintSize({ minHeight: 44 }).fontSize(13).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
              .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' }))
          }.width('100%')
          Row({ space: 15 }) {
            Stack() {
              Text('库').fontSize(25).fontColor('#138C83')
              if (this.profile.headUrl) { Image(this.profile.headUrl).width(64).height(64).borderRadius(32).objectFit(ImageFit.Cover) }
            }.width(64).height(64).borderRadius(32).backgroundColor('#DFFBF6')
            Column({ space: 7 }) {
              Text(this.loggedIn ? this.profile.userName || '库街区用户' : '立即登录').fontSize(22).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
              Text(this.loggedIn ? `ID ${this.profile.userId}` : '登录查看更多精彩内容').fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
              if (this.profile.signature && this.loggedIn) { Text(this.profile.signature).fontSize(12).fontColor(UiTheme.muted(this.darkTheme)).maxLines(2) }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%').padding({ top: 12, bottom: 18 }).onClick(() => { this.getUIContext().getRouter().pushUrl({url:this.loggedIn ? 'pages/UserProfile' : 'pages/Login',params:{userId:Session.userId}}); })
          Row({ space: 12 }) {
            Button(this.loggedIn ? `${this.profile.followCount === undefined ? '—' : this.profile.followCount}  关注` : '关注').height(48).layoutWeight(1).fontSize(15)
              .fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.openAccountList('follows'))
            Button(this.loggedIn ? `${this.profile.fansCount === undefined ? '—' : this.profile.fansCount}  粉丝` : '粉丝').height(48).layoutWeight(1).fontSize(15)
              .fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme)).onClick(() => this.openAccountList('fans'))
          }.width('100%')
          Column({ space: 10 }) {
            Text('角色卡片').fontSize(12).fontColor(UiTheme.secondary(this.darkTheme)).width('100%')
            Text(this.loggedIn ? '查看游戏角色与每日签到' : '登录查看或绑定角色信息').fontSize(17).fontWeight(FontWeight.Medium).fontColor(UiTheme.primary(this.darkTheme))
            Text('进入数据终端  ›').fontSize(12).fontColor('#119B90')
          }.padding(20).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(18)
            .onClick(() => this.controller.changeIndex(1))
          Row({ space: 10 }) {
            Button('我的收藏').layoutWeight(1).height(64).fontSize(15).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
              .onClick(() => { this.hubMode = 1; this.controller.changeIndex(3); })
            Button('鸣潮大地图').layoutWeight(1).height(64).fontSize(15).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
              .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/WebPage', params: { url: 'https://www.kurobbs.com/mc/map/', title: '鸣潮大地图' } }))
          }.width('100%')
          Row({ space: 10 }) {
            Button('我的帖子').layoutWeight(1).height(56).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
              .onClick(() => this.openAccountList('posts'))
            Button('浏览记录').layoutWeight(1).height(56).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
              .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/History' }))
          }.width('100%')
          Button('本地抓包诊断 · 开发测试').height(48).width('100%').fontSize(14).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
            .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/CaptureProbe' }))
          Button('官方社区').height(48).width('100%').fontSize(14).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
            .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/WebPage', params: { url: 'https://www.kurobbs.com/mc/home', title: '官方社区' } }))
          if (this.message) { Text(this.message).fontSize(12).fontColor(UiTheme.errorText(this.darkTheme)).width('100%') }
          if (this.loggedIn) { Button('退出账号').constraintSize({ minHeight: 44 }).width('100%').fontColor(UiTheme.warningText(this.darkTheme)).backgroundColor(UiTheme.warningSurface(this.darkTheme)).onClick(() => this.logout()) }
          Text('库街区 · 非官方 1.8.7\n独立开发 · HarmonyOS API 26').fontSize(11).fontColor(UiTheme.muted(this.darkTheme)).lineHeight(19).textAlign(TextAlign.Center)
        }.padding({ left: 20, right: 20, top: 12, bottom: 110 }).width('100%')
      }.onScroll((xOffset: number, yOffset: number) => this.scrollNavigation(yOffset)).width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme))
    }.width('100%').height('100%')
  }
  build() {
    Stack() {
    SafePage({ reserveBottom: false }) {
    Stack() {
    HdsTabs({ controller: this.controller }) {
      TabContent() { Feed({ onScrollDirection: (hidden: boolean): void => this.setNavigationHidden(hidden) }) }.tabBar({ icon: $r('app.media.community'), text: '首页' })
      TabContent() { GameData({ refreshVersion: this.version, onScrollDirection: (hidden: boolean): void => this.setNavigationHidden(hidden) }) }.tabBar({ icon: $r('app.media.data'), text: '终端' })
      TabContent() { Text('发布新内容').fontColor(UiTheme.primary(this.darkTheme)) }.tabBar({ icon: $r('app.media.compose'), text: '发布' })
      TabContent() { this.dynamic() }.tabBar({ icon: $r('app.media.star'), text: '动态' })
      TabContent() { this.account() }.tabBar({ icon: $r('app.media.me'), text: '我的' })
    }.barOverlap(true).barPosition(BarPosition.End).vertical(false)
      .barHeight(this.navigationHidden ? 0 : 64)
      .barFloatingStyle({
        barWidth: { smallWidth: 350, mediumWidth: 420, largeWidth: 480 },
        barBottomMargin: 18 + this.safeBottom,
        systemMaterialEffect: {
          materialType: this.materialEnabled ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.NONE,
          materialLevel: UiTheme.hdsLevel(this.materialLevel)
        }
      })
      .scrollable(false)
      .onContentWillChange((_currentIndex: number, comingIndex: number): boolean => comingIndex !== 2)
      .onTabBarClick((index: number) => {
        if (index === 2) {
          this.openCompose();
        }
      })
      .onChange((_index: number) => {
        this.setNavigationHidden(false); this.refresh();
      })
      .width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme))
    }.width('100%').height('100%')
    }
    }.width('100%').height('100%').backgroundColor(this.diagnostic ? '#9C27B0' : Color.Transparent)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
