//
//  BLEPacket.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/11.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BLEPacket : NSObject

@property (nonatomic,copy)   NSString       *identifier;
@property (nonatomic,copy)   NSData         *payload;
@property (nonatomic,assign) CBUUID         *type;
@property (nonatomic,assign) NSInteger      index;

//for ios
+ (instancetype)dataWithUUIDs:(NSArray *)uuids;

//for android
+ (instancetype)dataWithUUID:(CBUUID *)uuid mData:(NSData *)mdata iData:(NSData *)idata;

//init
- (instancetype)initWithUUID:(CBUUID *)uuid data:(NSData *)data index:(NSInteger)index;


@end
