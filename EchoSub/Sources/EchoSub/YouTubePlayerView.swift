import AppKit
import WebKit

protocol YouTubePlayerViewDelegate: AnyObject {
    func playerView(_ view: YouTubePlayerView, didUpdateTime time: Double)
    func playerView(_ view: YouTubePlayerView, didChangeState state: Int)
    func playerView(_ view: YouTubePlayerView, didFailWithCode code: Int)
}

final class YouTubePlayerView: NSView, WKScriptMessageHandler, WKNavigationDelegate {
    weak var delegate: YouTubePlayerViewDelegate?
    private let webView: WKWebView
    private(set) var videoID: String?
    private(set) var isReady = false

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        controller.add(self, name: "echoPlayer")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        addSubview(webView)
        webView.pinEdges(to: self)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "echoPlayer")
    }

    func load(videoID: String, start: Double = 0) {
        self.videoID = videoID
        isReady = false
        let safeID = videoID.replacingOccurrences(of: "'", with: "")
        // YouTube requires an identifiable HTTP Referer for desktop WebView players.
        // Using the bundle identifier as the local page origin makes WKWebView emit it
        // for the iframe request while keeping the player inside the native view.
        let appID = (Bundle.main.bundleIdentifier ?? "app.echosub.mac").lowercased()
        let appOrigin = "https://\(appID)"
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body,#player{width:100%;height:100%;margin:0;background:#000;overflow:hidden}</style></head>
        <body><div id="player"></div><script src="https://www.youtube.com/iframe_api"></script><script>
        let player; let ready=false;
        function send(type, value) { window.webkit.messageHandlers.echoPlayer.postMessage({type:type,value:value}); }
        function onYouTubeIframeAPIReady(){
          player=new YT.Player('player',{
            videoId:'\(safeID)',
            playerVars:{playsinline:1,rel:0,controls:1,fs:0,start:\(Int(start)),enablejsapi:1,origin:'\(appOrigin)',widget_referrer:'\(appOrigin)/'},
            events:{
              onReady:function(){ready=true;send('ready',1);},
              onStateChange:function(e){send('state',e.data);},
              onError:function(e){send('error',e.data);}
            }
          });
        }
        setInterval(function(){if(ready&&player&&player.getCurrentTime)send('time',player.getCurrentTime());},250);
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "\(appOrigin)/")!)
    }

    func play() { evaluate("player && player.playVideo();") }
    func pause() { evaluate("player && player.pauseVideo();") }
    func togglePlayback() { evaluate("if(player){player.getPlayerState()===1?player.pauseVideo():player.playVideo();}") }
    func seek(to seconds: Double) { evaluate("player && player.seekTo(\(max(0, seconds)), true);") }
    func skip(by delta: Double) { evaluate("player && player.seekTo(Math.max(0,player.getCurrentTime()+\(delta)), true);") }

    private func evaluate(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        let value = (body["value"] as? NSNumber)?.doubleValue ?? 0
        switch type {
        case "ready": isReady = true
        case "time": delegate?.playerView(self, didUpdateTime: value)
        case "state": delegate?.playerView(self, didChangeState: Int(value))
        case "error": delegate?.playerView(self, didFailWithCode: Int(value))
        default: break
        }
    }
}
