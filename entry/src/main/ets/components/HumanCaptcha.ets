import { webview } from '@kit.ArkWeb';

// Exposes only one result callback. Never receives phone numbers, SMS codes or tokens.
class CaptchaResultBridge {
  onResult: (proof: string) => void = (_proof: string): void => {};
  active: boolean = false;
  complete(proof: string): void {
    if (!this.active || typeof proof !== 'string' || proof.length > 16384) { return; }
    this.active = false;
    this.onResult(proof);
  }
}

@Component
export struct HumanCaptcha {
  onComplete: (proof: string) => void = (_proof: string): void => {};
  private controller: webview.WebviewController = new webview.WebviewController();
  private resultBridge: CaptchaResultBridge = new CaptchaResultBridge();
  aboutToAppear(): void {
    this.resultBridge.active = true;
    this.resultBridge.onResult = (proof: string): void => { this.onComplete(proof); };
  }
  aboutToDisappear(): void { this.resultBridge.active = false; }
  build() {
    Web({ src: $rawfile('human_captcha.html'), controller: this.controller })
      .javaScriptAccess(true).domStorageAccess(true).fileAccess(false)
      .mixedMode(MixedMode.None).height(420).width('100%')
      .javaScriptProxy({ object: this.resultBridge, name: 'KuroCaptcha', methodList: ['complete'], controller: this.controller })
      .onLoadIntercept((event) => {
        if (!event) { return true; }
        if (!event.data.isMainFrame()) { return false; }
        const target = event.data.getRequestUrl();
        return !/^(resource|file):\/\/[^?#]*\/human_captcha\.html$/.test(target);
      })
      .onSslErrorEventReceive((event) => { event?.handler.handleCancel(); })
  }
}
