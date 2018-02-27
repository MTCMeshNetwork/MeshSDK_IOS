//
//  MESHBeaconSDK.m
//  MeshSDK
//
//  Created by arron on 18-2-19.
//  Copyright (c) 2018年 arron. All rights reserved.
//

#import <UIKit/UIDevice.h>
#import <UIKit/UIKit.h>
#import "MESHBeaconSDK.h"
#import "MESHIDFA.h"

@interface records : NSObject

@property (nonatomic,copy) NSString *macAddr;
@property (nonatomic,assign) NSInteger startTime;
@property (nonatomic,assign) NSInteger endTime;
@property (nonatomic,assign) NSInteger useTime;
@property (nonatomic,copy) NSString *distances;
@property (nonatomic,strong) NSString *lat;
@property (nonatomic,strong) NSString *lng;
@property (nonatomic,strong) NSString *addr;

@property (nonatomic,copy) NSNumber *temperature;
@property (nonatomic,copy) NSNumber *electricity;

@end

@implementation records

-(void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:self.macAddr forKey:@"macAddr"];
    [aCoder encodeObject:[NSNumber numberWithInteger:self.startTime] forKey:@"startTime"];
    [aCoder encodeObject:[NSNumber numberWithInteger:self.endTime] forKey:@"endTime"];
    [aCoder encodeObject:[NSNumber numberWithInteger:self.useTime] forKey:@"useTime"];
    [aCoder encodeObject:self.temperature forKey:@"temperature"];
    [aCoder encodeObject:self.electricity forKey:@"electricity"];
    [aCoder encodeObject:self.distances forKey:@"distances"];
    [aCoder encodeObject:self.lat forKey:@"lat"];
    [aCoder encodeObject:self.lng forKey:@"lng"];
    [aCoder encodeObject:self.addr forKey:@"addr"];
}

-(id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    if(self) {
        self.macAddr = [aDecoder decodeObjectForKey:@"macAddr"];
        self.startTime = [[aDecoder decodeObjectForKey:@"startTime"] integerValue];
        self.endTime = [[aDecoder decodeObjectForKey:@"endTime"] integerValue];
        self.useTime = [[aDecoder decodeObjectForKey:@"useTime"] integerValue];
        self.temperature = [aDecoder decodeObjectForKey:@"temperature"];
        self.electricity = [aDecoder decodeObjectForKey:@"electricity"];
        self.distances = [aDecoder decodeObjectForKey:@"distances"];
        self.lat = [aDecoder decodeObjectForKey:@"lat"];
        self.lng = [aDecoder decodeObjectForKey:@"lng"];
        self.addr = [aDecoder decodeObjectForKey:@"addr"];
        if (!self.lat) {
            self.lat = @"";
        }
        if (!self.lng) {
            self.lng = @"";
        }
        if (!self.addr) {
            self.addr = @"";
        }
        if (!self.temperature) {
            self.temperature = @-1;
        }
        if (!self.electricity) {
            self.electricity = @-1;
        }
    }
    return self;
}
@end

@interface MESHBeaconSDK ()<MESHBeaconManagerDelegate>{
    BOOL isupdating,isposting;
    NSTimeInterval lastTimeAllKey;
}

@property (nonatomic,strong) MESHBeaconManager *beaconManager;
@property (nonatomic,strong) NSMutableSet<MESHBeacon *> *meshBeacons;
@property (nonatomic,strong) NSArray *rangingRegions;
@property (nonatomic,assign) NSTimeInterval invalidTime;
@property (nonatomic,assign) NSTimeInterval scanResponseTime;
@property (nonatomic,strong) id<MESHBeaconRegionDelegate> handler;
@property (nonatomic,strong) NSArray<CBUUID *> *bleServices;

@property (nonatomic, copy) ScanBlesCompletionBlock scanMeshBeaconsCompletionBlock;
@property (nonatomic, copy) RangingiBeaconsCompletionBlock rangingiBeaconsCompletionBlock;
@property (nonatomic, copy) MESHCompletionBlock registAppCompletionBlock;
@end

@implementation MESHBeaconSDK

static MESHBeaconSDK *_meshsdkinstance=nil;
static dispatch_once_t _meshonce;
+ (MESHBeaconSDK*) Share
{
    dispatch_once(&_meshonce, ^ {
        _meshsdkinstance = [[MESHBeaconSDK alloc] init];
        _meshsdkinstance.beaconManager = [[MESHBeaconManager alloc] init];
        _meshsdkinstance.beaconManager.delegate = _meshsdkinstance;
        _meshsdkinstance.beaconManager.regionDelegate = (id)[UIApplication sharedApplication].delegate;
        _meshsdkinstance.meshBeacons = [NSMutableSet set];
    });
    return _meshsdkinstance;
}

+ (NSSet<MESHBeacon *> *)meshBeacons {
    return [[MESHBeaconSDK Share].meshBeacons copy];
}

- (NSTimeInterval)invalidTime {
    return _invalidTime?:3;
}

- (NSTimeInterval)scanResponseTime {
    return _scanResponseTime?:1;
}

+ (void)setInvalidTime:(NSTimeInterval)invalidTime {
    [[self Share] setInvalidTime:invalidTime];
}
+ (void)setScanResponseTime:(NSTimeInterval)scanResponseTime {
    [[self Share] setScanResponseTime:scanResponseTime];
}
+ (void)regionHander:(id)handler
{
    if ([CLLocationManager authorizationStatus]>=3) {
        //如果从未获取GPS权限，避免提示需要GPS权限。在调用启动扫描时候再提示。
        [[MESHBeaconSDK MESHBeaconManager] locManager];
    }
    _meshsdkinstance.beaconManager.regionDelegate = handler;
}

+ (MESHBeaconManager*) MESHBeaconManager
{
    return [[MESHBeaconSDK Share] beaconManager];
}

+ (void)registerApp:(NSString *)appKey onCompletion:(MESHCompletionBlock)completion
{
    if(!appKey.length) appKey = DEFAULT_KEY;
    [[NSUserDefaults standardUserDefaults] setValue:appKey forKey:@"MESHSDK_APPKEY"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    completion?completion(YES,nil):nil;
}

//仅蓝牙扫描
+ (void) scanBleServices:(NSArray<CBUUID *> *)services onCompletion:(ScanBlesCompletionBlock)completion NS_AVAILABLE_IOS(6_0)
{
    [[MESHBeaconSDK Share] setBleServices:services];
    if(completion)[[MESHBeaconSDK Share] setScanMeshBeaconsCompletionBlock:completion];
    [[[MESHBeaconSDK Share] beaconManager] scanBleServices:services];
    
    [NSObject cancelPreviousPerformRequestsWithTarget:[MESHBeaconSDK Share] selector:@selector(scanMeshBeaconsCompletionBlockTimmer) object:nil];
    [[MESHBeaconSDK Share] performSelector:@selector(scanMeshBeaconsCompletionBlockTimmer) withObject:nil afterDelay:[MESHBeaconSDK Share].scanResponseTime];
}

//不启用蓝牙扫描
+ (void) startRangingBeaconsInRegions:(NSArray*)regions onCompletion:(RangingiBeaconsCompletionBlock)completion
{
    BOOL isIOS7 =([[[UIDevice currentDevice] systemVersion] intValue]>=7);
    if (isIOS7) {
        //停止之前扫描
        [[[MESHBeaconSDK Share] rangingRegions] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([obj isKindOfClass:[CLBeaconRegion class]]) {
                [[[MESHBeaconSDK Share] beaconManager] stopRangingBeaconsInRegion:obj];
            }else{
                MESHBeaconRegion *region = [[MESHBeaconRegion alloc] initWithProximityUUID:obj identifier:((NSUUID*)obj).UUIDString];
                [[[MESHBeaconSDK Share] beaconManager] stopRangingBeaconsInRegion:region];
            }
        }];
        //regions容错
        if (!regions.count) {
            [[MESHBeaconSDK Share] setRangingRegions: @[[[MESHBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:DEFAULT_UUID] identifier:DEFAULT_UUID]]];
        }else{
            NSMutableArray *marray = [NSMutableArray array];
            for (id obj in regions) {
                if ([obj isKindOfClass:[CLBeaconRegion class]]) {
                    [marray addObject:obj];
                }else if([obj isKindOfClass:[NSUUID class]]){
                    MESHBeaconRegion *region = [[MESHBeaconRegion alloc] initWithProximityUUID:obj identifier:((NSUUID*)obj).UUIDString];
                    [marray addObject:region];
                }else if([obj isKindOfClass:[NSString class]]){
                    MESHBeaconRegion *region = [[MESHBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:obj] identifier:obj];
                    [marray addObject:region];
                }
            }
            [[MESHBeaconSDK Share] setRangingRegions:marray];
        }
        //启动当前监听
        [[MESHBeaconSDK Share].rangingRegions enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [[[MESHBeaconSDK Share] beaconManager] startRangingBeaconsInRegion:obj];
        }];
    }else{
        if(completion)completion(nil,nil,[NSError errorWithDomain:@"no support <ios7" code:CBErrorCode5 userInfo:nil]);
    }
    if(completion)[[MESHBeaconSDK Share] setRangingiBeaconsCompletionBlock:completion];
}

+ (void) startMonitoringForRegions:(NSArray *)regions
{
    for (MESHBeaconRegion *obj in regions) {
        for (MESHBeaconRegion *region in [[[MESHBeaconSDK Share] beaconManager] monitoredRegions]) {
            if (obj.major == region.major &&obj.minor == region.minor&&[obj.proximityUUID.UUIDString isEqualToString:region.proximityUUID.UUIDString]) {
                //移除已有相同监听
                [[[MESHBeaconSDK Share] beaconManager] stopMonitoringForRegion:region];
            }
        }
        //添加新的监听
        [[[MESHBeaconSDK Share] beaconManager] requestAlwaysAuthorization];
        [[[MESHBeaconSDK Share] beaconManager] startMonitoringForRegion:obj];
    }
}
+ (NSDictionary*)isMonitoring:(NSDictionary*)dict
{
    BOOL isIOS7 =([[[UIDevice currentDevice] systemVersion] intValue]>=7);
    if (!isIOS7) {
        return nil;
    }
    NSString *identifier = [dict valueForKey:@"identifier"];
    if (identifier.length == 0) {
        NSString *uuid = [dict valueForKey:@"uuid"];
        NSString *major = [dict valueForKey:@"major"];
        NSString *minor = [dict valueForKey:@"minor"];
        if (minor) {
            identifier = [NSString stringWithFormat:@"%@_%@_%@",uuid,major,minor];
        }else if(major) {
            identifier = [NSString stringWithFormat:@"%@_%@",uuid,major];
        }else {
            identifier = uuid;
        }
    }
    for (MESHBeaconRegion *region in [[[MESHBeaconSDK Share] beaconManager] monitoredRegions] ) {
        if ([identifier isEqual:region.identifier]) {
            return @{@"in":(region.notifyOnEntry?@YES:@NO),@"out":(region.notifyOnExit?@YES:@NO),@"display":(region.notifyEntryStateOnDisplay?@YES:@NO)};
        }
    }
    return nil;
}

+ (void) requestStateForRegions:(NSArray *)regions
{
    BOOL isIOS7 =([[[UIDevice currentDevice] systemVersion] intValue]>=7);
    if (isIOS7) {
        [regions enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [[[MESHBeaconSDK Share] beaconManager] requestStateForRegion:obj];
        }];
    }
}

+ (void) stopScan {
    [[MESHBeaconSDK Share] setScanMeshBeaconsCompletionBlock:nil];
    [[[MESHBeaconSDK Share] beaconManager] stopScan];
}

+ (void) stopRangingBeacons
{
    BOOL isIOS7 =([[[UIDevice currentDevice] systemVersion] intValue]>=7);
    if (isIOS7) {
        [[[MESHBeaconSDK Share] rangingRegions] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([obj isKindOfClass:[CLBeaconRegion class]]) {
                [[[MESHBeaconSDK Share] beaconManager] stopRangingBeaconsInRegion:obj];
            }else{
                MESHBeaconRegion *region = [[MESHBeaconRegion alloc] initWithProximityUUID:obj identifier:((NSUUID*)obj).UUIDString];
                [[[MESHBeaconSDK Share] beaconManager] stopRangingBeaconsInRegion:region];
            }
        }];
    }
    [[MESHBeaconSDK Share] setRangingiBeaconsCompletionBlock:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:[self Share] selector:@selector(scanMeshBeaconsCompletionBlockTimmer) object:nil];
}

+ (void) stopMonitoringForRegions:(NSArray *)regions
{
    if (regions.count) {
        [regions enumerateObjectsUsingBlock:^(MESHBeaconRegion *obj, NSUInteger idx, BOOL *stop) {
            if (obj.identifier.length) {
                [[[MESHBeaconSDK Share] beaconManager] stopMonitoringForRegion:obj];
            }else{
                [[[[MESHBeaconSDK Share] beaconManager] monitoredRegions] enumerateObjectsUsingBlock:^(MESHBeaconRegion *region, BOOL *stop) {
                    if (obj.major == region.major &&obj.minor == region.minor&&[obj.proximityUUID.UUIDString isEqualToString:region.proximityUUID.UUIDString]) {
                        [[[MESHBeaconSDK Share] beaconManager] stopMonitoringForRegion:region];
                    }
                }];
            }
        }];
    }else{
        [[[[MESHBeaconSDK Share] beaconManager] monitoredRegions] enumerateObjectsUsingBlock:^(MESHBeaconRegion *region, BOOL *stop) {
            [[[MESHBeaconSDK Share] beaconManager] stopMonitoringForRegion:region];
        }];
    }
}


//检查并移除超时的Beacon
- (BOOL)checkAndRemoveTimeoutBeacon{
    BOOL flag = NO;
    NSArray *tmpArr = [NSArray arrayWithArray:self.meshBeacons.allObjects];
    //到一定时间后 移除
    NSTimeInterval time = [[NSDate date] timeIntervalSince1970];
    for (MESHBeacon *b in tmpArr) {
        //对于已存储的beacon超过InvalidTime没收到数据，做移除
        if(b&&(time-b.invalidTime>=self.invalidTime)){
            [self.meshBeacons removeObject:b];
        }
    }
    return flag;
}

//每一秒钟通知回调-
- (void)scanMeshBeaconsCompletionBlockTimmer{
//    [MESHBeaconSDK stopScan];会删掉回调
    [[[MESHBeaconSDK Share] beaconManager] stopScan];
    [self checkAndRemoveTimeoutBeacon];
    if(self.scanMeshBeaconsCompletionBlock){
        NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"rssi" ascending:YES];
        self.scanMeshBeaconsCompletionBlock([[self.meshBeacons.allObjects sortedArrayUsingDescriptors:@[sort]] copy],nil);
    }
    [MESHBeaconSDK scanBleServices:self.bleServices onCompletion:nil];
}
#pragma
#pragma discover
- (void)beaconManager:(MESHBeaconManager *)manager
    didDiscoverBeacon:(MESHBeacon *)beacon
{
    [self.meshBeacons addObject:beacon];
}
#pragma ranging
#pragma mark - MESHBeaconManager delegate

- (void)beaconManagerDidUpdateState:(CBManagerState)state {
//    IOS10:CBManagerStatePoweredOn;
//    CBCentralManagerStatePoweredOn
    if(state == 5)[MESHBeaconSDK scanBleServices:self.bleServices onCompletion:nil];
}

- (void)beaconManager:(MESHBeaconManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(MESHBeaconRegion *)region
{
    NSTimeInterval time = [[NSDate date] timeIntervalSince1970];
    if (self.rangingRegions.count) {
        if (![self.rangingRegions containsObject:region.proximityUUID]) {
            CLBeaconRegion *findregion  = nil;
            for (CLBeaconRegion *obj in self.rangingRegions) {
                if([obj isKindOfClass:[NSUUID class]]){
                    break;
                }
                if ([obj.identifier isEqualToString:region.identifier]&&obj.major==region.major&&obj.minor == region.minor) {
                    findregion = obj;
                    break;
                }
            }
            if (!findregion) {
                [manager stopRangingBeaconsInRegion:region];
                return;
            }
        }
    }
    if(self.rangingiBeaconsCompletionBlock==nil){
        [manager stopRangingBeaconsInRegion:region];
        return;
    }
    if (self.rangingiBeaconsCompletionBlock) {
        NSMutableArray *marray = [NSMutableArray arrayWithCapacity:beacons.count];
        for (CLBeacon *b in beacons) {
            MESHBeacon *beacon = [MESHBeacon new];
            beacon.proximityUUID = b.proximityUUID;
            beacon.major = b.major;
            beacon.minor = b.minor;
            beacon.proximity = b.proximity;
            beacon.accuracy = b.accuracy;
            beacon.rssi = b.rssi?:-127;
            beacon.invalidTime = time;
            [marray addObject:beacon];
        }
        self.rangingiBeaconsCompletionBlock(marray,region,nil);
    }
}
- (void)beaconManager:(CLLocationManager *)manager rangingBeaconsDidFailForRegion:(MESHBeaconRegion *)region withError:(NSError *)error
{
    if(self.rangingiBeaconsCompletionBlock)self.rangingiBeaconsCompletionBlock(nil,region,error);
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end
