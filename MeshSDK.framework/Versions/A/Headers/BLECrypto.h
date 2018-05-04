//
//  BLECrypto.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/25.
//  Copyright © 2018年 m2c. All rights reserved.
//

#import <Foundation/Foundation.h>

extern const uint8_t Zeros[];

@interface BLECrypto : NSObject

+ (NSData*) signatureForData:(NSData*)data;
+ (BOOL) verifyData:(NSData*)data crc:(uint32_t)crc;

@end
