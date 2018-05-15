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

/**
    BLETransfer.
*/
@interface BLETransfer : NSObject

/**
    BLETransfer is not available for current version
 */
@property (nonatomic,readonly) id<BLEStorage> dataStorage;


/**
 * @method meshDataServiceUUID
 *
 * @discussion
 *       defaultServiceUUID for BLEScanner. set yours to BLEScannerDelegate datasource
 *
 * @return defaultServiceUUID
 */
+ (CBUUID *) meshDataServiceUUID;


/**
 * @method initWithDataStorage:
 *
 * @discussion
 *  not available for current version, keep nil.
 *
 * @param dataStorage protocol for data storage.
 * @return dataStorage instance
 */
- (instancetype) initWithDataStorage:(id<BLEStorage>)dataStorage;

/**
 * @return success
 */
- (BOOL) start;
- (void) stop;

@end
