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

- (void)wakeUpManager:(WakeUpManager *)manager monitoringDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error;
- (void)wakeUpManager:(WakeUpManager *)manager didEnterRegion:(CLBeaconRegion *)region;
- (void)wakeUpManager:(WakeUpManager *)manager didExitRegion:(CLBeaconRegion *)region;
- (void)wakeUpManager:(WakeUpManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLBeaconRegion *)region;
@end

@interface WakeUpManager : NSObject

@property (nonatomic,weak) id<WakeUpManagerDelegate> delegate;

- (void)monitorMeshWakeUp:(CLBeaconRegion *)region;
- (void)stopMonitor:(CLBeaconRegion *)region;

@end
