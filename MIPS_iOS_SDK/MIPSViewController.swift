//
//  MIPSViewController.swift
//  MIPS_iOS_SDK
//
//  Created by shyank on 29/04/24.
//

import UIKit
import CommonCrypto
import CryptoKit
import WebKit



public protocol MipsPaymentPageDelegate : AnyObject{
    func successPayment(_ sender : MIPSViewController , orderID : String , mode : PaymentMode)
}




open class MIPSViewController : UIViewController {
    
    
    private var webView: WKWebView? = nil
    private var networkURL : MipsNetworkUrls! = nil
    private var merchantDetails : MerchantDetails! = nil
    private var amount : Amount! = nil
    private var orderID : String! = nil
    private var credentials : MerchantCredentials! = nil
    
    
    private var backgruondTask : UIBackgroundTaskIdentifier = .invalid
    
    
    public var delegate : MipsPaymentPageDelegate? = nil
    
    private override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    
    public convenience init(
        networkURL : MipsNetworkUrls ,
        merchantDetails : MerchantDetails ,
        credentials : MerchantCredentials ,
        amount : Amount ,
        orderID : String
    ) {
        self.init(nibName: nil, bundle: nil)
        self.networkURL = networkURL
        self.merchantDetails = merchantDetails
        self.credentials = credentials
        self.amount = amount
        self.orderID = orderID
    }
    
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    public func createPayment() {
        let totalAmount = amount.price * 100
//        let orderID = merchantDetails.sIdForm
        let checksum = "\(merchantDetails.sIdForm)\(orderID!)\(totalAmount)\(amount.currency.rawValue)\(merchantDetails.salt)".sha256()
        
        let paymentJSON = MipsPaymentJSON()
        paymentJSON.id_form = merchantDetails.sIdForm
        paymentJSON.id_order = orderID!
        paymentJSON.amount = totalAmount
        paymentJSON.currency = amount.currency.rawValue
        paymentJSON.checksum = checksum
        
        let (data , dataErr) = JSONCoder.encodeJso(json: paymentJSON)
        guard dataErr == nil , let data = data
        else {return}
        
        let jsonString = "\((String(data: data, encoding: .utf8))!)"
        let middleUrl = try! jsonString.aesEncrypt(key: merchantDetails.sCipherKey)
        let finalUrl = middleUrl.toBase64()
        
        let urlStirng = "\(self.networkURL.baseURl)\(finalUrl)&smid=\(self.merchantDetails.sIdMerchant)"
        guard let urlToPayment = NSURL(string: urlStirng)
        else{return}
        
        let req = URLRequest(url: urlToPayment as URL)
        
        self.webView!.load(req as URLRequest)
        
        
        setupNotificationListners()
    }
    
    
    @objc func appMovedToForeground() {
        LogManager.shared.info("App moved to foreground!")
        UIApplication.shared.endBackgroundTask(self.backgruondTask)
        self.backgruondTask = .invalid
        
        NetworkAdaptor.checkPaymentStatus(
            mipsNetworkURl: self.networkURL,
            merchant: self.merchantDetails, 
            credentials: self.credentials,
            orderID: self.orderID
        ) { [weak self] isPaymentCompleted in
            guard let self
            else {return}
            if isPaymentCompleted {
                self.showSuceesPaymrnt(.juice)
            }
        } errorHandler: { errorString in
            LogManager.shared.error("got error while callin mips payment confirmation call with error  :=> \(errorString)")
        }
    }
    
    @objc func appMovedToBackground() {
        startbackgroundMethod()
        LogManager.shared.info("app moved to background mode")
        
    }
    private func startbackgroundMethod() {
        backgruondTask = UIApplication.shared.beginBackgroundTask {[weak self] in
            guard let self = self
            else{return}
            UIApplication.shared.endBackgroundTask(self.backgruondTask)
            LogManager.shared.info("bckground task expired")
        }
    }
    
    private func setupNotificationListners() {
        let notificationCenter = NotificationCenter.default
        
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        notificationCenter.addObserver(self, selector: #selector(appMovedToForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        
        let contentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        
        config.userContentController = contentController
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        self.webView = WKWebView( frame: .zero, configuration: config)
        
        webView?.translatesAutoresizingMaskIntoConstraints = false
        webView?.navigationDelegate = self
        webView?.uiDelegate = self
        view.addSubview(webView!)
        
        NSLayoutConstraint.activate([
            webView!.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor , constant: 2),
            webView!.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor , constant: -2),
            webView!.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor , constant: 2),
            webView!.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -2)
        ])
    }
    
    private func showSuceesPaymrnt(_ mode : PaymentMode) {
        delegate?.successPayment(self, orderID: orderID, mode: mode)
    }
}


extension MIPSViewController : WKNavigationDelegate, WKUIDelegate {
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        LogManager.shared.info("message from mips web page -> \(message)")
        if (message.lowercased() == "success") {
            showSuceesPaymrnt(.instant)
        }
        if (message.lowercased() == "success_juice"){
            showSuceesPaymrnt(.juice)
        }
        
        if (message.lowercased() == "success_bank_transfer"){
            showSuceesPaymrnt(.bankTransfer)
        }
        completionHandler()
        UIApplication.shared.endBackgroundTask(self.backgruondTask)
        self.backgruondTask = .invalid
    }
}
