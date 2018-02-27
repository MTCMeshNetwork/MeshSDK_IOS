;//
//  MESHBeaconManager.h
//  MeshSDK
//
//  Version : 1.0.0
//  Created by MTC on 20/02/18.
//  Copyright (c) 2018 MTC Network. All rights reserved.
//

#import "MESHBeaconManager.h"
#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <MapKit/MapKit.h>
#import "MESHBeaconSDK.h"
#import "MESHBeaconRegion.h"
#import "MESHBeacon.h"

#define iszh [[NSLocale preferredLanguages][0] rangeOfString:@"zh"].location==0
#define LOC_TITLE iszh?@"需要定位":@"Location Need"
#define LOC_TIPS iszh?@"感知iBeacon设备，获取区域推送，需要定位权限“使用期间”或“始终”":@"In order to be notified about ibeacons near you, please open this app's settings and set location access to 'Always' Or 'WhenInUse'."

#define subHexStr2Long(str,loc,len) strtoul([[str substringWithRange:NSMakeRange(loc, len)] UTF8String],0,16)

@interface MESHBeaconManager ()<CLLocationManagerDelegate,CBPeripheralManagerDelegate,CBCentralManagerDelegate,CBPeripheralDelegate,UIAlertViewDelegate>{
    CGFloat iosversion;
    BOOL isLocation;
    
    BOOL isGeocoder;
}

@property (nonatomic,strong) locBlock locationBlock;

@property (nonatomic,strong) CLLocationManager *locManager;
@property (nonatomic,strong) CBCentralManager *centralManager;
@property (nonatomic,strong) CBPeripheralManager *peripheralManager;
@property (nonatomic,strong) NSMutableDictionary *blesDictionary;

@property (nonatomic,strong) NSDictionary *peripheralData;

@end

@implementation MESHBeaconManager

- (id)init
{
    self = [super init];
    if (self) {
        iosversion = [[[UIDevice currentDevice] systemVersion] floatValue];
        isLocation = ([CLLocationManager locationServicesEnabled] &&
                      [CLLocationManager authorizationStatus] >=3);
        self.centralManager  = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) options:@{CBCentralManagerOptionShowPowerAlertKey:@NO}];
        self.blesDictionary = [NSMutableDictionary dictionary];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectPeripheral:) name:kNotifyConnect object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(disconnectPeripheral:) name:kNotifyCancelConnect object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (CLLocationManager *)locManager {
    if (!_locManager) {
        _locManager = [[CLLocationManager alloc] init];
        _locManager.delegate = self;
        if (isLocation) {
            [self.locManager startUpdatingLocation];
        }
        if ([CLLocationManager authorizationStatus] <= kCLAuthorizationStatusDenied) {
            if([_locManager respondsToSelector:@selector(requestAlwaysAuthorization)])[self.locManager requestAlwaysAuthorization];
            if([_locManager respondsToSelector:@selector(requestWhenInUseAuthorization)])[self.locManager requestWhenInUseAuthorization];
        }else{
            //if([_locManager respondsToSelector:@selector(requestWhenInUseAuthorization)])[self.locManager performSelector:@selector(requestWhenInUseAuthorization)];
        }
    }
    return _locManager;
}
- (void)startUpdateLocations:(void(^)(CLLocation *location, CLPlacemark *placemark, NSError *error))block {
    if ([CLLocationManager authorizationStatus]>kCLAuthorizationStatusDenied) {
        if(block)self.locationBlock = block;
        [self.locManager startUpdatingLocation];
    }else{
        if(block)block(nil,nil,[NSError errorWithDomain:@"CLErrorAuthorizationStatus" code:[CLLocationManager authorizationStatus] userInfo:nil]);
    }
}
- (void)stopUpdatingLocation {
    [self.locManager stopUpdatingLocation];
    if(self.locationBlock)self.locationBlock = nil;
}
- (NSSet*)monitoredRegions
{
    return self.locManager.monitoredRegions;
}

- (NSSet*)rangedRegions
{
    return self.locManager.rangedRegions;
}
- (void)requestAlwaysAuthorization{
    if([self.locManager respondsToSelector:@selector(requestAlwaysAuthorization)])[self.locManager performSelector:@selector(requestAlwaysAuthorization)];
}
- (void)requestWhenInUseAuthorization{
    if([self.locManager respondsToSelector:@selector(requestWhenInUseAuthorization)])[self.locManager performSelector:@selector(requestWhenInUseAuthorization)];
}
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    if ([self.delegate respondsToSelector:@selector(locationManagerAuthorStatus:)]) {
        [self.delegate locationManagerAuthorStatus:status];
    }else if(status <= kCLAuthorizationStatusDenied){
        NSLog(@"Location Not Authorization");
    }
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (self.locationBlock) {
        self.locationBlock(nil,nil,error);
    }
}

- (void)startRangingBeaconsInRegion:(MESHBeaconRegion *)region
{
    [self.locManager startRangingBeaconsInRegion:region];
}
-(void)startMonitoringForRegion:(MESHBeaconRegion*)region{
    [self.locManager startMonitoringForRegion:region];
}

-(void)stopRangingBeaconsInRegion:(MESHBeaconRegion*)region{
    [self.locManager stopRangingBeaconsInRegion:region];
}

-(void)stopMonitoringForRegion:(MESHBeaconRegion *)region{
    [self.locManager stopMonitoringForRegion:region];
}
-(void)requestStateForRegion:(MESHBeaconRegion *)region
{
    [self.locManager requestStateForRegion:region];
}

#pragma mark - **************** advertising iBeacon

-(void)startAdvertisingWithProximityUUID:(NSUUID *)proximityUUID
                                   major:(CLBeaconMajorValue)major
                                   minor:(CLBeaconMinorValue)minor
                              identifier:(NSString*)identifier
                                   power:(NSNumber *)power
{
    CLBeaconRegion *region = [[CLBeaconRegion alloc] initWithProximityUUID:proximityUUID major:major minor:minor identifier:identifier];
    self.peripheralData = [region peripheralDataWithMeasuredPower:power];
//    [self.peripheralManager stopAdvertising];
    self.peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) options:@{CBPeripheralManagerOptionShowPowerAlertKey:@NO}];
}
-(BOOL)isAdvertising{
    return [_peripheralManager isAdvertising];
}
-(void)stopAdvertising{
    self.peripheralData = nil;
    [_peripheralManager stopAdvertising];
}

- (void)peripheralManagerDidUpdateState:(CBPeripheral *)peripheral{
    if (self.centralManager.state == CBManagerStatePoweredOn) {
        // The region's peripheral data contains the CoreBluetooth-specific data we need to advertise.
        if(self.peripheralData)
        {
            [_peripheralManager startAdvertising:_peripheralData];
        }else if ([self.regionDelegate respondsToSelector:@selector(beaconManagerDidStartAdvertising:error:)]) {
            [self.regionDelegate beaconManagerDidStartAdvertising:self error:[NSError errorWithDomain:NSLocalizedString(@"检查参数格式",nil) code:101 userInfo:nil]];
        }else {
            NSLog(@"参数格式有误");
        }
    }else {
        if ([self.regionDelegate respondsToSelector:@selector(beaconManagerDidStartAdvertising:error:)]) {
            [self.regionDelegate beaconManagerDidStartAdvertising:self error:[NSError errorWithDomain:NSLocalizedString(@"检查蓝牙状态",nil) code:100 userInfo:nil]];
        }else {
            NSLog(@"蓝牙未打开，无法广播");
        }
    }
}

- (void)peripheralManagerDidStartAdvertising:(CBPeripheralManager *)peripheral error:(NSError *)error
{
    if (error) {
        NSLog(@"ERROR：%@",error.description);
    }
    if ([self.regionDelegate respondsToSelector:@selector(beaconManagerDidStartAdvertising:error:)]) {
        [self.regionDelegate beaconManagerDidStartAdvertising:self error:error];
    }
}

#pragma mark - **************** ranging iBeacons

- (void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region
{
    //同一个UUID，每秒都来一次，而且每个UUID都会在1s来一次
    if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:didRangeBeacons:inRegion:)]) {
        [self.delegate beaconManager:self didRangeBeacons:beacons inRegion:(MESHBeaconRegion *)region];
    }
}

- (void)locationManager:(CLLocationManager *)manager rangingBeaconsDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error
{
    if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:rangingBeaconsDidFailForRegion:withError:)]) {
        [self.delegate beaconManager:self rangingBeaconsDidFailForRegion:(MESHBeaconRegion *)region withError:error];
    }
}

#pragma monitor
- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    // A user can transition in or out of a region while the application is not running.
    // When this happens CoreLocation will launch the application momentarily, call this delegate method
    // and we will let the user know via a local notification.
    
    if ([self.regionDelegate respondsToSelector:@selector(beaconManager:didDetermineState:forRegion:)]) {
        [self.regionDelegate beaconManager:self didDetermineState:state forRegion:(MESHBeaconRegion *)region];
    }
}

-(void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error{
    if ([self.regionDelegate respondsToSelector:@selector(beaconManager:monitoringDidFailForRegion:withError:)]) {
        [self.regionDelegate beaconManager:self monitoringDidFailForRegion:(MESHBeaconRegion *)region withError:error];
        
    }
}
-(void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region{
    if ([self.regionDelegate respondsToSelector:@selector(beaconManager:didEnterRegion:)]) {
        [self.regionDelegate beaconManager:self didEnterRegion:(MESHBeaconRegion *)region];
    }
}
-(void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region{
    if ([self.regionDelegate respondsToSelector:@selector(beaconManager:didExitRegion:)]) {
        [self.regionDelegate beaconManager:self
                             didExitRegion:(MESHBeaconRegion *)region];
    }
}

#pragma mark - **************** scanBle

-(void)scanBleServices:(NSArray<CBUUID *> *)services {
    
    isLocation = ([CLLocationManager locationServicesEnabled] &&
                  [CLLocationManager authorizationStatus] >=3);
    //	[self.centralManager  scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:@"180a"]] options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES}];
    [self.centralManager  scanForPeripheralsWithServices:services options:@{ CBCentralManagerScanOptionAllowDuplicatesKey : @YES}];
}

-(void)stopScan {
    [self.centralManager  stopScan];
}

#pragma mark -- CBCentralManagerDelegate
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManagerDidUpdateState:)]) {
        [self.delegate beaconManagerDidUpdateState:central.state];
    }
}

#pragma mark - **************** notifyConnect
- (void)connectPeripheral:(NSNotification *)notify {
    CBPeripheral *peripheral = notify.object;
    
    BOOL connect = (iosversion>=7)?(peripheral.state == CBPeripheralStateConnecting||peripheral.state == CBPeripheralStateConnected):(!![peripheral performSelector:@selector(isConnected)]);
    if (NO == connect) {
        [self.centralManager connectPeripheral:peripheral options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
    }
}
- (void)disconnectPeripheral:(NSNotification *)notify {
    CBPeripheral *peripheral = notify.object;
    [self.centralManager cancelPeripheralConnection:peripheral];
}

#pragma mark -- CBCentralManagerDelegate
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifyDisconnect object:peripheral userInfo:error?@{@"error": error}:nil];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotifyDisconnect object:peripheral userInfo:error?@{@"error": error}:nil];
}

-(NSString*)convertCBUUIDToString:(CBUUID*)uuid {
    NSData *data = uuid.data;
    NSUInteger bytesToConvert = [data length];
    const unsigned char *uuidBytes = [data bytes];
    NSMutableString *outputString = [NSMutableString stringWithCapacity:16];
    
    for (NSUInteger currentByteIndex = 0; currentByteIndex < bytesToConvert; currentByteIndex++)
    {
        switch (currentByteIndex)
        {
            case 3:
            case 5:
            case 7:
            case 9:[outputString appendFormat:@"%02x-", uuidBytes[currentByteIndex]]; break;
            default:[outputString appendFormat:@"%02x", uuidBytes[currentByteIndex]];
        }
        
    }
    
    NSString *result = [outputString uppercaseString];
    return result;
}

-(NSString*)getHexString:(NSData*)data {
    NSUInteger dataLength = [data length];
    NSMutableString *string = [NSMutableString stringWithCapacity:dataLength*2];
    const unsigned char *dataBytes = [data bytes];
    for (NSInteger idx = 0; idx < dataLength; ++idx) {
        [string appendFormat:@"%02x", dataBytes[idx]];
    }
    return string;
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    NSMutableDictionary *mdict = self.blesDictionary;
    BOOL isIOS7 =(iosversion>=7);
    NSString *pUUID = nil;
    if (isIOS7) {
        pUUID = peripheral.identifier.UUIDString;
    }else{
        id obj = [peripheral performSelector:@selector(UUID)];
        if (obj) {
            pUUID = (NSString*)CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault,(CFUUIDRef)obj));
        }else if (iosversion<=6.0){
            //兼容IOS6.0.x系列
            [central connectPeripheral:peripheral options:nil];
            [central performSelector:@selector(cancelPeripheralConnection:) withObject:peripheral afterDelay:.5];
            return;
        }
    }
    
    MESHBeacon *b = [mdict valueForKey:pUUID];
    NSString *name = [advertisementData valueForKey:@"kCBAdvDataLocalName"];
    if(name.length) b.name = name;
    if (!b) {
        b = [MESHBeacon new];
        [mdict setObject:b forKey:pUUID];
    }
    b.peripheral = peripheral;
    if(name.length)b.name = name;
    //上一次也是扫描来的rssi直接使用
    if([RSSI isEqualToNumber:@127]){
        b.rssi = b.rssi==0?-127:b.rssi;
    }else {
        b.rssi = RSSI.integerValue;
    }
    b.invalidTime = [[NSDate date] timeIntervalSince1970];
    
    BOOL disconnect = isIOS7?(peripheral.state == CBPeripheralStateDisconnected):(![peripheral performSelector:@selector(isConnected)]);
    NSDictionary *dict = [advertisementData valueForKey:@"kCBAdvDataServiceData"];
    if (disconnect&&dict.allValues.count) {
        NSString *key = [self getHexString:[(CBUUID*)dict.allKeys[0] data]];
        NSString *str = [self getHexString:dict.allValues[0]];
        
        NSString *str1 = str;
        BOOL isEddystone = [key isEqualToString:@"feaa"];
        if (isEddystone) {
            //尝试抛给原来解析
            key = [self getHexString:[(CBUUID*)dict.allKeys.lastObject data]];
            str = [self getHexString:dict.allValues.lastObject];
            if ([key isEqualToString:@"feaa"]) {
                //解析feaa
            }
        }
        if ([key isEqualToString:@"180a"]&&str.length>=54) {
            //设备解析18A0 = <817b2d16 4a54(mac)2711(major) 6b34(minor)bf(mpower)02(ver) 64(bat)13(temp)00ff(light) ffffffff ffffffff ffffff>
            //2.x老设备解析：8c632bfb4dce ce4d fb2b bf 05 64 12 00c8 ffffffffffffffffffffff
            NSString *mac = [NSString stringWithFormat:@"%@:%@:%@:%@:%@:%@",[str substringWithRange:NSMakeRange(10, 2)],[str substringWithRange:NSMakeRange(8, 2)],[str substringWithRange:NSMakeRange(6, 2)],[str substringWithRange:NSMakeRange(4, 2)],[str substringWithRange:NSMakeRange(2, 2)],[str substringWithRange:NSMakeRange(0, 2)]];
            
            NSString *smajor = [str substringWithRange:NSMakeRange(12, 4)];
            unsigned long imajor = strtoul([smajor UTF8String],0,16);
            
            
            NSString *sminor = [str substringWithRange:NSMakeRange(16, 4)];
            unsigned long iminor = strtoul([sminor UTF8String],0,16);
            
            NSString *smeasure = [str substringWithRange:NSMakeRange(20, 2)];
            long imeasure = strtol([smeasure UTF8String],0,16)-256;
            
            MESHBeacon *beacon = b;
            beacon.isMeshBeacon = YES;
            beacon.peripheral = peripheral;
            beacon.name = peripheral.name;
            beacon.macAddress = mac;
            beacon.major = [NSNumber numberWithUnsignedLong:imajor];
            beacon.minor = [NSNumber numberWithUnsignedLong:iminor];
            beacon.measuredPower =[NSNumber numberWithLong:imeasure];
            
            // "Device Information" = <8830525c 67de(mac)2711(major) 6bb5(minor)bf(mpower)b0 00(标识)0304(硬件)00 0a(软件)63(电量)16（温度）00 5d（光感）ffffffff （保留）0a（随机）bb(固定)>;
            if ([[str substringWithRange:NSMakeRange(str.length-4, 2)] isEqualToString:@"bb"]) {
                //0304-9以上等新固件。
                NSInteger flag = subHexStr2Long(str, 22, 4);
                beacon.flag = flag;
                
                beacon.mode = flag&0x1;
                
                beacon.hardwareVersion = [str substringWithRange:NSMakeRange(26, 4)];
                if ([beacon isSupport:BleSupportsExtension]) {
                    beacon.broadcastMode = (flag>>1)&0x07;//初始化
                    if (isEddystone&&str1.length>=4) {
                        if ([[str1 substringToIndex:1] integerValue]) {
                            beacon.eddystone_Url = [beacon eddystone_Url_To:[str1 substringFromIndex:4]];
                        }else{
                            beacon.eddystone_Uid = [str1 substringFromIndex:4];
                        }
                    }
                }else if ([beacon isSupport:BleSupportsAli]) {
                    beacon.lightSleep = (flag>>1)&0x1;
                    beacon.broadcastMode = 0;//初始化防止干扰。
                    beacon.broadcastMode |= (int)((flag>>2)&0x1)<<2;
                    beacon.broadcastMode |= (int)((flag>>3)&0x1)<<1;
                    beacon.broadcastMode |= (flag>>4)&0x1;
                    if (isEddystone&&str1.length>=4) {
                        if ([[str1 substringToIndex:1] integerValue]) {
                            beacon.eddystone_Url = [beacon eddystone_Url_To:[str1 substringFromIndex:4]];
                        }else{
                            beacon.eddystone_Uid = [str1 substringFromIndex:4];
                        }
                    }
                }
                if ([beacon isSupport:BleSupportsAdvRFOff]){
                    beacon.isOff2402 = (flag>>12)&0x1;
                    beacon.isOff2426 = (flag>>13)&0x1;
                    beacon.isOff2480 = (flag>>14)&0x1;
                }
                beacon.firmwareVersion =[NSString stringWithFormat:@"%ld",subHexStr2Long(str, 30, 4)];
                beacon.battery = [NSNumber numberWithInteger:subHexStr2Long(str, 34, 2)];
                beacon.temperature = [NSNumber numberWithInteger:subHexStr2Long(str, 36, 2)];
                if([beacon isSupport:BleSupportsLight])beacon.light = subHexStr2Long(str, 38, 4);
                beacon.userData = [str substringWithRange:NSMakeRange(42, 8)];
                if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:didDiscoverBeacon:)]) {
                    [self.delegate beaconManager:self didDiscoverBeacon:beacon];
                }
            }else{
                NSString *hversion = [str substringWithRange:NSMakeRange(22, 2)];
                long ihversion = strtol([hversion UTF8String],0,16);
                
                NSString *sbattery = [str substringWithRange:NSMakeRange(24, 2)];
                unsigned long ibattery = strtoul([sbattery UTF8String],0,16);
                
                NSString *stemperature = [str substringWithRange:NSMakeRange(26, 2)];
                unsigned long uitemperature = strtoul([stemperature UTF8String],0,16);
                long itemperature = uitemperature > 127? (uitemperature - 256): uitemperature;
                
                NSString *hlight = [str substringWithRange:NSMakeRange(28, 4)];
                long ilight = strtol([hlight UTF8String],0,16);
                
                NSString *hfirmware = [str substringWithRange:NSMakeRange(32, 4)];
                long ifirmware = strtol([hfirmware UTF8String],0,16);
                
                beacon.battery = [NSNumber numberWithUnsignedLong:ibattery];
                beacon.temperature = [NSNumber numberWithLong:itemperature];
                beacon.hardwareVersion = [NSString stringWithFormat:@"%ld",ihversion];
                if(ifirmware&&ifirmware!=65535)beacon.firmwareVersion = [NSString stringWithFormat:@"%ld",ifirmware];
                if([beacon isSupport:BleSupportsLight])beacon.light = ilight;
                if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:didDiscoverBeacon:)]) {
                    [self.delegate beaconManager:self didDiscoverBeacon:beacon];
                }
            }
        }else if(([key isEqualToString:@"80E7"]||[key isEqualToString:@"81E7"])&&str.length>40){
            //兼容Ex设备
            //80E7 = <b0222c2e 1bd66c49 (MM)a40084bb (mac)3d3cdd(battery)47 (temp)15(light)0002(移动次数)03 000000>
            //b0222c2e 1bd66c49 ffff-007b (MAC)3d3cdd-50 20 ffff330000ff
            NSString *mac = [NSString stringWithFormat:@"01:17:c5:%@:%@:%@",[str substringWithRange:NSMakeRange(24, 2)],[str substringWithRange:NSMakeRange(26, 2)],[str substringWithRange:NSMakeRange(28, 2)]];
            NSString *smajor = [str substringWithRange:NSMakeRange(16, 4)];
            unsigned long imajor = strtoul([smajor UTF8String],0,16);
            
            NSString *sminor = [str substringWithRange:NSMakeRange(20, 4)];
            unsigned long iminor = strtoul([sminor UTF8String],0,16);
            NSString *sbattery = [str substringWithRange:NSMakeRange(30, 2)];
            unsigned long ibattery = strtoul([sbattery UTF8String],0,16);
            
            NSString *stemperature = [str substringWithRange:NSMakeRange(32, 2)];
            unsigned long uitemperature = strtoul([stemperature UTF8String],0,16);
            long itemperature = uitemperature > 127? (uitemperature - 256): uitemperature;
            
            MESHBeacon *beacon = b;
            beacon.isMeshBeacon = NO;
            beacon.peripheral = peripheral;
            beacon.distance = [NSNumber numberWithFloat:[MESHBeacon rssiToDistance:beacon]];
            beacon.name = peripheral.name;
            beacon.macAddress = mac;
            beacon.major = [NSNumber numberWithUnsignedLong:imajor];
            beacon.minor = [NSNumber numberWithUnsignedLong:iminor];
            beacon.measuredPower = @-77;//[NSNumber numberWithLong:imeasure];
            
            beacon.battery = [NSNumber numberWithUnsignedLong:ibattery];
            beacon.temperature = [NSNumber numberWithLong:itemperature-10];
            beacon.hardwareVersion = key;//[NSString stringWithFormat:@"%ld",ihversion];
            if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:didDiscoverBeacon:)]) {
                [self.delegate beaconManager:self didDiscoverBeacon:beacon];
            }
        }
    }else {
        NSString *str = nil;
        BOOL isOnlyOne = (advertisementData.allKeys.count==1);
        for (id obj in advertisementData.allKeys) {
            if ([[obj description] isEqualToString:@"kCBAdvDataManufacturerData"]) {
                str = [self getHexString:[advertisementData objectForKey:obj]];
                break;
            }
            if (![[obj description] isEqualToString:@"kCBAdvDataIsConnectable"]) {
                isOnlyOne = NO;
            }
        }
        if (str.length>=54) {
            //防丢器解析15F0 = beafd3cfcfd3 afbe bf00 00 0201 0001 64 19 0000 ffffffffffff0a18
            //MAC        Major minor mp flag ver sver bat temp light
            //4e9839364cf1 01f4 01f4 bf 0001 0301 0004 64 15 0000 ffffffffffff0a18
            //4e9839364cf1 0000 0000 20 0000 0306 0002 2d 17 0000ffffffffffff0a18
            NSString *mac = [NSString stringWithFormat:@"%@:%@:%@:%@:%@:%@",[str substringWithRange:NSMakeRange(10, 2)],[str substringWithRange:NSMakeRange(8, 2)],[str substringWithRange:NSMakeRange(6, 2)],[str substringWithRange:NSMakeRange(4, 2)],[str substringWithRange:NSMakeRange(2, 2)],[str substringWithRange:NSMakeRange(0, 2)]];
            NSInteger major = subHexStr2Long(str, 12, 4);
            NSInteger minor = subHexStr2Long(str, 16, 4);
            
            MESHBeacon *beacon = b;
            beacon.isMeshBeacon = YES;
            beacon.peripheral = peripheral;
            beacon.name = peripheral.name;
            beacon.macAddress = mac;
            beacon.major = [NSNumber numberWithInteger:major];
            beacon.minor = [NSNumber numberWithInteger:minor];
            beacon.measuredPower = [NSNumber numberWithInteger:subHexStr2Long(str, 20, 2)-256];
            
            NSInteger flag = subHexStr2Long(str, 22, 4);
            beacon.flag = flag;
            beacon.mode = flag&0x1;
            
            beacon.hardwareVersion = [str substringWithRange:NSMakeRange(26, 4)];//[NSString stringWithFormat:@"%lu",subHexStr2Long(str, 26, 4)];
            if ([beacon isSupport:BleSupportsAli]) {
                beacon.lightSleep = (flag>>1)&0x1;
                beacon.broadcastMode = 0;//初始化防止干扰。
                beacon.broadcastMode |= (int)((flag>>2)&0x1)<<2;
                beacon.broadcastMode |= (int)((flag>>3)&0x1)<<1;
                beacon.broadcastMode |= (flag>>4)&0x1;
            }
            if ([beacon isSupport:BleSupportsAdvRFOff]){
                beacon.isOff2402 = (flag>>12)&0x1;
                beacon.isOff2426 = (flag>>13)&0x1;
                beacon.isOff2480 = (flag>>14)&0x1;
            }
            beacon.firmwareVersion =[NSString stringWithFormat:@"%lu",subHexStr2Long(str, 30, 4)];
            beacon.battery = [NSNumber numberWithInteger:subHexStr2Long(str, 34, 2)];
            beacon.temperature = [NSNumber numberWithInteger:subHexStr2Long(str, 36, 2)];
            if([beacon isSupport:BleSupportsLight])beacon.light = subHexStr2Long(str, 38, 4);
            beacon.userData = [str substringWithRange:NSMakeRange(42, 8)];
            if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:didDiscoverBeacon:)]) {
                [self.delegate beaconManager:self didDiscoverBeacon:beacon];
            }
        }/*else if(iosversion>=9&&isOnlyOne&&[self.mdict_uuid valueForKey:pUUID]){
          //特殊处理IOS9,无法获取到manufacturerData
          NSString *mac = [self.mdict_uuid valueForKey:pUUID];
          MESHBeacon *beacon = b;
          beacon.isMeshBeacon = YES;
          beacon.peripheral = peripheral;
          beacon.name = peripheral.name;
          beacon.macAddress = [self.mdict_uuid valueForKey:pUUID];
          
          beacon.major = nil;
          beacon.minor = nil;
          beacon.hardwareVersion = @"0304";
          beacon.firmwareVersion = @"8";
          if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:didDiscoverBeacon:)]) {
          [self.delegate beaconManager:self didDiscoverBeacon:beacon];
          }
          }*/
    }
    NSArray *array = [advertisementData valueForKey:@"kCBAdvDataServiceUUIDs"];
    if (disconnect&&array.count==14) {
        //老固件解析
        NSString *smeasuredpower = [self convertCBUUIDToString:array[10]];
        if ([smeasuredpower rangeOfString:@"42"].length==2) {
            int i=0;
            NSString *uuid = nil;
            NSMutableString *mac = [NSMutableString string];
            NSMutableData *mdata = [NSMutableData data];
            for (CBUUID *uid in array){
                if (i<8) {
                    [mdata appendData:uid.data];
                }else if(i==8) {
                    uuid = [self convertCBUUIDToString:[CBUUID UUIDWithData:mdata]];
                }else if(i>10){
                    const unsigned char *uuidBytes = [uid.data bytes];
                    [mac appendFormat:@"%02x:",uuidBytes[0]];
                    if (i==13) {
                        [mac appendFormat:@"%02x",uuidBytes[1]];
                    }else{
                        [mac appendFormat:@"%02x:",uuidBytes[1]];
                    }
                }
                i++;
            }
            NSString *smajor = [self convertCBUUIDToString:array[8]];
            NSString *sminor = [self convertCBUUIDToString:array[9]];
            
            NSNumber *major = [NSNumber numberWithUnsignedLong:strtoul([smajor UTF8String],0,16)];
            NSNumber *minor = [NSNumber numberWithUnsignedLong:strtoul([sminor UTF8String],0,16)];
            NSNumber *measuredpower = [NSNumber numberWithShort:strtol([[smeasuredpower substringToIndex:2] UTF8String],0,16)-256];
            if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:didDiscoverBeacon:)]) {
                MESHBeacon *beacon = b;
                beacon.isMeshBeacon = YES;
                beacon.peripheral = peripheral;
                beacon.name = peripheral.name;
                beacon.macAddress = mac;
                beacon.hardwareVersion = @"42";
                beacon.proximityUUID = [[NSUUID alloc] initWithUUIDString:uuid];
                beacon.major = major;
                beacon.minor = minor;
                beacon.measuredPower =measuredpower;
                if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconManager:didDiscoverBeacon:)]) {
                    [self.delegate beaconManager:self didDiscoverBeacon:beacon];
                }
            }
        }
    }
    if (b.macAddress.length == 0) {
        [mdict removeObjectForKey:pUUID];
    }
}
@end
