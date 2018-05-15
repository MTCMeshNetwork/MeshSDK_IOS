//
//  MeshSDK.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/11.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <MeshSDK/BLEManager.h>
#import <MeshSDK/BLEBroadcast.h>


//! Project version number for mesh.
FOUNDATION_EXPORT double meshVersionNumber;

//! Project version string for mesh.
FOUNDATION_EXPORT const unsigned char meshVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <mesh/PublicHeader.h>

@interface MeshSDK : NSObject

@end
