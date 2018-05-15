//
//  BeaconManager.h
//  mtc
//
//  Created by thomasho on 2018/5/2.
//  Copyright © 2017年 mtc.io. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@class WakeUpManager;
@protocol WakeUpManagerDelegate<NSObject>

@optional

/**
 *  @method wakeUpManager:monitoringDidFailForRegion:withError:
 *
 * @param manager WakeUpManager.
 * @param region a monitored region
 * @param error error.
 *
 *  Discussion:
 *    Invoked when a region monitoring error has occurred.
 */
- (void)wakeUpManager:(WakeUpManager *)manager monitoringDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error;

/**
 *  @method wakeUpManager:didEnterRegion:
 *
 * @param manager WakeUpManager.
 * @param region a monitored region
 *
 *  Discussion:
 *    Invoked when the user enters a monitored region.  This callback will be invoked for every allocated
 *    WakeUpManager instance with a non-nil delegate that implements this method.
 */
- (void)wakeUpManager:(WakeUpManager *)manager didEnterRegion:(CLBeaconRegion *)region;

/**
 *  @method wakeUpManager:didExitRegion:
 *
 * @param manager WakeUpManager.
 * @param region a monitored region
 *
 *  Discussion:
 *    Invoked when the user exits a monitored region.  This callback will be invoked for every allocated
 *    wakeUpManager instance with a non-nil delegate that implements this method.
 */
- (void)wakeUpManager:(WakeUpManager *)manager didExitRegion:(CLBeaconRegion *)region;

/**
 *  @method wakeUpManager:didDetermineState:forRegion:
 *
 * @param manager WakeUpManager.
 * @param state  region state
 * @param region a monitored region
 *
 *  Discussion:
 *    Invoked when there's a state transition for a monitored region or in response to a request for state via a
 *    a call to requestStateForRegion:.
 */
- (void)wakeUpManager:(WakeUpManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLBeaconRegion *)region;
@end

/**
 use WakeUpManager class to monitor mesh region.
 */
@interface WakeUpManager : NSObject


/**
    delegate for region state
 */
@property (nonatomic, assign) id<WakeUpManagerDelegate> delegate;

/**
 *  @method startMonitoringForRegion:
 *
 * @param region a monitored region
 *
 *  Discussion:
 *      Start monitoring the specified region.
 *
 *      If a region of the same type with the same identifier is already being monitored for this application,
 *      it will be removed from monitoring.
 *
 *      This is done asynchronously and may not be immediately reflected in monitoredRegions.
 */
- (void)monitorMeshWakeUp:(CLBeaconRegion *)region;

/**
 *  @method stopMonitoringForRegion:
 *
 * @param region a monitored region
 *
 *  Discussion:
 *      Stop monitoring the specified region.  It is valid to call stopMonitor: for a region that was registered
 *      for monitoring with a different WakeUpManager object, during this or previous launches of your application.
 *
 *      This is done asynchronously and may not be immediately reflected in monitoredRegions.
 */
- (void)stopMonitor:(CLBeaconRegion *)region;

/**
 *  @method monitoredRegions
 *
 *  Discussion:
 *       Retrieve a set of objects for the regions that are currently being monitored.  If any WakeUpManager manager
 *       has been instructed to monitor a region, during this or previous launches of your application, it will
 *       be present in this set.
 */
- (NSSet *)monitoredRegions;

/**
 *  @method requestStateForRegion:
 *
 * @param region a monitored region
 *
 *  Discussion:
 *      Asynchronously retrieve the cached state of the specified region. The state is returned to the delegate via
 *      wakeUpManager:didDetermineState:forRegion:.
 */
- (void)requestStateForRegion:(CLBeaconRegion *)region;

@end
