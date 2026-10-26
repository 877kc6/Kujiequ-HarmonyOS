import { gameBoards, GameBoard } from '../services/GameBoards';
import { UiTheme } from '../services/UiTheme';
import { Session } from '../services/Session';
import { isOfficialUrl } from '../services/Protocol';
import { PostItem, OfficialBanner } from '../models/Models';
import { KuroApi } from '../services/KuroApi';

@Component
export struct Feed {
  @StorageLink('immersiveEnabled') materialEnabled: boolean = true;
  @StorageLink('materialThickness') materialThickness: number = 2;
  @StorageLink('darkTheme') darkTheme: boolean = false;
  @State gameId: number = 3;
  @State forumId: number = 9;
  @State sort: number = 1;
  @State posts: PostItem[] = [];
  @State banners: OfficialBanner[] = [];
  @State bannerMessage: string = '';
  private bannerSequence: number = 0;
  @State busy: boolean = false;
  @State refreshing: boolean = false;
  @State message: string = '';
  @State hasNext: boolean = true;
  @State filter: string = '';
  onScrollDirection: (hidden: boolean) => void = (_hidden: boolean): void => {};
  private scrollDistance: number = 0;
  private scrollNavigation(offset: number): void {
    if ((offset > 0) !== (this.scrollDistance > 0)) { this.scrollDistance = 0; }
    this.scrollDistance += offset;
    if (Math.abs(this.scrollDistance) > 18) { this.onScrollDirection(this.scrollDistance > 0); this.scrollDistance = 0; }
  }
  private page: number = 0;
  private sequence: number = 0;

  aboutToAppear(): void { AppStorage.setOrCreate('feedGameId', this.gameId); this.load(true); this.loadBanners(); }
  aboutToDisappear(): void { this.sequence++; this.bannerSequence++; }
  private async loadBanners(): Promise<void> {
    const seq = ++this.bannerSequence; const game = this.gameId;
    this.banners = []; this.bannerMessage = '';
    try {
      const items = await KuroApi.banners(game);
      if (seq === this.bannerSequence) {
        this.banners = items.filter((item: OfficialBanner): boolean => /^https:\/\//.test(item.url));
        if (this.banners.length === 0) { this.bannerMessage = '暂无官方推荐'; }
      }
    } catch (_) { if (seq === this.bannerSequence) { this.bannerMessage = '官方推荐加载失败，点击重试'; } }
  }
  private openBanner(item: OfficialBanner): void {
    if (item.h5Url) {
      if (isOfficialUrl(item.h5Url)) { this.getUIContext().getRouter().pushUrl({ url: 'pages/WebPage', params: { url: item.h5Url, title: item.msg } }); }
      else { this.getUIContext().getPromptAction().showToast({ message: '此活动使用外部网站，请在官方客户端查看' }); }
      return;
    }
    const id = item.postId || (item.toAppIOS || '').split('postId=')[1] || '';
    if (/^\d{1,24}$/.test(id)) { this.getUIContext().getRouter().pushUrl({ url: 'pages/Post', params: { postId: id } }); }
  }
  private publish(): void {
    if (!Session.token) { this.getUIContext().getRouter().pushUrl({ url: 'pages/Login' }); return; }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Compose', params: { gameId: this.gameId } });
  }
  private async load(reset: boolean): Promise<void> {
    if (this.busy && !reset) { return; }
    const sequence = ++this.sequence;
    const next = reset ? 1 : this.page + 1;
    this.busy = true; this.message = '';
    if (reset) { this.hasNext = true; }
    try {
      const data = await KuroApi.feed(this.gameId, this.forumId, next, this.sort);
      if (sequence !== this.sequence) { return; }
      if (!data || !Array.isArray(data.postList)) { throw new Error('帖子列表格式已变化，请使用官方网页查看'); }
      const incoming = data.postList;
      const merged = reset ? [] : this.posts.slice();
      incoming.forEach((p: PostItem): void => {
        if (p.postId && !merged.some((old: PostItem): boolean => old.postId === p.postId)) { merged.push(p); }
      });
      this.posts = merged; this.page = next; this.hasNext = data.hasNext === 1 && incoming.length > 0;
    } catch (e) { if (sequence === this.sequence) { this.message = (e as Error).message || '网络请求失败，请重试'; } }
    finally { if (sequence === this.sequence) { this.busy = false; this.refreshing = false; } }
  }
  private selectGame(id: number): void { this.gameId = id; AppStorage.setOrCreate('feedGameId', id); this.forumId = id === 3 ? 9 : 2; this.filter = ''; this.posts = []; this.load(true); this.loadBanners(); }
  private visible(): PostItem[] {
    const key = this.filter.trim().toLowerCase();
    return this.posts.filter((p: PostItem): boolean => !key || `${p.postTitle} ${p.postContent} ${p.userName}`.toLowerCase().includes(key));
  }
  private cover(post: PostItem): string {
    if (post.coverImages && post.coverImages.length > 0) { return post.coverImages[0].url; }
    return post.imgContent && post.imgContent.length > 0 ? post.imgContent[0].url : '';
  }
  @Builder
  card(post: PostItem) {
    Column({ space: 12 }) {
      Row({ space: 9 }) {
        if (post.userHeadUrl) { Image(post.userHeadUrl).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover).onClick(() => { if (post.userId && /^\d{1,24}$/.test(String(post.userId))) { this.getUIContext().getRouter().pushUrl({url:'pages/UserProfile',params:{userId:String(post.userId),userName:post.userName || '',avatar:post.userHeadUrl || ''}}); } }) }
        Column({ space: 3 }) {
          Text(post.userName ?? '库街区用户').fontSize(13).fontWeight(FontWeight.Medium).fontColor(UiTheme.body(this.darkTheme)).onClick(() => { if (post.userId && /^\d{1,24}$/.test(String(post.userId))) { this.getUIContext().getRouter().pushUrl({url:'pages/UserProfile',params:{userId:String(post.userId),userName:post.userName || '',avatar:post.userHeadUrl || ''}}); } })
          Text(post.showTime ?? '').fontSize(11).fontColor(UiTheme.muted(this.darkTheme))
        }.alignItems(HorizontalAlign.Start)
        Blank()
        if (post.postType === 2) { Text('视频').fontSize(11).fontColor('#9F7B1E') }
      }.width('100%')
      Text(post.postTitle || '社区动态').fontSize(18).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme)).width('100%').maxLines(2).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Post', params: { postId: post.postId } }))
      if (post.postContent) { Text(post.postContent).fontSize(14).fontColor(UiTheme.secondary(this.darkTheme)).width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Post', params: { postId: post.postId } })) }
      if (this.cover(post)) { Image(this.cover(post)).width('100%').height(185).borderRadius(14).objectFit(ImageFit.Cover).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Post', params: { postId: post.postId } })) }
      Row() {
        Text(`${post.likeCount ?? 0} 赞`).fontSize(12).fontColor(UiTheme.muted(this.darkTheme))
        Blank()
        Text(`${post.commentCount ?? 0} 条评论`).fontSize(12).fontColor(UiTheme.muted(this.darkTheme))
      }.width('100%')
    }.alignItems(HorizontalAlign.Start).padding(18).width('100%').backgroundColor(UiTheme.surface(this.darkTheme)).borderRadius(20)
      
  }
  build() {
    Stack() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('库街区').fontSize(25).fontWeight(FontWeight.Bold).fontColor(UiTheme.primary(this.darkTheme))
        Text('非官方').fontSize(10).fontColor(UiTheme.muted(this.darkTheme)).padding(5).backgroundColor(UiTheme.control(this.darkTheme)).borderRadius(5)
        Blank()
        Button(this.gameId === 3 ? '鸣潮 ▾' : '战双 ▾').constraintSize({ minHeight: 44 }).fontSize(13).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor('#16D9C9')
          .onClick(() => this.selectGame(this.gameId === 3 ? 2 : 3)).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness))
      }.width('100%').padding({ left: 20, right: 20, top: 12 })
      Scroll() {
        Row({ space: 8 }) {
          ForEach(gameBoards(this.gameId), (board: GameBoard) => {
            Button(board.label).height(44).fontSize(13)
              .fontColor(this.forumId === board.id ? '#122828' : UiTheme.secondary(this.darkTheme))
              .backgroundColor(this.forumId === board.id ? '#16D9C9' : UiTheme.surface(this.darkTheme))
              .onClick(() => { this.forumId = board.id; this.posts = []; this.load(true); })
          }, (board: GameBoard): string => `${this.gameId}_${board.id}`)
        }.padding({ left: 16, right: 16 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(48)
      Row() {
        Text(this.gameId === 2 ? '战双帕弥什 · 灰鸦指挥部' : '鸣潮 · 索拉里斯').fontSize(12).fontColor(UiTheme.secondary(this.darkTheme))
        Blank()
        Button(this.sort === 1 ? '最新发布' : '最新回复').height(36).fontSize(12).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.surface(this.darkTheme))
          .onClick(() => { this.sort = this.sort === 1 ? 2 : 1; this.load(true); })
      }.padding({ left: 20, right: 16 }).width('100%')
      Search({ placeholder: '筛选已加载帖子', value: this.filter }).height(40).margin({ left: 16, right: 16 })
        .onChange((value: string) => { this.filter = value; })
      if (this.message) {
        Row() { Text(this.message).fontSize(12).fontColor(UiTheme.errorText(this.darkTheme)).layoutWeight(1); Button('重试').constraintSize({ minHeight: 44 }).fontSize(12).onClick(() => this.load(this.page === 0)).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness)) }
          .padding(12).backgroundColor(UiTheme.errorSurface(this.darkTheme)).borderRadius(12).margin({ left: 16, right: 16 })
      }
      Refresh({ refreshing: $$this.refreshing }) {
        List({ space: 12 }) {
          if (this.banners.length > 0) {
            ListItem() {
              Swiper() {
                ForEach(this.banners, (banner: OfficialBanner) => {
                  Stack({ alignContent: Alignment.BottomStart }) {
                    Image(banner.url).width('100%').height(175).objectFit(ImageFit.Cover)
                    Text(banner.msg || banner.postTitle || '官方推荐').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
                      .padding(12).width('100%').backgroundColor('#88000000').maxLines(2)
                  }.width('100%').height(175).borderRadius(18).clip(true).onClick(() => this.openBanner(banner))
                }, (banner: OfficialBanner): string => String(banner.id))
              }.height(175).width('100%').autoPlay(false).indicator(true)
            }
          } else if (this.bannerMessage) {
            ListItem() { Text(this.bannerMessage).fontSize(13).fontColor(UiTheme.secondary(this.darkTheme)).padding(16).onClick(() => this.loadBanners()) }
          }
          ForEach(this.visible(), (post: PostItem) => { ListItem() { this.card(post) } }, (post: PostItem): string => post.postId)
          ListItem() {
            Column({ space: 10 }) {
              if (this.busy) { LoadingProgress().width(28).height(28) }
              else if (this.posts.length === 0) { Text('暂无帖子，下拉刷新').fontColor(UiTheme.muted(this.darkTheme)) }
              else if (this.hasNext) { Button('加载更多').constraintSize({ minHeight: 44 }).fontColor(UiTheme.primary(this.darkTheme)).backgroundColor(UiTheme.control(this.darkTheme)).onClick(() => this.load(false)).systemMaterial(UiTheme.button(this.materialEnabled, this.materialThickness)) }
              else { Text('已经到底了').fontSize(12).fontColor(UiTheme.muted(this.darkTheme)) }
            }.width('100%').padding({ top: 12, bottom: 110 })
          }
        }.width('100%').height('100%').padding({ left: 16, right: 16 }).onScroll((scrollOffset: number, scrollState: ScrollState) => this.scrollNavigation(scrollOffset)).onReachStart(() => this.onScrollDirection(false)).onReachEnd(() => { if (this.hasNext && !this.message) { this.load(false); } })
      }.onRefreshing(() => { this.load(true); this.loadBanners(); }).layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(UiTheme.page(this.darkTheme))
    }.width('100%').height('100%')
  }
}
