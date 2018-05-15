//
//  RegionHander.m
//  Demo
//
//  Created by thomasho on 18/3/6.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import "RegionHandler.h"

#define IOS8 ([[UIDevice currentDevice].systemVersion doubleValue] >= 8.0 && [[UIDevice currentDevice].systemVersion doubleValue] < 9.0)
#define IOS8_10 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0 && [[UIDevice currentDevice].systemVersion doubleValue] < 10.0)
#define IOS10 ([[[UIDevice currentDevice] systemVersion] floatValue] >= 10.0)

@implementation RegionHandler

- (void)registerLocalNotification:(UIApplication *)application {
    if (IOS10) {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = self;
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert) completionHandler:^(BOOL granted, NSError * _Nullable error) {
            if (!error) {
                NSLog(@"succeeded!");
            }
        }];
    } else if (IOS8_10){//iOS8-iOS10
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeBadge | UIUserNotificationTypeAlert | UIUserNotificationTypeSound) categories:nil];
        [application registerUserNotificationSettings:settings];
        [application registerForRemoteNotifications];
    } else {//iOS8以下
        [application registerForRemoteNotificationTypes: UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound];
    }
}

//如需测试完全关闭app：可以通过XCode->Windows->Devices->选中调试的iPhone查看NSLog信息
//也可以先获取本地通知权限，直接发本地通知
-(void)wakeUpManager:(CLLocationManager *)manager didEnterRegion:(CLBeaconRegion *)region {
    [self sendLocalNotification:region.major.intValue];
}
-(void)wakeUpManager:(CLLocationManager *)manager didExitRegion:(CLBeaconRegion *)region {
    [self sendLocalNotification:region.major.intValue];
}

-(void)wakeUpManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLBeaconRegion *)region {
    NSLog(@"锁屏点亮、检测区域状态：%@->%ld",region,(long)state);
    [self sendLocalNotification:0];
}
- (void)wakeUpManager:(WakeUpManager *)manager monitoringDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error {
    NSLog(@"区域监听失败：%@  error:%@",region,error);
}

- (void)sendLocalNotification:(NSInteger)major
{
    NSString *title = @"收到通知";
    NSString *subtitle = @"打开应用查看";
    if (major != 0) {
        title = @"打开应用查看详情";
        subtitle = @"检测到您进入Mesh区域";
    }
    if (IOS10) {
        [self addlocalNotificationForNewVersion:title sub:subtitle type:major];
    }else{
        [self addLocalNotificationForOldVersion:title sub:subtitle type:major];
    }
}

/**
 iOS 10以前版本添加本地通知
 */
- (void)addLocalNotificationForOldVersion:(NSString *)msg sub:(NSString *)subtitle type:(NSInteger) type {
    
    //定义本地通知对象
    UILocalNotification *notification = [[UILocalNotification alloc] init];
    //设置调用时间
    notification.timeZone = [NSTimeZone localTimeZone];
    notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:1.0];//通知触发的时间，1s以后
    notification.repeatInterval = 1;//通知重复次数
    notification.repeatCalendar=[NSCalendar currentCalendar];//当前日历，使用前最好设置时区等信息以便能够自动同步时间
    
    //设置通知属性
    notification.alertBody = msg;//[NSString stringWithFormat:@"Agent-%d",arc4random()%100]; //通知主体
    notification.applicationIconBadgeNumber += 1;//应用程序图标右上角显示的消息数
    notification.alertAction = subtitle; //待机界面的滑动动作提示
    notification.alertLaunchImage = @"Default";//通过点击通知打开应用时的启动图片,这里使用程序启动图片
    notification.soundName = UILocalNotificationDefaultSoundName;//收到通知时播放的声音，默认消息声音
    //    notification.soundName=@"msg.caf";//通知声音（需要真机才能听到声音）
    
    //设置用户信息
    notification.userInfo = @{@"type": @(type)};//绑定到通知上的其他附加信息
    
    //调用通知
    [[UIApplication sharedApplication] scheduleLocalNotification:notification];
}

/**
 iOS 10以后的本地通知
 */
- (void)addlocalNotificationForNewVersion:(NSString *)msg sub:(NSString *)subtitle type:(NSInteger)type {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [NSString localizedUserNotificationStringForKey:msg arguments:nil];
    content.body = [NSString localizedUserNotificationStringForKey:subtitle arguments:nil];
    content.sound = [UNNotificationSound defaultSound];
    content.userInfo = @{@"type": @(type)};
    
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1.0 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"OXNotification" content:content trigger:trigger];
    
    [center addNotificationRequest:request withCompletionHandler:^(NSError *_Nullable error) {
        NSLog(@"成功添加推送");
    }];
}

#pragma mark - UNUserNotificationCenterDelegate
// iOS 10收到前台通知
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    
    NSDictionary * userInfo = notification.request.content.userInfo;
    UNNotificationRequest *request = notification.request; // 收到推送的请求
    UNNotificationContent *content = request.content; // 收到推送的消息内容
    NSNumber *badge = content.badge;  // 推送消息的角标
    NSString *body = content.body;    // 推送消息体
    UNNotificationSound *sound = content.sound;  // 推送消息的声音
    NSString *subtitle = content.subtitle;  // 推送消息的副标题
    NSString *title = content.title;  // 推送消息的标题
    
    if([notification.request.trigger isKindOfClass:[UNPushNotificationTrigger class]]) {
        NSLog(@"iOS10 前台收到远程通知:%@", body);
    } else {
        // 判断为本地通知
        NSLog(@"iOS10 前台收到本地通知:{\\\\nbody:%@，\\\\ntitle:%@,\\\\nsubtitle:%@,\\\\nbadge：%@，\\\\nsound：%@，\\\\nuserInfo：%@\\\\n}",body,title,subtitle,badge,sound,userInfo);
    }
    completionHandler(UNNotificationPresentationOptionBadge|UNNotificationPresentationOptionSound|UNNotificationPresentationOptionAlert); // 需要执行这个方法，选择是否提醒用户，有Badge、Sound、Alert三种类型可以设置
}
// iOS 10收到后台通知
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    [[UIApplication sharedApplication].delegate application:nil didReceiveLocalNotification:response.notification];
    completionHandler();
}
@end
