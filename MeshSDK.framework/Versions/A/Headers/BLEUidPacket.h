//
//  BLEUidPacket.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/11.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import "BLEPacket.h"
#import "BLECrypto.h"

// payload_data: [display_name=35]
// full: [[version=1][timestamp=8][sender_public_key=32][display_name=35]][signature=64]
@interface BLEUidPacket : BLEPacket

// Static Properties
@property (nonatomic, strong, readonly) NSData *displayNameData;

// Dynamic Properties
@property (nonatomic, strong, readonly) NSString *displayName;

// Outgoing
- (instancetype) initWithDisplayName:(NSString*)displayName;

@end
