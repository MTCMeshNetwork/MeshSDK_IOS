//
//  MESHTools.h
//  MeshSDK
//
//  Created by arron on 18/2/18.
//  Copyright © 2018年 arron. All rights reserved.
//

#import <Foundation/Foundation.h>

#define subString(str,loc,len) [str substringWithRange:NSMakeRange(loc, len)]

@interface MESHTools : NSObject

+ (NSData *)hex2data:(NSString *)hex;
+ (NSString *)data2hex:(NSData *)data;
+ (NSString *)data2UTF8:(NSData *)data;

//小端模式(little-endian)
+ (int32_t)data2Integer:(NSData *)data;
+ (NSData *)integer2data:(int32_t )value;
+ (NSData *)uinteger2data:(uint32_t )value;

@end
