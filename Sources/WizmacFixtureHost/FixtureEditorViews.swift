import AppKit
import SwiftUI
import WebKit

struct AppKitTextFieldFixture: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = "AppKit NSTextField"
        field.delegate = context.coordinator
        field.identifier = NSUserInterfaceItemIdentifier("fixture.appkit.field")
        return field
    }

    func updateNSView(_ nsView: NSTextField, context _: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AppKitTextFieldFixture

        init(parent: AppKitTextFieldFixture) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

struct AppKitTextViewFixture: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView()
        textView.string = text
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.delegate = context.coordinator
        textView.identifier = NSUserInterfaceItemIdentifier("fixture.appkit.textView")
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context _: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AppKitTextViewFixture

        init(parent: AppKitTextViewFixture) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

struct WebKitEditableFixture: NSViewRepresentable {
    var onEvent: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "fixture")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.fixtureHTML, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context _: Context) {
        if nsView.url == nil {
            nsView.loadHTMLString(Self.fixtureHTML, baseURL: nil)
        }
    }
}

extension WebKitEditableFixture {
    static let fixtureHTML = """
    <!doctype html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          margin: 0;
          padding: 16px;
          background: rgba(245,245,245,0.9);
          color: #1f2937;
        }
        .stack { display: grid; gap: 12px; }
        input, textarea, [contenteditable="true"] {
          width: 100%;
          box-sizing: border-box;
          padding: 10px 12px;
          border: 1px solid #cbd5e1;
          border-radius: 10px;
          background: white;
          font: 14px/1.4 -apple-system, BlinkMacSystemFont, sans-serif;
        }
        textarea { min-height: 110px; resize: vertical; }
        [contenteditable="true"] { min-height: 90px; }
        label { display: grid; gap: 6px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.08em; color: #475569; }
      </style>
    </head>
    <body>
      <div class="stack">
        <label>
          WebKit Input
          <input id="web-input" value="WebKit single-line editor" />
        </label>
        <label>
          WebKit Textarea
          <textarea id="web-textarea">This textarea exists to exercise browser-backed multiline editing.</textarea>
        </label>
        <label>
          Contenteditable
          <div id="web-rich" contenteditable="true">Editable div for hinting and modal transitions.</div>
        </label>
      </div>
      <script>
        const notify = (value) => {
          window.webkit.messageHandlers.fixture.postMessage(String(value));
        };
        for (const id of ["web-input", "web-textarea", "web-rich"]) {
          const node = document.getElementById(id);
          node.addEventListener("focus", () => notify(id + ":focus"));
          node.addEventListener("input", () => notify(id + ":input"));
        }
      </script>
    </body>
    </html>
    """

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let onEvent: (String) -> Void

        init(onEvent: @escaping (String) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? String else { return }
            onEvent(value)
        }
    }
}
