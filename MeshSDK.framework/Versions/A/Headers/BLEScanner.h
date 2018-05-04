//
//  BLEScanner.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/11.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BLETransfer.h"

extern const NSNotificationName ScannerDataNotification;

@class BLEScanner;
@protocol BLEScannerDelegate <NSObject>

@optional

- (NSArray <CBUUID *>*)supportMeshServiceUUIDs;
- (void)bleScanner:(BLEScanner*)scanner  didDiscoverUUID:(CBUUID *)uuid advertisementData:(NSData *)advertisementData RSSI:(NSNumber *)RSSI;

@end

@interface BLEScanner : BLETransfer <CBCentralManagerDelegate, CBPeripheralDelegate>

@property (nonatomic, weak) NSObject<BLEScannerDelegate> *delegate;

+ (instancetype)scanData:(void (^)(NSString *bleSessionID,NSData *advertisData))callback;

@end
