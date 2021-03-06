//
//  MKStoreKit.m
//  MKStoreKit 6.0
//
//  Copyright 2014 Steinlogic Consulting and Training Pte Ltd. All rights reserved.
//    File created using Singleton Xcode Template by Mugunth Kumar (http://blog.mugunthkumar.com)
//  More information about this template on the post http://mk.sg/89
//  Permission granted to do anything, commercial/non-commercial with this file apart from removing the line/URL above
//  Created by Mugunth Kumar (@mugunthkumar) on 17 Nov 2014.
//  Copyright (C) 2011-2020 by Steinlogic Consulting And Training Pte Ltd.

//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

//  As a side note on using this code, you might consider giving some credit to me by
//    1) linking my website from your app's website
//    2) or crediting me inside the app's credits page
//    3) or a tweet mentioning @mugunthkumar
//    4) A paypal donation to mugunth.kumar@gmail.com
//
//  A note on redistribution
//    if you are re-publishing after editing, please retain the above copyright notices

#import "MKStoreKit.h"

@import StoreKit;

NSString *const kMKStoreKitProductsAvailableNotification = @"com.mugunthkumar.mkstorekit.productsavailable";
NSString *const kMKStoreKitProductPurchasedNotification = @"com.mugunthkumar.mkstorekit.productspurchased";
NSString *const kMKStoreKitProductPurchaseFailedNotification = @"com.mugunthkumar.mkstorekit.productspurchasefailed";
NSString *const kMKStoreKitProductPurchaseDeferredNotification = @"com.mugunthkumar.mkstorekit.productspurchasedeferred";
NSString *const kMKStoreKitRestoredPurchasesNotification = @"com.mugunthkumar.mkstorekit.restoredpurchases";
NSString *const kMKStoreKitRestoringPurchasesFailedNotification = @"com.mugunthkumar.mkstorekit.failedrestoringpurchases";
NSString *const kMKStoreKitReceiptValidationFailedNotification = @"com.mugunthkumar.mkstorekit.failedvalidatingreceipts";
NSString *const kMKStoreKitSubscriptionExpiredNotification = @"com.mugunthkumar.mkstorekit.subscriptionexpired";
NSString *const kMKStoreKitDownloadProgressNotification = @"com.mugunthkumar.mkstorekit.downloadprogress";
NSString *const kMKStoreKitDownloadCompletedNotification = @"com.mugunthkumar.mkstorekit.downloadcompleted";

NSString *const kSandboxServer = @"https://sandbox.itunes.apple.com/verifyReceipt";
NSString *const kLiveServer = @"https://buy.itunes.apple.com/verifyReceipt";

NSString *const kOriginalAppVersionKey = @"SKOrigBundleRef"; // Obfuscating record key name

static NSDictionary *errorDictionary;

@interface MKStoreKit (/*Private Methods*/) <SKProductsRequestDelegate, SKPaymentTransactionObserver>

@property NSMutableDictionary *purchaseRecord;
@property (nonatomic, retain, readwrite) NSData *receiptData;
@property (nonatomic, retain, readwrite) NSMutableArray *restoredPurchases;
@property (nonatomic, retain, readwrite) NSMutableArray<SKProduct *> *products;
@property (nonatomic, copy) void(^refreshHandler)(BOOL);

@end

@implementation MKStoreKit

#pragma mark - getter

- (NSMutableArray<SKProduct *> *)products {

    if (!_products) {
        _products = [NSMutableArray array];
    }
    return _products;
}

- (NSArray<SKProduct *> *)availableProducts {

    return self.products;
}

- (NSMutableArray *)restoredPurchases {
    
    if (!_restoredPurchases) {
        _restoredPurchases = [NSMutableArray array];
    }
    return _restoredPurchases;
}

#pragma mark -
#pragma mark Singleton Methods

+ (MKStoreKit *)sharedKit {
    static MKStoreKit *_sharedKit;
    if (!_sharedKit) {
        static dispatch_once_t oncePredicate;
        dispatch_once(&oncePredicate, ^{
            _sharedKit = [[super allocWithZone:nil] init];
            [[SKPaymentQueue defaultQueue] addTransactionObserver:_sharedKit];
            [_sharedKit restorePurchaseRecord];
#if TARGET_OS_IPHONE
            [[NSNotificationCenter defaultCenter] addObserver:_sharedKit
                                                     selector:@selector(savePurchaseRecord)
                                                         name:UIApplicationDidEnterBackgroundNotification object:nil];
#elif TARGET_OS_MAC
            [[NSNotificationCenter defaultCenter] addObserver:_sharedKit
                                                     selector:@selector(savePurchaseRecord)
                                                         name:NSApplicationDidResignActiveNotification object:nil];
#endif
            
            [_sharedKit startValidatingReceiptsAndUpdateLocalStore];
        });
    }
    
    return _sharedKit;
}

+ (id)allocWithZone:(NSZone *)zone {
    return [self sharedKit];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

#pragma mark -
#pragma mark Initializer

+ (void)initialize {
    errorDictionary = @{@(21000) : @"The App Store could not read the JSON object you provided.",
                        @(21002) : @"The data in the receipt-data property was malformed or missing.",
                        @(21003) : @"The receipt could not be authenticated.",
                        @(21004) : @"The shared secret you provided does not match the shared secret on file for your accunt.",
                        @(21005) : @"The receipt server is not currently available.",
                        @(21006) : @"This receipt is valid but the subscription has expired.",
                        @(21007) : @"This receipt is from the test environment.",
                        @(21008) : @"This receipt is from the production environment."};
}

#pragma mark -
#pragma mark Helpers

+ (NSDictionary *)configs {
    return [NSDictionary dictionaryWithContentsOfFile:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"MKStoreKitConfigs.plist"]];
}


#pragma mark -
#pragma mark Store File Management

- (NSString *)purchaseRecordFilePath {
    NSString *documentDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documentDirectory stringByAppendingPathComponent:@"purchaserecord.plist"];
}

- (void)restorePurchaseRecord {
    self.purchaseRecord = (NSMutableDictionary *)[[NSKeyedUnarchiver unarchiveObjectWithFile:[self purchaseRecordFilePath]] mutableCopy];
    if (self.purchaseRecord == nil) {
        self.purchaseRecord = [NSMutableDictionary dictionary];
    }
    NSLog(@"[PAYMENT] %@", self.purchaseRecord);
}

- (void)savePurchaseRecord {
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.purchaseRecord];
#if TARGET_OS_IPHONE
    BOOL success = [data writeToFile:[self purchaseRecordFilePath] options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:&error];
#elif TARGET_OS_MAC
    BOOL success = [data writeToFile:[self purchaseRecordFilePath] options:NSDataWritingAtomic error:&error];
#endif
    
    if (!success) {
        NSLog(@"[PAYMENT] Failed to remember data record");
    }
    
    NSLog(@"[PAYMENT] %@", self.purchaseRecord);
}

#pragma mark -
#pragma mark Feature Management

- (BOOL)isProductPurchased:(NSString *)productId {
    return [self.purchaseRecord.allKeys containsObject:productId];
}

-(NSDate*) expiryDateForProduct:(NSString*) productId {
    
    NSNumber *expiresDateMs = self.purchaseRecord[productId];
    if ([expiresDateMs isKindOfClass:NSNull.class]) {
        return NSDate.date;
    } else {
        return [NSDate dateWithTimeIntervalSince1970:[expiresDateMs doubleValue] / 1000.0f];
    }
}

- (NSNumber *)availableCreditsForConsumable:(NSString *)consumableId {
    return self.purchaseRecord[consumableId];
}

- (NSNumber *)consumeCredits:(NSNumber *)creditCountToConsume identifiedByConsumableIdentifier:(NSString *)consumableId {
    NSNumber *currentConsumableCount = self.purchaseRecord[consumableId];
    currentConsumableCount = @([currentConsumableCount doubleValue] - [creditCountToConsume doubleValue]);
    self.purchaseRecord[consumableId] = currentConsumableCount;
    [self savePurchaseRecord];
    return currentConsumableCount;
}

- (void)setDefaultCredits:(NSNumber *)creditCount forConsumableIdentifier:(NSString *)consumableId {
    if (self.purchaseRecord[consumableId] == nil) {
        self.purchaseRecord[consumableId] = creditCount;
        [self savePurchaseRecord];
    }
}

#pragma mark -
#pragma mark Start requesting for available in app purchases

- (void)startProductRequestWithProductIdentifiers:(NSArray*) items {
    
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                          initWithProductIdentifiers:[NSSet setWithArray:items]];
    productsRequest.delegate = self;
    [productsRequest start];
}


- (void)startProductRequest {
    NSMutableArray *productsArray = [NSMutableArray array];
    NSArray *consumables = [[MKStoreKit configs][@"Consumables"] allKeys];
    NSArray *others = [MKStoreKit configs][@"Others"];
    
    [productsArray addObjectsFromArray:consumables];
    [productsArray addObjectsFromArray:others];
    
    [self startProductRequestWithProductIdentifiers:productsArray];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    if (response.invalidProductIdentifiers.count > 0) {
        NSLog(@"[PAYMENT] Invalid Product IDs: %@", response.invalidProductIdentifiers);
    }
    
    [self.products addObjectsFromArray:response.products];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMKStoreKitProductsAvailableNotification
                                                        object:self.availableProducts];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    NSLog(@"[PAYMENT] Product request failed with error: %@", error);
    if([request isKindOfClass:[SKReceiptRefreshRequest class]]) {
        if (self.refreshHandler) {
            self.refreshHandler(NO);
            self.refreshHandler = nil;
        }
    }
}

#pragma mark -
#pragma mark Restore Purchases

- (void)restorePurchases {
    [self.restoredPurchases removeAllObjects];
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    [[NSNotificationCenter defaultCenter] postNotificationName:kMKStoreKitRestoringPurchasesFailedNotification object:error userInfo:@{@"message":error.localizedDescription ?: @""}];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    [[NSNotificationCenter defaultCenter] postNotificationName:kMKStoreKitRestoredPurchasesNotification object:nil userInfo:@{@"restoredPurchases":self.restoredPurchases}];
}

#pragma mark -
#pragma mark Initiate a Purchase

- (void)initiatePaymentRequestForProductWithIdentifier:(NSString *)productId {
    if (!self.availableProducts) {
        // TODO: FIX ME
        // Initializer might be running or internet might not be available
        NSLog(@"[PAYMENT] No products are available. Did you initialize MKStoreKit by calling [[MKStoreKit sharedKit] startProductRequest]?");
    }
    
    if (![SKPaymentQueue canMakePayments]) {
#if TARGET_OS_IPHONE
        UIAlertController *controller = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"In App Purchasing Disabled", @"")
                                                                            message:NSLocalizedString(@"Check your parental control settings and try again later", @"") preferredStyle:UIAlertControllerStyleAlert];
        
        [[UIApplication sharedApplication].keyWindow.rootViewController
         presentViewController:controller animated:YES completion:nil];
#elif TARGET_OS_MAC
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NSLocalizedString(@"In App Purchasing Disabled", @"");
        alert.informativeText = NSLocalizedString(@"Check your parental control settings and try again later", @"");
        [alert runModal];
#endif
        return;
    }
    
    [self.availableProducts enumerateObjectsUsingBlock:^(SKProduct *thisProduct, NSUInteger idx, BOOL *stop) {
        if ([thisProduct.productIdentifier isEqualToString:productId]) {
            *stop = YES;
            SKPayment *payment = [SKPayment paymentWithProduct:thisProduct];
            [[SKPaymentQueue defaultQueue] addPayment:payment];
        }
    }];
}

#pragma mark -
#pragma mark Receipt validation

- (void)refreshAppStoreReceipt {
    SKReceiptRefreshRequest *refreshReceiptRequest = [[SKReceiptRefreshRequest alloc] initWithReceiptProperties:nil];
    refreshReceiptRequest.delegate = self;
    [refreshReceiptRequest start];
}

- (void)refreshAppStoreReceipt:(void (^)(BOOL))completionHandler {
    self.refreshHandler = completionHandler;
    [self refreshAppStoreReceipt];
}

- (void)requestDidFinish:(SKRequest *)request {
    // SKReceiptRefreshRequest
    if([request isKindOfClass:[SKReceiptRefreshRequest class]]) {
        NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
        if ([[NSFileManager defaultManager] fileExistsAtPath:[receiptUrl path]]) {
            NSLog(@"[PAYMENT] App receipt exists. Preparing to validate and update local stores.");
            [self startValidatingReceiptsAndUpdateLocalStore];
            if (self.refreshHandler) {
                self.refreshHandler(YES);
                self.refreshHandler = nil;
            }
        } else {
            NSLog(@"[PAYMENT] Receipt request completed but there is no receipt. The user may have refused to login, or the reciept is missing.");
            // Disable features of your app, but do not terminate the app
            if (self.refreshHandler) {
                self.refreshHandler(NO);
                self.refreshHandler = nil;
            }
        }
    }
}

- (void)loadReceiptData {
    
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSError *receiptError;
    BOOL isPresent = [receiptURL checkResourceIsReachableAndReturnError:&receiptError];
    if (!isPresent) {
        // No receipt - In App Purchase was never initiated
        NSLog(@"[PAYMENT] No receipt.");
        return;
    }
    
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
    if (!receiptData) {
        // Validation fails
        NSLog(@"[PAYMENT] Receipt exists but there is no data available. Try refreshing the reciept payload and then checking again.");
        return;
    }
    
    NSLog(@"[PAYMENT] has receipt: %@.", receiptData);
    self.receiptData = receiptData;
}

- (void)startValidatingAppStoreReceiptWithCompletionHandler:(void (^)(NSArray *receipts, NSError *error)) completionHandler {
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSError *receiptError;
    BOOL isPresent = [receiptURL checkResourceIsReachableAndReturnError:&receiptError];
    if (!isPresent) {
        // No receipt - In App Purchase was never initiated
        completionHandler(nil, nil);
        return;
    }
    
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
    if (!receiptData) {
        // Validation fails
        NSLog(@"[PAYMENT] Receipt exists but there is no data available. Try refreshing the reciept payload and then checking again.");
        completionHandler(nil, nil);
        return;
    }
    
    NSError *error;
    NSMutableDictionary *requestContents = [NSMutableDictionary dictionaryWithObject:
                                            [receiptData base64EncodedStringWithOptions:0] forKey:@"receipt-data"];
    NSString *sharedSecret = [MKStoreKit configs][@"SharedSecret"];
    if (sharedSecret) requestContents[@"password"] = sharedSecret;
    
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents options:0 error:&error];
    
#ifdef DEBUG
    NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kSandboxServer]];
#else
    NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLiveServer]];
#endif
    
    [storeRequest setHTTPMethod:@"POST"];
    [storeRequest setHTTPBody:requestData];
    [storeRequest setCachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    [[session dataTaskWithRequest:storeRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            NSInteger status = [jsonResponse[@"status"] integerValue];
            
            if (jsonResponse[@"receipt"] != [NSNull null]) {
                NSString *originalAppVersion = jsonResponse[@"receipt"][@"original_application_version"];
                if (nil != originalAppVersion) {
                    [self.purchaseRecord setObject:originalAppVersion forKey:kOriginalAppVersionKey];
                    [self savePurchaseRecord];
                }
                else {
                    completionHandler(nil, nil);
                }
            }
            else {
                completionHandler(nil, nil);
            }
            
            if (status != 0) {
                NSError *error = [NSError errorWithDomain:@"unlimited.free.speedvpn" code:status
                                                 userInfo:@{NSLocalizedDescriptionKey : errorDictionary[@(status)]}];
                completionHandler(nil, error);
            } else {
                NSMutableArray *receipts = [jsonResponse[@"latest_receipt_info"] mutableCopy];
                if (jsonResponse[@"receipt"] != [NSNull null]) {
                    NSArray *inAppReceipts = jsonResponse[@"receipt"][@"in_app"];
                    [receipts addObjectsFromArray:inAppReceipts];
                    completionHandler(receipts, nil);
                } else {
                    completionHandler(nil, nil);
                }
            }
        } else {
            completionHandler(nil, error);
        }
    }] resume];
}

- (void)validatingAppStoreReceiptWithCompletionHandler:(void (^)(NSArray *receipts, NSError *error))completionHandler {

    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSError *receiptError;
    BOOL isPresent = [receiptURL checkResourceIsReachableAndReturnError:&receiptError];
    if (!isPresent) {
        // No receipt - In App Purchase was never initiated
        completionHandler(nil, nil);
        return;
    }

    NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
    if (!receiptData) {
        // Validation fails
        NSLog(@"[PAYMENT] Receipt exists but there is no data available. Try refreshing the reciept payload and then checking again.");
        completionHandler(nil, nil);
        return;
    }

    NSError *error;
    NSMutableDictionary *requestContents = [NSMutableDictionary dictionaryWithObject:
                                            [receiptData base64EncodedStringWithOptions:0] forKey:@"receipt-data"];
    NSString *sharedSecret = [MKStoreKit configs][@"SharedSecret"];
    if (sharedSecret) requestContents[@"password"] = sharedSecret;

    NSData *requestData = [NSJSONSerialization dataWithJSONObject:requestContents options:0 error:&error];

#ifdef DEBUG
    NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kSandboxServer]];
#else
    NSMutableURLRequest *storeRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kLiveServer]];
#endif

    [storeRequest setHTTPMethod:@"POST"];
    [storeRequest setHTTPBody:requestData];

    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    [[session dataTaskWithRequest:storeRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error) {
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            NSInteger status = [jsonResponse[@"status"] integerValue];
            
           

            if (status != 0) {
                NSError *error = [NSError errorWithDomain:@"unlimited.speedvpn" code:status
                                                 userInfo:@{NSLocalizedDescriptionKey : errorDictionary[@(status)]?:@"unknown error"}];
                completionHandler(nil, error);
            } else {

                id receipt = nil;
                if (jsonResponse[@"latest_expired_receipt_info"]) {
                    receipt = jsonResponse[@"latest_expired_receipt_info"];
                } else if (jsonResponse[@"latest_receipt_info"]) {
                    receipt = jsonResponse[@"latest_receipt_info"];
                } else if (jsonResponse[@"receipt"] != [NSNull null]) {
                    receipt = jsonResponse[@"receipt"][@"in_app"];
                }

                if ([receipt isKindOfClass:[NSArray class]]) {
                    completionHandler(receipt, nil);
                } else if ([receipt isKindOfClass:[NSDictionary class]]) {
                    completionHandler(@[receipt], nil);
                } else {
                    completionHandler(nil, nil);
                }
            }
        } else {
            completionHandler(nil, error);
        }
    }] resume];
}

- (BOOL)purchasedAppBeforeVersion:(NSString *)requiredVersion {
    NSString *actualVersion = [self.purchaseRecord objectForKey:kOriginalAppVersionKey];
    
    if ([requiredVersion compare:actualVersion options:NSNumericSearch] == NSOrderedDescending) {
        // actualVersion is lower than the requiredVersion
        return YES;
    } else return NO;
}

- (void)startValidatingReceiptsAndUpdateLocalStore {
    // get receipt data, add by leo
    [self loadReceiptData];
    [self startValidatingAppStoreReceiptWithCompletionHandler:^(NSArray *receipts, NSError *error) {
        if (error) {
            NSLog(@"[PAYMENT] Receipt validation failed with error: %@", error);
            [[NSNotificationCenter defaultCenter] postNotificationName:kMKStoreKitReceiptValidationFailedNotification object:error];
        } else {
            __block BOOL purchaseRecordDirty = NO;
            [receipts enumerateObjectsUsingBlock:^(NSDictionary *receiptDictionary, NSUInteger idx, BOOL *stop) {
                NSString *productIdentifier = receiptDictionary[@"product_id"];
                NSNumber *expiresDateMs = receiptDictionary[@"expires_date_ms"];
                if (expiresDateMs) { // renewable subscription
                    NSNumber *previouslyStoredExpiresDateMs = self.purchaseRecord[productIdentifier];
                    if (!previouslyStoredExpiresDateMs ||
                        [previouslyStoredExpiresDateMs isKindOfClass:NSNull.class]) {
                        self.purchaseRecord[productIdentifier] = expiresDateMs;
                        purchaseRecordDirty = YES;
                    } else {
                        if ([expiresDateMs doubleValue] > [previouslyStoredExpiresDateMs doubleValue]) {
                            self.purchaseRecord[productIdentifier] = expiresDateMs;
                            purchaseRecordDirty = YES;
                        }
                    }
                }
            }];
            
            if (purchaseRecordDirty) {
                [self savePurchaseRecord];
            }
            
            [self.purchaseRecord enumerateKeysAndObjectsUsingBlock:^(NSString *productIdentifier, NSNumber *expiresDateMs, BOOL *stop) {
                if (![expiresDateMs isKindOfClass: [NSNull class]]) {
                    if ([[NSDate date] timeIntervalSince1970] > [expiresDateMs doubleValue]) {
                        [[NSNotificationCenter defaultCenter] postNotificationName:kMKStoreKitSubscriptionExpiredNotification object:productIdentifier];
                    }
                }
            }];
        }
    }];
}

#pragma mark -
#pragma mark Transaction Observers

- (BOOL)paymentQueue:(SKPaymentQueue *)queue shouldAddStorePayment:(SKPayment *)payment forProduct:(SKProduct *)product {
    return YES;
}

// TODO: FIX ME
- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads {
    [downloads enumerateObjectsUsingBlock:^(SKDownload *thisDownload, NSUInteger idx, BOOL *stop) {
        SKDownloadState state;
#if TARGET_OS_IPHONE
        state = thisDownload.downloadState;
#elif TARGET_OS_MAC
        state = thisDownload.state;
#endif
        switch (state) {
            case SKDownloadStateActive:
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:kMKStoreKitDownloadProgressNotification
                 object:thisDownload
                 userInfo:@{thisDownload.transaction.payment.productIdentifier: @(thisDownload.progress)}];
                break;
            case SKDownloadStateFinished: {
                NSString *documentDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
                NSString *contentDirectoryForThisProduct =
                [[documentDirectory stringByAppendingPathComponent:@"Contents"]
                 stringByAppendingPathComponent:thisDownload.transaction.payment.productIdentifier];
                [NSFileManager.defaultManager createDirectoryAtPath:contentDirectoryForThisProduct withIntermediateDirectories:YES attributes:nil error:nil];
                NSError *error = nil;
                [NSFileManager.defaultManager moveItemAtURL:thisDownload.contentURL
                                                      toURL:[NSURL URLWithString:contentDirectoryForThisProduct]
                                                      error:&error];
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:kMKStoreKitDownloadCompletedNotification
                 object:thisDownload
                 userInfo:@{thisDownload.transaction.transactionIdentifier: contentDirectoryForThisProduct}];
                [queue finishTransaction:thisDownload.transaction];
            }
                
                break;
            default:
                break;
        }
    }];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
                
            case SKPaymentTransactionStatePurchasing:
                break;
                
            case SKPaymentTransactionStateDeferred:
                [self deferredTransaction:transaction inQueue:queue];
                break;
                
            case SKPaymentTransactionStateFailed:
                [self failedTransaction:transaction inQueue:queue];
                break;
                
            case SKPaymentTransactionStatePurchased:
            case SKPaymentTransactionStateRestored: {
                
                if (transaction.downloads.count > 0) {
                    [SKPaymentQueue.defaultQueue startDownloads:transaction.downloads];
                } else {
                    [queue finishTransaction:transaction];
                }
                
                NSDictionary *availableConsumables = [MKStoreKit configs][@"Consumables"];
                NSArray *consumables = [availableConsumables allKeys];
                if ([consumables containsObject:transaction.payment.productIdentifier]) {
                    
                    NSDictionary *thisConsumable = availableConsumables[transaction.payment.productIdentifier];
                    NSString *consumableId = thisConsumable[@"ConsumableId"];
                    NSNumber *consumableCount = thisConsumable[@"ConsumableCount"];
                    NSNumber *currentConsumableCount = self.purchaseRecord[consumableId];
                    consumableCount = @([consumableCount doubleValue] + [currentConsumableCount doubleValue]);
                    self.purchaseRecord[consumableId] = consumableCount;
                } else {
                    // non-consumable or subscriptions
                    // subscriptions will eventually contain the expiry date after the receipt is validated during the next run
                    self.purchaseRecord[transaction.payment.productIdentifier] = [NSNull null];
                }
                
                [self savePurchaseRecord];
                if (transaction.transactionState == SKPaymentTransactionStatePurchased) {
                    NSLog(@"[PAYMENT] purchase '%@' with order id: %@", transaction.payment.productIdentifier, transaction.transactionIdentifier);
                    [[NSNotificationCenter defaultCenter] postNotificationName:kMKStoreKitProductPurchasedNotification
                                                                        object:transaction.payment.productIdentifier
                                                                      userInfo:@{@"transactionIdentifier":transaction.transactionIdentifier?:@"unknown identifier"}];
                } else {
                    [self.restoredPurchases addObject:@{
                                                        @"productIdentifier":transaction.payment.productIdentifier ?: @"unknown identifier",
                                                        @"transactionIdentifier":transaction.transactionIdentifier ?: @"unknown identifier",
                                                        @"originalTransaction":transaction.originalTransaction.transactionIdentifier ?: @"unknown identifier",
                                                        }];
                    NSLog(@"[PAYMENT] restore '%@' with order id: %@", transaction.payment.productIdentifier, transaction.transactionIdentifier);
                }
            } break;
        }
    }
}

- (void)failedTransaction:(SKPaymentTransaction *)transaction inQueue:(SKPaymentQueue *)queue {
    NSLog(@"[PAYMENT] Transaction Failed with error: %@", transaction.error);
    [queue finishTransaction:transaction];
    [[NSNotificationCenter defaultCenter] postNotificationName:kMKStoreKitProductPurchaseFailedNotification
                                                        object:transaction.payment.productIdentifier
                                                      userInfo:@{@"message":transaction.error.localizedDescription ?: @""}];
}

- (void)deferredTransaction:(SKPaymentTransaction *)transaction inQueue:(SKPaymentQueue *)queue {
    NSLog(@"[PAYMENT] Transaction Deferred: %@", transaction);
    [[NSNotificationCenter defaultCenter] postNotificationName:kMKStoreKitProductPurchaseDeferredNotification
                                                        object:transaction.payment.productIdentifier];
}

@end

