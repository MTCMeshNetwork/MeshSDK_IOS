//
//  BLEMsgPacket.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/11.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BLEMsgPacket : NSObject

@property (nonatomic,copy)   NSString       *identifier;
@property (nonatomic,copy)   NSData         *data;
@property (nonatomic,assign) CBUUID         *type;

- (instancetype)initWithIndentify:(NSString *)identifier type:(CBUUID *)type data:(NSData *)data;

@end
