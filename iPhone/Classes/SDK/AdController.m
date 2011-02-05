//
//  AdController.m
//  Copyright (c) 2010 MoPub Inc.
//

#import "AdController.h"
#import "AdClickController.h"
#import <CoreLocation/CoreLocation.h>
#import <StoreKit/StoreKit.h>

#import "MoPubNativeSDKRegistry.h"
#import "MoPubNativeSDKAdapter.h"

@interface AdController (Internal)
- (void)backfillWithNothing;
- (void)backfillWithADBannerView;
- (void)backfillWithAdSenseWithParams:(NSDictionary *)params;

- (NSString *)escapeURL:(NSURL *)urlIn;
- (NSDictionary *)parseQuery:(NSString *)query;
- (void)adClickHelper:(NSURL *)desiredURL;
- (void)loadAdWithURL:(NSURL *)adUrl;

// inapp purchases
- (void)initiatePurchaseForProductIdentifier:(NSString *)productIndentifier quantity:(NSInteger)quantity;
- (void)preloadProductForProductIdentifier:(NSString *)_productIdentifier;
- (void)requestProductDataForProductIdentifier:(NSString *)_productIdentifier autoPurchase:(BOOL)autoPurchase;
- (void)startPaymentForProductIdentifier:(NSString *)_productIdentifier;
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions;
- (void)completeTransaction: (SKPaymentTransaction *)transaction;
- (void)restoreTransaction: (SKPaymentTransaction *)transaction;
- (void)failedTransaction: (SKPaymentTransaction *)transaction;
- (void)recordTransaction:(SKPaymentTransaction *)transaction;
- (void)provideContent:(NSString *)productId;
- (void)performSelectorString:(NSString *)selectorString withStringData:(NSString *)stringData;


	

@end

	
@implementation AdController

@synthesize delegate;
@synthesize loaded;
@synthesize adUnitId;
@synthesize size;
@synthesize webView, loadingIndicator;
@synthesize parent, keywords, location;
@synthesize data, url, failURL;
@synthesize nativeAdView, nativeAdViewController;
@synthesize clickURL;
@synthesize newPageURLString;
@synthesize currentAdapter, lastAdapter;
@synthesize currentAdType;
@synthesize interceptLinks;
@synthesize scrollable;
@synthesize productIdentifier;
@synthesize product;
@synthesize productDictionary;


- (id)initWithSize:(CGSize)_size adUnitId:(NSString*)a parentViewController:(UIViewController*)pvc{
	if (self = [super init]){
		self.data = [NSMutableData data];
		
		// set format + publisherId, the two immutable properties of this ad controller
		self.parent = pvc;
		self.size = _size;
		self.adUnitId = a;
				
		// initialize ad Loading to False
		adLoading = NO;
		_isInterstitial = NO;
		interceptLinks = YES;
		scrollable = NO;
		
		// init the exclude parameter list
		excludeParams = [[NSMutableArray alloc] initWithCapacity:1];
		
		// add self to receive notifications that the application will resign
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillResign:) name:UIApplicationWillResignActiveNotification object:nil];
		
		// register as an in-app purchase observer
		[[SKPaymentQueue defaultQueue] addTransactionObserver:self];
	}	
	return self;
}

- (void)setNativeAdViewController:(UIViewController *)vc{
	[vc retain];
	// unsubscribe as delegate
	if ([nativeAdViewController respondsToSelector:@selector(setDelegate:)]){
		[nativeAdViewController performSelector:@selector(setDelegate:) withObject:nil];
	}
	[nativeAdViewController release];
	nativeAdViewController = vc;
}

- (NSString *)currentAdType{
	if (self.currentAdapter)
		return [[self.currentAdapter class] networkType];
	return @"html";
}

- (void)dealloc{
	[data release];
	[parent release];
	[adUnitId release];
	
	// first nil out the delegate so that this
	// object doesn't receive any more messages
	// then release the webview
	webView.delegate = nil;
	[webView release];

	[keywords release];
	[location release];
	[loadingIndicator release];
	[url release];
	[nativeAdView release];
	
	if ([nativeAdViewController respondsToSelector:@selector(setDelegate:)]){
		[nativeAdViewController performSelector:@selector(setDelegate:) withObject:nil];
	}
	[nativeAdViewController release];
	
	[clickURL release];
	[excludeParams release];
	[newPageURLString release];
	
	[failURL release];
	
	[currentAdapter release];
	[lastAdapter release];
	[super dealloc];
}

-(UIWebView *)webView{
	if (!_webView){
		_webView = [[UIWebView alloc] initWithFrame:CGRectZero];
		_webView.backgroundColor = [UIColor clearColor];
		_webView.opaque = NO;
		_webView.delegate = self;
		// this turns off the scrollability of the webview
		if (!self.scrollable){
			self.scrollable = self.scrollable;
		}
	}
	return _webView;
}

-(void)setScrollable:(BOOL)_scrollable{
	scrollable = _scrollable;
	if (_webView){
		UIScrollView* _scrollView = nil;
		for (UIView* v in _webView.subviews){
			if ([v isKindOfClass:[UIScrollView class]]){
				_scrollView = (UIScrollView*)v; 
				break;
			}
		}
		if (_scrollView) {
			_scrollView.scrollEnabled = _scrollable;
			_scrollView.bounces = _scrollable;
		}		
	}
}

- (NSMutableDictionary *)productDictionary{
	if (!productDictionary)
		productDictionary = [[NSMutableDictionary alloc] init];
	return productDictionary;
}

/*
 * Override the view loading mechanism to create a WebView with overlaid activity indicator
 */
-(void)loadView {
	
	// create view substructure
	UIView *thisView = [[UIView alloc] initWithFrame:CGRectMake(0.0,0.0,self.size.width,self.size.height)];
	self.view = thisView;
	[thisView release];
	
}

- (void)loadAdWithURL:(NSURL *)adUrl{
	// only loads if its not already in the process of getting the assets
	if (!adLoading){
		adLoading = YES;
		self.loaded = FALSE;
		
		// remove the native view
		if (self.nativeAdView) {
			[self.nativeAdView removeFromSuperview];
			if ([self.nativeAdView respondsToSelector:@selector(setDelegate:)]) {
				[self.nativeAdView performSelector:@selector(setDelegate:) withObject:nil];
			}
			self.nativeAdView = nil;
		}
		
		//
		// create URL based on the parameters provided to us if a url was not passed in
		//
		if (!adUrl){
			NSString *urlString = [NSString stringWithFormat:@"http://%@/m/ad?v=3&udid=%@&q=%@&id=%@&payment=%d", 
								   HOSTNAME,
								   [[UIDevice currentDevice] uniqueIdentifier],
								   [keywords stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],
								   [adUnitId stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding],
								   [SKPaymentQueue canMakePayments]
								   ];
			
			// append on location if it has been passed in
			if (self.location){
				urlString = [urlString stringByAppendingFormat:@"&ll=%f,%f",location.coordinate.latitude,location.coordinate.longitude];
			}
			
			// add all the exclude parameters
			for (NSString *excludeParam in excludeParams){
				urlString = [urlString stringByAppendingFormat:@"&exclude=%@",excludeParam];
			}
			
			self.url = [NSURL URLWithString:urlString];
		}
		else {
			self.url = adUrl;
		}

		
		// inform delegate we are about to start loading...
		if ([self.delegate respondsToSelector:@selector(adControllerWillLoadAd:)]) {
			[self.delegate adControllerWillLoadAd:self];
		}
		
		// We load manually so that we can check for a special backfill header 
		// that instructs us to do some native things on occasion 
		NSLog(@"MOPUB: ad loading via %@", self.url);

		// start the spinner
		[self.loadingIndicator startAnimating];
		
		// fire off request
		NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:self.url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:3.0];
		
		// sets the user agent so that we know where the request is coming from !important for targeting!
		if ([request respondsToSelector:@selector(setValue:forHTTPHeaderField:)]) {
			NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
			NSString *systemName = [[UIDevice currentDevice] systemName];
			NSString *model = [[UIDevice currentDevice] model];
			NSString *bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"];
			NSString *appVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];			
			NSString *userAgentString = [NSString stringWithFormat:@"%@/%@ (%@; U; CPU %@ %@ like Mac OS X; %@)",
																	bundleName,appVersion,model,
																	systemName,systemVersion,[[NSLocale currentLocale] localeIdentifier]];
			[request setValue:userAgentString forHTTPHeaderField:@"User-Agent"];
		}		
		
		// autoreleased object
		[NSURLConnection connectionWithRequest:request delegate:self];
		
		[request release];
	}
}

-(void) loadAd{
	[self loadAdWithURL:nil];
}

-(void)refresh {
	// start afresh 
	[excludeParams removeAllObjects];
	// load the ad again
	[self loadAd];
}

- (void)closeAd{
	// act as though the application close of the ad is the same as the user's
	[self didSelectClose:nil];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	
	//
	// if the response is anything but a 200 (OK) or 300 (redirect) we call the response a failure and bail
	//
	if ([response respondsToSelector:@selector(statusCode)])
	{
		int statusCode = [((NSHTTPURLResponse *)response) statusCode];
		if (statusCode >= 400)
		{
			[connection cancel];  // stop connecting; no more delegate messages
			NSDictionary *errorInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:
												  NSLocalizedString(@"Server returned status code %d",@""),
												  statusCode]
										  forKey:NSLocalizedDescriptionKey];
			NSError *statusError = [NSError errorWithDomain:@"mopub.com"
								  code:statusCode
							  userInfo:errorInfo];
			[self connection:connection didFailWithError:statusError];
			return;
		}
	}
	
	// initialize the data
	[self.data setLength:0];
	
	if ([delegate respondsToSelector:@selector(adControllerDidReceiveResponseParams:)]){
		[delegate performSelector:@selector(adControllerDidReceiveResponseParams:) withObject:[(NSHTTPURLResponse*)response allHeaderFields]];
	}
	
	// grab the clickthrough URL from the headers as well 
	self.clickURL = [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:@"X-Clickthrough"];
	
	// grab the url string that should be intercepted for the launch of a new page (c.admob.com, c.google.com, etc)
	self.newPageURLString = [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:@"X-Launchpage"];
	
	// grab the fail URL for rollover from the headers as well
	NSString *failURLString = [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:@"X-Failurl"];
	if (failURLString)
		self.failURL = [NSURL URLWithString:failURLString];

	// check for ad types
	NSString* adTypeKey = [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:@"X-Adtype"];
	
	NSString *interceptLinksString = [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:@"X-Interceptlinks"];
	if (interceptLinksString){
		self.interceptLinks = [interceptLinksString boolValue];
	}

	NSString *scrollableString = [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:@"X-Scrollable"];
	if (scrollableString){
		self.scrollable = [scrollableString boolValue];
	}
	
	productIdentifier = [[(NSHTTPURLResponse*)response allHeaderFields] objectForKey:@"X-Productid"];
	
	
	if (!adTypeKey || [adTypeKey isEqual:@"html"]) {
		return;
	} 
	else if ([adTypeKey isEqualToString:@"clear"]) {
		self.loaded = TRUE;
		[self.loadingIndicator stopAnimating];
		adLoading = NO;
		[connection cancel];
//		[connection release];
		[self backfillWithNothing];
		return;
	}
					   
	
	Class adapterClass = [[MoPubNativeSDKRegistry sharedRegistry] adapterClassForNetworkType:adTypeKey];
	if (!adapterClass){
		adLoading = NO; // weird
		[connection cancel];
//		[connection release];
		[self loadAdWithURL:self.failURL];	
		return;
	} 

	self.loaded = TRUE;
	[self.loadingIndicator stopAnimating];
	adLoading = NO;
	[connection cancel];
//	[connection release];
					   
	MoPubNativeSDKAdapter *adapter = [[adapterClass alloc] initWithAdController:self];
	NSLog(@"adapterClass :%@",adapter);
	[adapter getAdWithParams:[(NSHTTPURLResponse *)response allHeaderFields]];
	self.lastAdapter = self.currentAdapter;
	self.currentAdapter = adapter;
	[adapter release];

}

// standard data appending
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)d {
	[self.data appendData:d];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	NSLog(@"MOPUB: failed to load ad content... %@", error);
	
	[self backfillWithNothing];
//	[connection release];
	adLoading = NO;
	[loadingIndicator stopAnimating];
	
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	// set the content into the webview	
	
	self.webView.delegate = self;
	[self.webView loadData:self.data MIMEType:@"text/html" textEncodingName:@"utf-8" baseURL:self.url];


	// print out the response for debugging purposes
	NSString *response = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
	NSLog(@"MOPUB: response %@",response);
	[response release];
	
	// set ad loading to be False
	adLoading = NO;
	
	// release the connection
//	[connection release];
	
	// if there is a productIdentifier, pre-fetch the info
	if (self.productIdentifier){
		[self preloadProductForProductIdentifier:self.productIdentifier];
	}
}

- (void)viewWillAppear:(BOOL)animated{
	[super viewWillAppear:animated];
}


- (void)viewDidAppear:(BOOL)animated{
	// tell the webpage that the webview has been presented to the user
	// this is a good place to fire of the tracking pixel and/or begin animations
	[self.webView stringByEvaluatingJavaScriptFromString:@"webviewDidAppear();"]; 
	[super viewDidAppear:animated];
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
    [super viewDidLoad];
	
	// activity indicator, placed in the center
	loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];

	loadingIndicator.center = self.view.center;
	loadingIndicator.hidesWhenStopped = YES;
	
	// fill up view with the webview
	self.webView.frame = self.view.frame; // fill up
	self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	
	// add them 
	[self.view addSubview:self.loadingIndicator];	
	
	// put the webview on the page but hide it until its loaded
	[self.view addSubview:self.webView];
	
	// if the ad has already been loaded or is in the process of being loaded
	// do nothing otherwise load the ad
	if (!adLoading && !loaded){
		[self loadAd];
	}
}

- (void)rotateToOrientation:(UIInterfaceOrientation)newOrientation{
	[self.currentAdapter rotateToOrientation:newOrientation];
}


// when the content has loaded, we stop the loading indicator
- (void)webViewDidFinishLoad:(UIWebView *)_webView {
	[self.loadingIndicator stopAnimating];
	[self.webView setNeedsDisplay];

	// show the webview because we know it has been loaded
	self.webView.hidden = NO;

}

- (void)didSelectClose:(id)sender{
	// tell the webpage that the webview has been dismissed by the user
	// this is a good place to record time spent on site
	[self.webView stringByEvaluatingJavaScriptFromString:@"webviewDidClose();"]; 
}


// Intercept special urls
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
	NSLog(@"MOPUB: shouldStartLoadWithRequest URL:%@ navigationType:%d", [[request URL] absoluteString], navigationType);
	NSURL *requestURL = [request URL];
	
	// intercept mopub specific urls mopub://close, mopub://finishLoad, mopub://failLoad
	if ([[requestURL scheme] isEqual:@"mopub"]){
		if ([[requestURL host] isEqual:@"close"]){
			// lets the delegate (self) that the webview would like to close itself, only really matter for interstital
			[self didSelectClose:nil];
			return NO;
		}
		else if ([[requestURL host] isEqual:@"finishLoad"]){
			//lets the delegate know that the the ad has succesfully loaded 
			loaded = YES;
			adLoading = NO;
			if ([self.delegate respondsToSelector:@selector(adControllerDidLoadAd:)]) {
				[self.delegate adControllerDidLoadAd:self];
			}
			self.webView.hidden = NO;
			return NO;
		}
		else if ([[requestURL host] isEqual:@"failLoad"]){
			//lets the delegate know that the the ad has failed to be loaded 
			loaded = YES;
			adLoading = NO;
			if ([self.delegate respondsToSelector:@selector(adControllerFailedLoadAd:)]) {
				[self.delegate adControllerFailedLoadAd:self];
			}
			self.webView.hidden = NO;
			return NO;
		}
		else if ([[requestURL host] isEqual:@"open"]){
			[self adClickHelper:[NSURL URLWithString:[requestURL query]]];
			return NO;
		}
		else if ([[requestURL host] isEqual:@"inapp"]){
			NSDictionary *queryDict = [self parseQuery:[requestURL query]];
			[self initiatePurchaseForProductIdentifier:[queryDict objectForKey:@"id"] 
											  quantity:[[queryDict objectForKey:@"num"] intValue]];
			return NO;
		}
		else if ([[requestURL host] isEqual:@"method"]){
			NSDictionary *queryDict = [self parseQuery:[requestURL query]];
			[self performSelectorString:[queryDict objectForKey:@"sel"]
						 withStringData:[queryDict objectForKey:@"data"]];
			return NO;
		 }
	} 	
	
	if (interceptLinks){
		if (navigationType == UIWebViewNavigationTypeOther){
			NSLog(@"Navigation Type: Other %@",self.newPageURLString);
			// interecepts special url that we want to intercept ex: c.admob.com
			if (self.newPageURLString && [[requestURL absoluteString] hasPrefix:self.newPageURLString]){
				[self adClickHelper:[request URL]];
				return NO;
			}
		}
		// interecept user clicks to open appropriately
		else if (navigationType == UIWebViewNavigationTypeLinkClicked){
			NSLog(@"Navigation Type: Click");
			[self adClickHelper:[request URL]];
			return NO;
		}
	}
	// other javascript loads, etc. 
	return YES;
}

- (void)adClickHelper:(NSURL *)desiredURL{
	// escape the redirect url
	NSString *redirectUrl = [self escapeURL:desiredURL];										
	
	// create ad click URL
	NSURL* adClickURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@&r=%@",
											  self.clickURL,
											  redirectUrl]];
	
	
	if ([self.delegate respondsToSelector:@selector(adControllerAdWillOpen:)]) {
		[self.delegate adControllerAdWillOpen:self];
	}
	
	
	// inited but release in the dealloc
	AdClickController *_adClickController = [[AdClickController alloc] initWithURL:adClickURL delegate:self]; 
	
	// signal to the delegate if it cares that the click controller is about to be presented
	if ([self.delegate respondsToSelector:@selector(willPresentModalViewForAd:)]){
		[self.delegate performSelector:@selector(willPresentModalViewForAd:) withObject:self];
	}
	
	// if the ad is being show as an interstitial then this view may load another modal view
	// otherwise, the ad is just a subview of what is on screen, so the parent should load the modal view
	if (_isInterstitial){
		[self presentModalViewController:_adClickController animated:YES];
	}
	else {
		[self.parent presentModalViewController:_adClickController animated:YES];
	}
	
	// signal to the delegate if it cares that the click controller has been presented
	if ([self.delegate respondsToSelector:@selector(didPresentModalViewForAd:)]){
		[self.delegate performSelector:@selector(didPresentModalViewForAd:) withObject:self];
	}
	
	[_adClickController release];
}


- (void)dismissModalViewForAdClickController:(AdClickController *)_adClickController{
	// signal to the delegate if it cares that the click controller is about to be torn down
	if ([self.delegate respondsToSelector:@selector(willPresentModalViewForAd:)]){
		[self.delegate performSelector:@selector(willPresentModalViewForAd:) withObject:self];
	}
	
	
	[_adClickController dismissModalViewControllerAnimated:YES];
	
	// signal to the delegate if it cares that the click controller has been torn down
	if ([self.delegate respondsToSelector:@selector(didPresentModalViewForAd:)]){
		[self.delegate performSelector:@selector(didPresentModalViewForAd:) withObject:self];
	}
	
}


- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
	NSLog(@"MOPUB: Ad load failed with error: %@", error);
}


#pragma mark -
#pragma mark Special backfill strategies: ADBannerView, display a solid color

- (void)backfillWithNothing {
	self.webView.backgroundColor = [UIColor clearColor];
	self.webView.hidden = YES;

	// let delegate know that the ad has failed to load
	if ([self.delegate respondsToSelector:@selector(adControllerFailedLoadAd:)]){
		[self.delegate adControllerFailedLoadAd:self];
	}
	
}

- (void)nativeAdLoadSucceededWithResults:(NSDictionary *)results {
	// Successful load. You can examine the results for interesting things.
	adLoading = NO;
	if ([self.delegate respondsToSelector:@selector(adControllerDidLoadAd:)]) {
		[self.delegate adControllerDidLoadAd:self];
	}	
}

- (void)nativeAdTrackAdClick{
	[self nativeAdTrackAdClickWithURL:self.clickURL];
}

- (void)nativeAdTrackAdClickWithURL:(NSString *)adClickURL{
	NSURLRequest* clickURLRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:adClickURL]];
	[[[NSURLConnection alloc] initWithRequest:clickURLRequest delegate:nil] autorelease];
	NSLog(@"MOPUB: Tracking click %@",[clickURLRequest URL]);
	
	// pass along to our own delegate
	if ([self.delegate respondsToSelector:@selector(adControllerAdWillOpen:)]) {
		[self.delegate adControllerAdWillOpen:self];
	}
}

- (void)nativeAdLoadFailedwithError:(NSError *)error{
	if (self.nativeAdView) {
		[self.nativeAdView removeFromSuperview];
		self.nativeAdView = nil;
	}
	// then try another ad call to verify see if there is another ad creative that can fill this spot
	// if this fails the delegate will be notified
	[self loadAdWithURL:self.failURL];	
}

- (void)rollOver{
	[self nativeAdLoadFailedwithError:nil];
}

# pragma
# pragma Dynamic Method Call
# pragma
 - (void)performSelectorString:(NSString *)selectorString withStringData:(NSString *)stringData{
	SEL eventSelector = NSSelectorFromString(selectorString);

	if ([self.delegate respondsToSelector:eventSelector]) {
		[self.delegate performSelector:eventSelector withObject:stringData];
	}
	else {
		NSLog(@"MOPUB: Delegate does not implement function %@", selectorString);
	}
 }



# pragma 
# pragma In-App Purchases
# pragma
- (void)initiatePurchaseForProductIdentifier:(NSString *)_productIdentifier quantity:(NSInteger)quantity{
	if (![self.productDictionary objectForKey:_productIdentifier])
		[self requestProductDataForProductIdentifier:_productIdentifier autoPurchase:YES];
	else
		[self startPaymentForProductIdentifier:_productIdentifier];

}

- (void)preloadProductForProductIdentifier:(NSString *)_productIdentifier{
	if (![self.productDictionary objectForKey:_productIdentifier])
		[self requestProductDataForProductIdentifier:(NSString *)_productIdentifier autoPurchase:NO];
}

- (void)requestProductDataForProductIdentifier:(NSString *)_productIdentifier autoPurchase:(BOOL)autoPurchase
{
	SKProductsRequest *request= [[SKProductsRequest alloc] initWithProductIdentifiers: [NSSet setWithObject:_productIdentifier]];
	request.delegate = self;
	autoPurchaseProduct = autoPurchase;
	[request start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    // populate UI
	SKProduct *_product = [response.products objectAtIndex:0];
	for (SKProduct *p in response.products){
		[self.productDictionary setObject:@"1" forKey:p.productIdentifier];
	}
	if (autoPurchaseProduct){
		[self startPaymentForProductIdentifier:_product.productIdentifier];
	}
    [request autorelease];					  
}

- (void)startPaymentForProductIdentifier:(NSString *)_productIdentifier{
	SKMutablePayment *payment = [SKMutablePayment paymentWithProductIdentifier:_productIdentifier];

	[[SKPaymentQueue defaultQueue] addPayment:payment];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions)
    {
        switch (transaction.transactionState)
        {
            case SKPaymentTransactionStatePurchased:
                [self completeTransaction:transaction];
                break;
            case SKPaymentTransactionStateFailed:
                [self failedTransaction:transaction];
                break;
            case SKPaymentTransactionStateRestored:
                [self restoreTransaction:transaction];
            default:
                break;
        }
    }
}

- (void) completeTransaction: (SKPaymentTransaction *)transaction
{
	// Your application should implement these two methods.
    [self recordTransaction: transaction];	
}

- (void) restoreTransaction: (SKPaymentTransaction *)transaction
{
    [self recordTransaction: transaction];
    [self provideContent: transaction.originalTransaction.payment.productIdentifier];
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}


- (void) failedTransaction: (SKPaymentTransaction *)transaction
{
    if (transaction.error.code != SKErrorPaymentCancelled)
    {
        // Optionally, display an error here.
    }
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

- (void)recordTransaction:(SKPaymentTransaction *)transaction{
	NSLog(@"record transaction in adcontroller: %@",transaction);
}

- (void)provideContent:(NSString *)_productIdentifier{
	NSLog(@"provide product in adcontroller:%@", _productIdentifier);
}

- (NSDictionary *)parseQuery:(NSString *)query{
	NSMutableDictionary *queryDict = [[NSMutableDictionary alloc] initWithCapacity:1];
	NSArray *queryElements = [query componentsSeparatedByString:@"&"];
	for (NSString *element in queryElements) {
		NSArray *keyVal = [element componentsSeparatedByString:@"="];
		NSString *key = [keyVal objectAtIndex:0];
		NSString *value = [keyVal lastObject];
		[queryDict setObject:[value stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] 
					  forKey:key];
	}
	return [queryDict autorelease];
}

- (NSString *)escapeURL:(NSURL *)urlIn{
	NSMutableString *redirectUrl = [NSMutableString stringWithString:[urlIn absoluteString]];
	NSRange wholeString = NSMakeRange(0, [redirectUrl length]);
	[redirectUrl replaceOccurrencesOfString:@"&" withString:@"%26" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"+" withString:@"%2B" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"," withString:@"%2C" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"/" withString:@"%2F" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@":" withString:@"%3A" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@";" withString:@"%3B" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"=" withString:@"%3D" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"?" withString:@"%3F" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"@" withString:@"%40" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@" " withString:@"%20" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"\t" withString:@"%09" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"#" withString:@"%23" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"<" withString:@"%3C" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@">" withString:@"%3E" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"\"" withString:@"%22" options:NSCaseInsensitiveSearch range:wholeString];
	[redirectUrl replaceOccurrencesOfString:@"\n" withString:@"%0A" options:NSCaseInsensitiveSearch range:wholeString];
	
	return redirectUrl;
}

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

// we should tell the webview that the application would like to close
// this may be called more than once, so in our logs we'll assume the last close the it correct one
- (void)applicationWillResign:(id)sender{
	[self didSelectClose:sender];
}

@end