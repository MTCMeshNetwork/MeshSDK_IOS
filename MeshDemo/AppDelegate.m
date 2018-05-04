//
//  AppDelegate.m
//  MeshDemo
//
//  Created by thomasho on 2018/5/2.
//  Copyright © 2018年 o2o. All rights reserved.
//

#import "AppDelegate.h"
#import "ViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[[ViewController alloc] initWithNibName:nil bundle:nil]];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
