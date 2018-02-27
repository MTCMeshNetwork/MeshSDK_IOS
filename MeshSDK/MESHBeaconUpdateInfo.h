//
//  MESHBeaconUpdateInfo.h
//  MeshSDK
//
//  Version : 1.0.0
//  Created by MTC on 22/02/18.
//  Copyright (c) 2018 MTC Network. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MESHBeaconUpdateInfo : NSObject

@property (nonatomic, strong) NSString* currentFirmwareVersion;
@property (nonatomic, strong) NSArray*  supportedHardware;

@end
