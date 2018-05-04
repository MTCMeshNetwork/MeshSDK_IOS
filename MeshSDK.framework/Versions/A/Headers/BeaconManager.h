//
//  BeaconManager.h
//  mtc
//
//  Created by thomasho on 2018/5/2.
//  Copyright © 2017年 mtc.io. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface BeaconManager : NSObject

@property (nonatomic,strong) CLLocationManager *locManager;

+ (void)sendLocalNotificationTitle:(NSString *)title msg:(NSString *)msg;

- (void)startMonitor:(CLBeaconRegion *)region;

@end
