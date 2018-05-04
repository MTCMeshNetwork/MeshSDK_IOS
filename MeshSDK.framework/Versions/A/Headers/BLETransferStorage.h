//
//  BLETransferStorage.h
//  MeshSDK
//
//  Created by thomasho on 2018/1/11.
//  Copyright © 2018年 mtc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BLEStorage.h"

@interface BLETransferStorage : NSObject <BLEStorage>

- (instancetype) initWithDataStorage:(id<BLEStorage>)dataStorage;

@end
