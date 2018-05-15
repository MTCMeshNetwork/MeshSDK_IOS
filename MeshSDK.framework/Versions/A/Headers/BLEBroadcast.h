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

/**
 delegate for BLEBroadcast state or advertising data state
 */
@protocol BLEBroadcastDelegate <NSObject>

@optional

/**
 *  @method broadcast:didHopPayload:withError:
 *
 *  @param bleCast  BLEBroadcast.
 *  @param payload  data to be advertised.
 *  @param error    error.
 *
 *  @discussion Whether or not the BLEBroadcast is currently advertising data.
 *
 */
- (void)broadcast: (BLEBroadcast*)bleCast didHopPayload:(NSArray *)payload withError:(NSError *)error;

@end


/**
 use BLEBroadcast class to Broadcast mesh wake up or transfer mesh data.
 */
@interface BLEBroadcast : BLETransfer <CBPeripheralManagerDelegate>


/*!
 *  @property broadcasting
 *
 *  @discussion Whether or not the BLEBroadcast is currently advertising data.
 *
 */
@property (nonatomic, readonly) BOOL broadcasting;


/**
 delegate for BLEBroadcast state or advertising data state
 */
@property (nonatomic, weak) NSObject<BLEBroadcastDelegate> *delegate;

/*!
 *  @method setMeshCast:data:
 *
 *  @param uuid    An CBUUID data to be advertised. limit to 2 bytes.
 *  @param data    An optional data to be advertised.
 *
 *  @discussion                 Set advertising data. Supported advertising data types are <code>CBUUIDsKey</code>.
 *                              When in the foreground, an application can utilize up to 16 bytes data per time,
 *                              While an application is in the background, applications that have specified the "bluetooth-peripheral" background mode will only advertise uuid while in the background.
 */
- (BOOL)setMeshCast:(CBUUID *)uuid data:(NSData *)data;

/**
 * @method removeMeshCast:
 *
 * @param uuid remove uuid
 *
 */
- (void)removeMeshCast:(CBUUID *)uuid;

/**
 * @method meshWakeUp:
 *
 * @param region a wakeup region
 *
 *  Discussion:
 *    Invoked another ios device when there's a WakeUpManager scan for the region.
 *    Such a region can be defined by proximityUUID, major and minor values.
 */
- (void)setMeshWakeUp:(CLBeaconRegion *)region;

/**
 * @method stopMeshWakeUp:
 *
 * @param region a wakeup region
 *
 *  Discussion:
 *    Remove advertising the region.
 */
- (void)removeMeshWakeUp:(CLBeaconRegion *)region;

/**
 start broadCast
 */
- (BOOL) start;

/**
 stop broadCast
 */
- (void) stop;

@end
