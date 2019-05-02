//
//  EPUBNavigatorViewController.swift
//  r2-navigator-swift
//
//  Created by Winnie Quinn, Alexandre Camilleri on 8/23/17.
//
//  Copyright 2018 Readium Foundation. All rights reserved.
//  Use of this source code is governed by a BSD-style license which is detailed
//  in the LICENSE file present in the project repository where this source code is maintained.
//

import UIKit
import R2Shared
import WebKit
import SafariServices


public protocol EPUBNavigatorDelegate: class {
    func middleTapHandler()
    func willExitPublication(documentIndex: Int, progression: Double?)
    /// invoked when publication's content change to another page of 'document', slide to next chapter for example
    /// It changes when html file resource changed
    func didChangedDocumentPage(currentDocumentIndex: Int)
    func didChangedPaginatedDocumentPage(currentPage: Int, documentTotalPage: Int)
    func didNavigateViaInternalLinkTap(to documentIndex: Int)
    func didTapExternalUrl(_ : URL)
    func didCallFromWebTTSEvent(with model: TTSBridgeModel)
    
    /// Displays an error message to the user.
    func presentError(_ error: NavigatorError)
}

public extension EPUBNavigatorDelegate {
    func didChangedDocumentPage(currentDocumentIndex: Int) {
        // optional
    }
    
    func didChangedPaginatedDocumentPage(currentPage: Int, documentTotalPage: Int) {
        // optional
    }
    
    func didNavigateViaInternalLinkTap(to documentIndex: Int) {
        // optional
    }
    
    func didTapExternalUrl(_ url: URL) {
        // optional
        // TODO following lines have been moved from the original implementation and might need to be revisited at some point
        let view = SFSafariViewController(url: url)
        UIApplication.shared.keyWindow?.rootViewController?.present(view, animated: true, completion: nil)
    }
}


public typealias EPUBContentInsets = (top: CGFloat, bottom: CGFloat)

open class EPUBNavigatorViewController: UIViewController {
    private let delegatee: Delegatee!
    fileprivate let triptychView: TriptychView
    public var userSettings: UserSettings
    fileprivate var initialProgression: Double?
    //
    public let publication: Publication
    public let license: DRMLicense?
    public weak var delegate: EPUBNavigatorDelegate?
    
    public let pageTransition: PageTransition
    public let disableDragAndDrop: Bool
    
    fileprivate let editingActions: EditingActionsController

    /// Content insets used to add some vertical margins around reflowable EPUB publications. The insets can be configured for each size class to allow smaller margins on compact screens.
    public let contentInset: [UIUserInterfaceSizeClass: EPUBContentInsets]

    /// - Parameters:
    ///   - publication: The publication.
    ///   - initialIndex: Inital index of -1 will open the publication's at the end.
    public init(for publication: Publication, license: DRMLicense? = nil, initialIndex: Int, initialProgression: Double?, pageTransition: PageTransition = .none, disableDragAndDrop: Bool = false, editingActions: [EditingAction] = EditingAction.defaultActions, contentInset: [UIUserInterfaceSizeClass: EPUBContentInsets]? = nil) {
        self.publication = publication
        self.license = license
        self.initialProgression = initialProgression
        self.pageTransition = pageTransition
        self.disableDragAndDrop = disableDragAndDrop
        self.contentInset = contentInset ?? [
            .compact: (top: 20, bottom: 20),
            .regular: (top: 44, bottom: 44)
        ]
      
        self.editingActions = EditingActionsController(actions: editingActions, license: license)

        userSettings = UserSettings()
        publication.userProperties.properties = userSettings.userProperties.properties
        delegatee = Delegatee()
        var index = initialIndex

        if initialIndex == -1 {
            index = publication.readingOrder.count
        }
        
        triptychView = TriptychView(frame: CGRect.zero,
                                    viewCount: publication.readingOrder.count,
                                    initialIndex: index,
                                    readingProgression:publication.metadata.readingProgression)
        
        super.init(nibName: nil, bundle: nil)
        
        self.editingActions.delegate = self
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        delegatee.parent = self
        view.backgroundColor = .clear
        triptychView.backgroundColor = .clear
        triptychView.delegate = delegatee
        triptychView.frame = view.bounds
        triptychView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        view.addSubview(triptychView)
    }

    public var currentLocation: Locator? {
        var hrefToTitle: [String: String] = {
            let linkList = self.getTableOfContents()
            return fulfill(linkList: linkList)
        } ()
        
        func fulfill(linkList: [Link]) -> [String: String] {
            var result = [String: String]()
            
            for link in linkList {
                if let title = link.title {
                    result[link.href] = title
                }
                let subResult = fulfill(linkList: link.children)
                result.merge(subResult) { (current, another) -> String in
                    return current
                }
            }
            return result
        }
        
        let progression = triptychView.getCurrentDocumentProgression()
        let index = triptychView.getCurrentDocumentIndex()
        let readingOrder = self.getReadingOrder()[index]
        let resourceTitle: String = hrefToTitle[readingOrder.href] ?? "Unknown"
        
        return Locator(
            href: readingOrder.href,
            type: readingOrder.type ?? "text/html",
            title: resourceTitle,
            locations: Locations(
                progression: progression ?? 0
            )
        )
    }
    
    @available(*, deprecated, message: "Bookmark model is deprecated, use your own model and `currentLocation`")
    public var currentPosition: Bookmark? {
        guard let publicationID = publication.metadata.identifier,
            let locator = currentLocation else
        {
            return nil
        }
        return Bookmark(
            publicationID: publicationID,
            resourceIndex: triptychView.getCurrentDocumentIndex(),
            locator: locator
        )
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Save the currently opened document index and progression.
        let progression = triptychView.getCurrentDocumentProgression()
        let index = triptychView.getCurrentDocumentIndex()
        delegate?.willExitPublication(documentIndex: index, progression: progression)
    }
}

extension EPUBNavigatorViewController {

    /// Display the readingOrder item at `index`.
    ///
    /// - Parameter index: The index of the readingOrder item to display.
    public func displayReadingOrderItem(at index: Int, force: Bool = false) {
        guard publication.readingOrder.indices.contains(index) else {
            return
        }
        performTriptychViewTransition {
            self.triptychView.moveTo(index: index, force: force)
        }
    }
    
    /// Display the readingOrder item at `index` with scroll `progression`
    ///
    /// - Parameter index: The index of the readingOrder item to display.
    public func displayReadingOrderItem(at index: Int, progression: Double) {
        guard publication.readingOrder.indices.contains(index) else {
            return
        }
        
        performTriptychViewTransitionDelayed {
            // This is so the webview will move to it's correct progression if it's not loaded into the triptych view
            self.initialProgression = progression
            self.triptychView.moveTo(index: index)
            if let webView = self.triptychView.currentView as? WebView {
                // This is needed for when the webView is loaded into the triptychView
                webView.scrollAt(position: progression)
            }
        }
    }
    
    /// Load resource with the corresponding href.
    ///
    /// - Parameter href: The href of the resource to load. Can contain a tag id.
    /// - Returns: The readingOrder index for the link
    public func displayReadingOrderItem(with href: String) -> Int? {
        // remove id if any
        let components = href.components(separatedBy: "#")
        guard let href = components.first else {
            return nil
        }
        guard let index = publication.readingOrder.index(where: { $0.href.contains(href) }) else {
            return nil
        }
        // If any id found, set the scroll position to it, else to the
        // beggining of the document.
        let id = (components.count > 1 ? components.last : "")
        
        // Jumping set to true to avoid clamping.
        performTriptychViewTransition {
            self.triptychView.moveTo(index: index, id: id)
        }
        return index
    }
    
    public func getReadingOrder() -> [Link] {
        return publication.readingOrder
    }
    
    public func getTableOfContents() -> [Link] {
        return publication.tableOfContents
    }
    
    public func updateUserSettingStyle() {
        guard let views = triptychView.views?.array else {
            return
        }
        for view in views {
            let webview = view as? WebView
            
            webview?.applyUserSettingsStyle()
        }
    }
}

extension EPUBNavigatorViewController: WebViewDelegate {
    
    func willAnimatePageChange() {
        triptychView.isUserInteractionEnabled = false
    }
    
    func didEndPageAnimation() {
        triptychView.isUserInteractionEnabled = true
    }
    
    func handleTapOnLink(with url: URL) {
        delegate?.didTapExternalUrl(url)
    }
    
    func handleTapOnInternalLink(with href: String) {
        guard let index = displayReadingOrderItem(with: href) else { return }
        delegate?.didNavigateViaInternalLinkTap(to: index)
    }
    
    func documentPageDidChange(webView: WebView, currentPage: Int, totalPage: Int) {
        if triptychView.currentView == webView {
            delegate?.didChangedPaginatedDocumentPage(currentPage: currentPage, documentTotalPage: totalPage)
        }
    }
    
    /// Display next document (readingOrder item).
    public func displayRightDocument() {
        let delta = triptychView.readingProgression == .rtl ? -1:1
        self.displayReadingOrderItem(at: self.triptychView.index + delta)
    }
    
    /// Display previous document (readingOrder item).
    public func displayLeftDocument() {
        let delta = triptychView.readingProgression == .rtl ? -1:1
        self.displayReadingOrderItem(at: self.triptychView.index - delta)
    }
    
    /// Returns the currently presented Publication's identifier.
    ///
    /// - Returns: The publication identifier.
    public func publicationIdentifier() -> String? {
        return publication.metadata.identifier
    }
    
    public func publicationBaseUrl() -> URL? {
        return publication.baseURL
    }
    
    internal func handleCenterTap() {
        delegate?.middleTapHandler()
    }

}

extension EPUBNavigatorViewController: EditingActionsControllerDelegate {
    
    func editingActionsDidPreventCopy(_ editingActions: EditingActionsController) {
        delegate?.presentError(.copyForbidden)
    }

    func didCallFromWebTTSEvent(with model: TTSBridgeModel) {
        delegate?.didCallFromWebTTSEvent(with: model)
   }
    
}

extension EPUBNavigatorViewController {
    
    public func isReadyToTTS(completion: ((Bool) -> Void)?) {
        (triptychView.currentView as? WebView)?.webView
            .evaluateJavaScript("tts_result_json;") { (result, error) in
            guard let _ = result as? [Any] else {
                completion?(false)
                return
            }
            completion?(true)
        }
    }
    
    public func readyToTTS(with isAutoPage: Bool, completion: TTSBridgeModelDefaultHandler?) {
        (triptychView.currentView as? WebView)?.webView
            .evaluateJavaScript("tts_ready(\(isAutoPage));", completionHandler: { (_, _) in
            completion?()
        })
    }
    
    public func executeTTS(index: Int, completion: TTSBridgeModelDefaultHandler?) {
        (triptychView.currentView as? WebView)?.webView
            .evaluateJavaScript("call_from_native_tts_page(\(index));", completionHandler: { (_, _) in
            completion?()
        })
    }
    
    public func stopTTS(completion: TTSBridgeModelDefaultHandler?) {
        (triptychView.currentView as? WebView)?.webView
            .evaluateJavaScript("call_from_native_reset();") { (_, _) in
            completion?()
        }
    }
    
    public func removeAllHighlight(completion: TTSBridgeModelDefaultHandler?) {
        (triptychView.currentView as? WebView)?.webView
            .evaluateJavaScript("ADDON_IPAPRIKA.JS.remove_TTS_All_Highlight();") { (_, _) in
            completion?()
        }
    }
    
}

/// Used to hide conformance to package-private delegate protocols.
private final class Delegatee: NSObject {
    weak var parent: EPUBNavigatorViewController!
    fileprivate var firstView = true
}

extension Delegatee: TriptychViewDelegate {

    public func triptychView(_ view: TriptychView, viewForIndex index: Int, location: BinaryLocation) -> UIView {
        let link = parent.publication.readingOrder[index]
        // Check if link is FXL.
        let hasFixedLayout = (parent.publication.metadata.rendition?.layout == .fixed && link.properties.layout == nil) || link.properties.layout == .fixed
        
        let webViewType = hasFixedLayout ? FixedWebView.self : ReflowableWebView.self
        let webView = webViewType.init(
            initialLocation: location,
            readingProgression: view.readingProgression,
            pageTransition: parent.pageTransition,
            disableDragAndDrop: parent.disableDragAndDrop,
            editingActions: parent.editingActions,
            contentInset: parent.contentInset
        )
        
        if let url = parent.publication.url(to: link) {
            let urlRequest = URLRequest(url: url)
            
            webView.viewDelegate = parent
            webView.load(urlRequest)
            webView.userSettings = parent.userSettings
            
            // Load last saved regionIndex for the first view.
            if parent.initialProgression != nil {
                webView.progression = parent.initialProgression
                parent.initialProgression = nil
            }
        }
        return webView
    }
    
    func viewsDidUpdate(documentIndex: Int) {
        // notice that you should set the delegate before you load views
        // otherwise, when open the publication, you may miss the first invocation
        parent.delegate?.didChangedDocumentPage(currentDocumentIndex: documentIndex)
        if let currentView = parent.triptychView.currentView {
            let cw = currentView as! WebView
            if let pages = cw.totalPages {
                parent.delegate?.didChangedPaginatedDocumentPage(currentPage: cw.currentPage(), documentTotalPage: pages)
            }
        }
    }
}


extension EPUBNavigatorViewController {
    
    public var contentView: UIView {
        return triptychView
    }
    
    func performTriptychViewTransition(commitTransition: @escaping () -> ()) {
        switch pageTransition {
        case .none:
            commitTransition()
        case .animated:
            fadeTriptychView(alpha: 0) {
                commitTransition()
                self.fadeTriptychView(alpha: 1, completion: { })
            }
        }
    }
    
    /*
     This is used when we want to jump to a document with proression. The rendering is sometimes very slow in this case so we have a generous delay before we show the view again.
     */
    func performTriptychViewTransitionDelayed(commitTransition: @escaping () -> ()) {
        switch pageTransition {
        case .none:
            commitTransition()
        case .animated:
            fadeTriptychView(alpha: 0) {
                commitTransition()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                    self.fadeTriptychView(alpha: 1, completion: { })
                })
            }
        }
    }
    
    private func fadeTriptychView(alpha: CGFloat, completion: @escaping () -> ()) {
        UIView.animate(withDuration: 0.15, animations: {
            self.triptychView.alpha = alpha
        }) { _ in
            completion()
        }
    }
}

extension EPUBNavigatorViewController {
    
    public var currentDocumentPosition: (Int, Double) {
        let documentIndex = triptychView.getCurrentDocumentIndex()
        let documentProgression = triptychView.getCurrentDocumentProgression() ?? 0.0
        return (documentIndex, documentProgression)
    }
    
}

@available(*, deprecated, renamed: "EPUBNavigatorViewController")
public typealias NavigatorViewController = EPUBNavigatorViewController
@available(*, deprecated, renamed: "EPUBNavigatorDelegate")
public typealias NavigatorDelegate = EPUBNavigatorDelegate
