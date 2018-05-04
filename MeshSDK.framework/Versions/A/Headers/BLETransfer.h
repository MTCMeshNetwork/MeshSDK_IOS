//
//  BLETransfer.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/11.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BLEStorage.h"
#import <CoreBluetooth/CoreBluetooth.h>

@interface BLETransfer : NSObject

@property (nonatomic,readonly) id<BLEStorage> dataStorage;

+ (CBUUID *) meshDataServiceUUID;

- (instancetype) initWithDataStorage:(id<BLEStorage>)dataStorage;

/**
 * @return success
 */
- (BOOL) start;
- (void) stop;

@end
