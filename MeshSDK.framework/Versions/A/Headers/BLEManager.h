//
//  BLEManager.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/11.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BLEBroadcast.h"
#import "BLEScanner.h"
#import "BLECrypto.h"
#import "BLEUidPacket.h"
#import "BLEStorage.h"

@interface BLEManager : NSObject

@property (nonatomic, weak, readonly) id<BLEStorage> dataStorage;

- (instancetype) initWithDataStorage:(id<BLEStorage>)dataStorage;

- (void) start;
- (void) stop;

@end
