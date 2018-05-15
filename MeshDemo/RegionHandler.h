//
//  RegionHander.h
//  Demo
//
//  Created by thomasho on 18/3/6.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>
#import <MeshSDK/WakeUpManager.h>

@interface RegionHandler : NSObject <WakeUpManagerDelegate,CLLocationManagerDelegate,UNUserNotificationCenterDelegate>

/**
 注册本地消息推送

 @param application 应用
 */
- (void)registerLocalNotification:(UIApplication *)application;

@end
