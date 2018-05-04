//
//  BLEBroadcast.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/25.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import "BLETransfer.h"
#import <CoreLocation/CoreLocation.h>

@class BLEBroadcast;
@protocol BLEBroadcastDelegate <NSObject>

@optional

- (void)bleCast: (BLEBroadcast*)bleCast didHopPayload: (NSData*)payload index: (uint8_t)index;

@end

@interface BLEBroadcast : BLETransfer <CBPeripheralManagerDelegate>

@property (nonatomic, readonly) BOOL broadcasting;
@property (nonatomic, weak) NSObject<BLEBroadcastDelegate> *delegate;

- (BOOL)setMeshCast:(CBUUID *)uuid data:(NSData *)data;
- (void)removeMeshCast:(CBUUID *)uuid;

- (void)meshWakeUp:(CLBeaconRegion *)region;
- (void)stopMeshWakeUp:(CLBeaconRegion *)region;
@end
