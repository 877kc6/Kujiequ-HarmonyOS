import { UiTheme } from '../services/UiTheme';

@Component
export struct AppBackdrop {
  @StorageLink('layoutDiagnostic') diagnostic: boolean = false;
  @StorageLink('backgroundImage') imagePath: string = '';
  @StorageLink('darkTheme') darkTheme: boolean = false;
  build() {
    Stack() {
      if (this.diagnostic) { Column().width('100%').height('100%').backgroundColor('#00C853') }
      else if (this.imagePath) {
        Image(`file://${this.imagePath}`).width('100%').height('100%').objectFit(ImageFit.Cover)
        Column().width('100%').height('100%').backgroundColor(this.darkTheme ? '#9A090C12' : '#B8FFFFFF')
      } else {
        Column().width('100%').height('100%').backgroundColor(UiTheme.base(this.darkTheme))
      }
    }.width('100%').height('100%')
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
  }
}
