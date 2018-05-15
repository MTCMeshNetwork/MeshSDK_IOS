//
//  AppDelegate.m
//  MeshDemo
//
//  Created by thomasho on 2018/3/2.
//  Copyright © 2018年 o2o. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"
#import <MeshSDK/WakeUpManager.h>
#import "RegionHandler.h"

@interface AppDelegate ()

@property (nonatomic,strong) WakeUpManager *wakeUpManager;
@property (nonatomic,strong) RegionHandler *regionHandler;

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[[ViewController alloc] initWithNibName:nil bundle:nil]];
    [self.window makeKeyAndVisible];
    
    //处理后台唤醒类、申请发通知权限
    self.regionHandler = [[RegionHandler alloc] init];
    [self.regionHandler registerLocalNotification:application];
    
    //初始化后台唤醒Manager
    self.wakeUpManager = [[WakeUpManager alloc] init];
    self.wakeUpManager.delegate = self.regionHandler;
    
//    stop any you donnot want
//    for (CLBeaconRegion *region in [self.wakeUpManager monitoredRegions]) {
//        [self.wakeUpManager stopMonitor:region];
//    }
    if ([self.wakeUpManager monitoredRegions].count == 0) {
        CLBeaconRegion *regionMesh = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:@"FDA50693-A4E2-4FB1-AFCF-C6EB07647825"] major:1 identifier:@"mesh"];
        regionMesh.notifyOnEntry = YES;
        regionMesh.notifyOnExit = NO;
        regionMesh.notifyEntryStateOnDisplay = YES;
        [self.wakeUpManager monitorMeshWakeUp:regionMesh];
    }
    
    /* APP未启动，点击推送消息的情况下 iOS10遗弃UIApplicationLaunchOptionsLocalNotificationKey，
     使用代理UNUserNotificationCenterDelegate方法didReceiveNotificationResponse:withCompletionHandler:获取本地推送
     */
    UILocalNotification *notification = launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
    if (notification) {
        NSLog(@"localUserInfo:%@",notification);
        //APP未启动，点击推送消息
        [self application:application didReceiveLocalNotification:notification];
    }
    return YES;
}
#pragma mark - **************** local notification for IOS 7~10
-(void)application:(UIApplication *)application didReceiveLocalNotification:(id)notification {
    NSLog(@"用户打开通知：%@",notification);
//    if ([notification isKindOfClass:[UILocalNotification class]]) {
//        NSNumber *major = [((UILocalNotification*)notification).userInfo valueForKey:@"type"];
//    }else if([notification isKindOfClass:[UNNotification class]]) {
//        NSNumber *major = [((UNNotification*)notification).request.content.userInfo valueForKey:@"type"];
//    }
}

@end
