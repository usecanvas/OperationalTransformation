//
//  TransportController.swift
//  OperationalTransformation
//
//  Created by Sam Soffes on 11/10/15.
//  Copyright © 2015 Canvas Labs, Inc. All rights reserved.
//

import WebKit

public protocol TransportControllerDelegate: class {
	func transportController(_ controller: TransportController, willConnectWithWebView webView: WKWebView)
	func transportController(_ controller: TransportController, didReceiveSnapshot text: String)
	func transportController(_ controller: TransportController, didReceiveOperation operation: Operation)
	func transportController(_ controller: TransportController, didReceiveWebErrorMessage errorMessage: String?, lineNumber: UInt?, columnNumber: UInt?)
	func transportController(_ controller: TransportController, didDisconnectWithErrorMessage errorMessage: String?)
}

private let indexHTML: String? = {
	let bundle = Bundle(for: TransportController.self)
	guard let editorPath = bundle.path(forResource: "index", ofType: "html"),
		let html = try? String(contentsOfFile: editorPath, encoding: String.Encoding.utf8)
	else { return nil }

	return html
}()


open class TransportController: NSObject {
	
	// MARK: - Properties

	open let serverURL: URL
	fileprivate let accessToken: String
	open let organizationID: String
	open let canvasID: String
	open let debug: Bool
	open weak var delegate: TransportControllerDelegate?

	var webView: WKWebView!

	
	// MARK: - Initializers
	
	public init(serverURL: URL, accessToken: String, organizationID: String, canvasID: String, debug: Bool = false) {
		self.serverURL = serverURL
		self.accessToken = accessToken
		self.organizationID = organizationID
		self.canvasID = canvasID
		self.debug = debug
		
		super.init()

		let configuration = WKWebViewConfiguration()
		configuration.allowsAirPlayForMediaPlayback = false

		#if !os(OSX)
			configuration.allowsInlineMediaPlayback = false
			configuration.allowsPictureInPictureMediaPlayback = false
		#endif

		// Setup script handler
		let userContentController = WKUserContentController()
		userContentController.add(self, name: "share")

		// Connect
		let js = "Canvas.connect({" +
			"realtimeURL: '\(serverURL.absoluteString)', " +
			"accessToken: '\(accessToken)', " +
			"orgID: '\(organizationID)', " +
			"canvasID: '\(canvasID)', " +
			"debug: \(debug)" +
		"});"
		userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
		configuration.userContentController = userContentController

		// Load file
		webView = WKWebView(frame: .zero, configuration: configuration)

		#if !os(OSX)
			webView.scrollView.scrollsToTop = false
		#endif

	}


	// MARK: - Connecting

	open func connect() {
		guard let html = indexHTML else { return }

		if webView.superview == nil {
			delegate?.transportController(self, willConnectWithWebView: webView)
		}
		
		webView.loadHTMLString(html, baseURL: URL(string: "https://usecanvas.com/"))
	}

	open func disconnect(withReason reason: String? = nil) {
		webView.removeFromSuperview()
		delegate?.transportController(self, didDisconnectWithErrorMessage: reason)
	}
	
	// MARK: - Operations
	
	open func submit(operation: Operation) {
		switch operation {
		case .insert(let location, let string): insert(atLocation: location, string: string)
		case .remove(let location, let length): remove(atLocation: location, length: length)
		}
	}

	
	// MARK: - Private
	
	fileprivate func insert(atLocation location: UInt, string: String) {
		guard let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
			let json = String(data: data, encoding: String.Encoding.utf8)
		else { return }
		
		webView.evaluateJavaScript("Canvas.insert(\(location), \(json)[0]);", completionHandler: nil)
	}
	
	fileprivate func remove(atLocation location: UInt, length: UInt) {
		webView.evaluateJavaScript("Canvas.remove(\(location), \(length));", completionHandler: nil)
	}
}


extension TransportController: WKScriptMessageHandler {
	public func userContentController(_ userContentController: WKUserContentController, didReceive scriptMessage: WKScriptMessage) {
		guard let dictionary = scriptMessage.body as? [String: Any],
			let message = Message(dictionary: dictionary)
		else {
			print("[TransportController] Unknown message: \(scriptMessage.body)")
			return
		}

		switch message {
		case .operation(let operation):
			delegate?.transportController(self, didReceiveOperation: operation)
		case .snapshot(let content):
			delegate?.transportController(self, didReceiveSnapshot: content)
		case .disconnect(let errorMessage):
			disconnect(withReason: errorMessage)
		case .error(let errorMessage, let lineNumber, let columnNumber):
			delegate?.transportController(self, didReceiveWebErrorMessage: errorMessage, lineNumber: lineNumber, columnNumber: columnNumber)
		}
	}
}
