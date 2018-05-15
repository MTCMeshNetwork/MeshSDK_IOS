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

/**
 delegate for BLEScanner state or discover data back
 */
@protocol BLEScannerDelegate <NSObject>

@optional

/**
 *  @method supportMeshServiceUUIDs
 *
 *  Discussion:
 *      A list of <code>CBUUID</code> objects representing the service(s) to scan for.
 */
- (NSArray <CBUUID *>*)supportMeshServiceUUIDs;

/**
 *  @method bleScanner:didFailScanWithError:
 *
 *  @param scanner  BLEScanner.
 *  @param error    An error data.
 *
 *  Discussion:
 *      Failed scanning for peripherals
 */
- (void)bleScanner: (BLEScanner*)scanner didFailScanWithError:(NSError *)error;

/**
 * @method bleScanner:didDiscoverUUID:advertisementData:RSSI:
 *
 * @param scanner BLEScanner.
 * @param uuid the service to scan.
 * @param advertisementData scan response data.
 * @param RSSI The current RSSI in dBm. A value of <code>-127</code> is reserved and indicates the RSSI was not available.
 *
 *  Discussion:
 *    Starts scanning for peripherals that are advertising any of the services listed insupportMeshServiceUUIDs. Although strongly discouraged,
 *                      if supportMeshServiceUUIDs is nil all discovered peripherals will be returned. If the central is already scanning with different
 *                      serviceUUIDs, the provided parameters will replace them.
 *                      Applications that have specified the bluetooth-central background mode are allowed to scan while backgrounded, but must specify one or more service types in serviceUUIDs
 *
 */
- (void)bleScanner:(BLEScanner*)scanner  didDiscoverUUID:(CBUUID *)uuid advertisementData:(NSData *)advertisementData RSSI:(NSNumber *)RSSI;

@end

/**
 use BLEScanner class to scan mesh data.
 */
@interface BLEScanner : BLETransfer

/**
 delegate for BLEScanner state or discover data back
 */
@property (nonatomic, weak) NSObject<BLEScannerDelegate> *delegate;

/**
 start scan
 */
- (BOOL) start;

/**
 stop scan
 */
- (void) stop;

@end
