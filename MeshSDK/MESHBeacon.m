//
//  MeshSDK.m
//  MeshSDK
//
//  Created by arron on 18-2-2.
//  Copyright (c) 2018年 arron. All rights reserved.
//

#import "MESHBeacon.h"
#import "MESHBeaconManager.h"
#import "AntiLose.h"
#import "CBeacon.h"
#import "MESHTools.h"
#define MESHSDK_APPKEY [[NSUserDefaults standardUserDefaults] valueForKey:@"MESHSDK_APPKEY"]?:DEFAULT_KEY

typedef enum : int
{
    IB_Service=80,
    IB_UUID,
    IB_Major,
    IB_Minor,
    IB_MPower,
    IB_Light,//IB_LED
    IB_Interval,
    IB_TX,
    IB_Key,
    IB_Name,
    IB_Battery,//90
    IB_Temperature,
    IB_DEVPUB,
    IB_Battery_Interval,
    IB_Temperature_Interval,
    IB_Light_Interval,
    IB_Light_Sleep
} IBeacon_UUID;

typedef enum : int
{
    IB_DFU_Service=0,
    IB_DFU_Notify,//带通知的头包
    IB_DFU_BLOCK,//写数据
    IB_DFU_Firmware//版本获取
} IB_DFU;

#define IB_SERVICE_UUID(x)  [NSString stringWithFormat:@"B07028%d-A295-A8AB-F734-031A98A512DE",x]
#define IB_SERVICE_DFU(x)   [NSString stringWithFormat:@"F000FFC%d-0451-4000-B000-000000000000",x]

#define HI_UINT16(a) (((a) >> 8) & 0xff)
#define LO_UINT16(a) ((a) & 0xff)

#define OAD_IMG_CRC_OSET      0x0000
#if defined FEATURE_OAD_SECURE
#define OAD_IMG_HDR_OSET      0x0000
#else  // crc0 is calculated and placed by the IAR linker at 0x0, so img_hdr_t is 2 bytes offset.
#define OAD_IMG_HDR_OSET      0x0002
#endif

// Image header size (version + length + image id size)
#define OAD_IMG_HDR_SIZE      ( 2 + 2 + OAD_IMG_ID_SIZE )
// Image Identification size
#define OAD_IMG_ID_SIZE       4
// The Image is transporte in 16-byte blocks in order to avoid using blob operations.
#define OAD_BLOCK_SIZE        16
#define HAL_FLASH_WORD_SIZE 4
// The Image Header will not be encrypted, but it will be included in a Signature.
typedef struct {
#if defined FEATURE_OAD_SECURE
    // Secure OAD uses the Signature for image validation instead of calculating a CRC, but the use
    // of CRC==CRC-Shadow for quick boot-up determination of a validated image is still used.
    uint16_t crc0;       // CRC must not be 0x0000 or 0xFFFF.
#endif
    uint16_t crc1;       // CRC-shadow must be 0xFFFF.
    // User-defined Image Version Number - default logic uses simple a '<' comparison to start an OAD.
    uint16_t ver;
    uint16_t len;        // Image length in 4-byte blocks (i.e. HAL_FLASH_WORD_SIZE blocks).
    uint8_t  uid[4];     // User-defined Image Identification bytes.
    uint8_t  res[4];     // Reserved space for future use.
} img_hdr_t;

@interface NSMutableDictionary (nilValue)
@end
@implementation NSMutableDictionary (nilValue)

- (BOOL)setNoNilValue:(id)value def:(id)value2 forKey:(NSString *)key
{
    if (value) {
        [self setValue:value forKey:key];
    }else if(value2){
        [self setValue:value2 forKey:key];
    }else{
        return NO;
    }
    return YES;
}

@end

@interface MESHBeacon (){
    NSInteger readedCharacteristicCount;
    NSInteger isValidate;
    //    NSInteger isUpdateVersion;
}

//Characterics
@property (nonatomic,strong) NSMutableDictionary *dict_Service_IB;
@property (nonatomic,strong) NSMutableDictionary *dict_Service_DFU;
@property (nonatomic,strong) NSMutableDictionary *dict_DFU_Data;
//BEACON
//connect block
@property (nonatomic,copy) MESHCompletionBlock connectBeaconCompletion;
@property (nonatomic,copy) MESHDataCompletionBlock readBeaconValuesCompletion;
//read block
@property (nonatomic,copy) MESHCompletionBlock readALButtonAlarmCompletion;
@property (nonatomic,copy) MESHDataCompletionBlock readBeaconChangesCompletion;
@property (nonatomic,copy) MESHDataCompletionBlock readDFUCompletion;

@property (nonatomic,copy) MESHDataCompletionBlock sendBeaconCompletion;
//write block
@property (nonatomic,copy) MESHCompletionBlock writeBeaconCompletion;
//OAD
@property (strong,nonatomic) NSData *imageFile;
@property NSInteger nBlocks;
//@property int nBytes;
@property NSInteger iBlocks;
@property NSInteger iBytes;
@property BOOL canceled;
@property BOOL inProgramming;
@property uint16_t imgVersion;

@property (nonatomic, copy) MESHDataCompletionBlock updateBeaconFirmwareProgress;
@property (nonatomic, copy) MESHCompletionBlock updateBeaconFirmwareCompletion;

@end

@implementation MESHBeacon

+ (float)rssiToDistance:(MESHBeacon*)beacon {
    
    double mpower = beacon.measuredPower.floatValue;
    double ratio = (double)beacon.rssi / (mpower<0?mpower:-65);
    double rssiCorrection = 0.96 + ((int)pow(ABS(beacon.rssi),3.0)) % 10 / 150.0;
    
    if (ratio <= 1.0) {
        return pow(ratio, 9.98) * rssiCorrection;
    }
    
    return (0.103 + 0.89978 * pow(ratio, 7.5)) * rssiCorrection;
}

+ (float)distanceByRssi:(NSInteger)rssi oneMeterRssi:(NSInteger)mpower {
    double ratio = (double)rssi / (mpower<0?mpower:-65);
    double rssiCorrection = 0.96 + ((int)pow(ABS(rssi),3.0)) % 10 / 150.0;
    
    if (ratio <= 1.0) {
        return pow(ratio, 9.98) * rssiCorrection;
    }
    
    return (0.103 + 0.89978 * pow(ratio, 7.5)) * rssiCorrection;
}

- (NSString *)CBUUID2String:(CBUUID*)uuid {
    if ([self respondsToSelector:@selector(UUIDString)]) {
        return [uuid UUIDString]; // Available since iOS 7.1
    } else {
        return [[[NSUUID alloc] initWithUUIDBytes:[[uuid data] bytes]] UUIDString]; // iOS 6.0+
    }
}
- (id)init{
    self = [super init];
    if (self) {
        self.measuredPower = [NSNumber numberWithInt:-65];
        _accuracy = -1;
        _isConnected = NO;
    }

    return self;
}
- (void)updateVersion:(NSNotification*)notify {
    //    isUpdateVersion = 1;
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (NSNumber *)distance{
    if (self.accuracy>=0) {
        return [NSNumber numberWithFloat:self.accuracy];
    }
    NSNumber *d = [NSNumber numberWithFloat:[MESHBeacon rssiToDistance:self]];
    return d;
}
- (NSNumber *)battery {
    if (self.hardwareVersion.integerValue==902&&self.firmwareVersion.integerValue==1){
        return @(MIN(100,(int)(_battery.integerValue*1.25)));
    }
    return _battery;
}
- (void)setAccuracy:(CLLocationAccuracy)accuracy {
    if (accuracy < 0) {
        _accuracy = [MESHBeacon rssiToDistance:self];
    }else{
        _accuracy = accuracy;
    }
}
- (void)setName:(NSString *)name {
    //如果peripheral的名字和 self.name不同，保留修改，保留本身name
    if (_name.length) {
        if (self.peripheral&&![self.peripheral.name isEqualToString:name]) {
            _name = name;
        }
    }else{
        _name = name;
    }
}
- (NSData*)eddystone_Url_From:(NSString*)url {
    if ([url hasSuffix:@".com/"]) {
        //为了兼容，屏蔽末尾为.com/
        url = [url stringByReplacingCharactersInRange:NSMakeRange(url.length-5, 5) withString:@".com"];
    }
    NSMutableData *mdata = [NSMutableData data];
    NSRange range;
    NSArray *array = @[@"http://www.",@"https://www.",@"http://",@"https://"];
    for (NSString *str in array) {
        range = [url rangeOfString:str];
        if (range.location==0) {
            url = [url substringFromIndex:str.length];
            [mdata appendData:[self hexStrToNSData:[NSString stringWithFormat:@"%2ld",(long)[array indexOfObject:str]]]];
            break;
        }
    }
    array = @[@".com/",@".org/",@".edu/",@".net/",@".info/",@".biz/",@".gov/",@".com",@".org",@".edu",@".net",@".info",@".biz",@".gov"];
    NSData *data = [url dataUsingEncoding:NSUTF8StringEncoding];
    NSString *hexStr = [self NSDataToHexString:data];
    for (NSString *str in array) {
        NSString *hex = [self NSDataToHexString:[str dataUsingEncoding:NSUTF8StringEncoding]];
        hexStr = [hexStr stringByReplacingOccurrencesOfString:hex withString:[NSString stringWithFormat:@"%02lx",(unsigned long)[array indexOfObject:str]]];
    }
    [mdata appendData:[self hexStrToNSData:hexStr]];
    //超过限制会无法保存回调。
    //            [mdata appendData:[self hexStrToNSData:@"00" withSize:20]];
    return mdata;

}
- (NSString*)eddystone_Url_To:(NSString*)eddystoneUrl {
    NSRange range = [eddystoneUrl rangeOfString:@"0000"];
    if (!range.length) {
        range = [eddystoneUrl rangeOfString:@"ffff"];
    }
    if (range.length) {
        //不完美兼容(PS:故配合from，直接屏蔽以 .com/ 结尾的为 .com)
        eddystoneUrl = [eddystoneUrl substringToIndex:range.location];
    }
    if (eddystoneUrl.length) {
        NSArray *array = @[@".com/",@".org/",@".edu/",@".net/",@".info/",@".biz/",@".gov/",@".com",@".org",@".edu",@".net",@".info",@".biz",@".gov"];
        NSString *hexStr = eddystoneUrl;
        NSInteger http = strtol([[hexStr substringToIndex:2] UTF8String], 0, 16);
        NSString *hex = nil;
        if (http>=0&&http<4) {
            hex = [self NSDataToHexString:[@[@"http://www.",@"https://www.",@"http://",@"https://"][http] dataUsingEncoding:NSUTF8StringEncoding]];
            hexStr = [hexStr substringFromIndex:2];
        }
        for (NSInteger i=0;i<13;i++) {
            NSRange range = NSMakeRange(0, 0);
            NSString *hex1 = [self NSDataToHexString:[array[i] dataUsingEncoding:NSUTF8StringEncoding]];
            //必须要偶数位匹配，例如误解析03：6674703a2f2f7777772e626169647507
            do {
                NSInteger offset = range.location+range.length;
                range = [hexStr rangeOfString:[NSString stringWithFormat:@"%02lx",(long)i] options:0 range:NSMakeRange(offset, hexStr.length-offset)];
                if (range.length&&range.location%2==0) {
                    hexStr = [hexStr stringByReplacingCharactersInRange:range withString:hex1];
                }
            } while (range.length);
        }
        NSString *tmp = [NSString stringWithFormat:@"%@%@",hex?:@"",hexStr];

        unsigned int bytes =  0x00;
        NSMutableData *data = [NSMutableData dataWithData:[self hexStrToNSData:tmp]];
        [data appendBytes:&bytes length:1];
        eddystoneUrl = [MESHTools data2UTF8:data];
        return eddystoneUrl;
    }else{
        return nil;
    }
}
#pragma -- Validate Metheds

- (NSData*)NumberToNSData:(NSString*)number withSize:(NSInteger)size
{
    NSString *hexStr = [NSString stringWithFormat:@"%llx",number.longLongValue];
    return [self hexStrToNSData:hexStr withSize:size];
}
//十六進位字串轉bytes，可以設定size，padding在左邊，size=byte数,data.length超过会截取左边
-(NSData *) hexStrToNSData:(NSString *)data withSize:(NSInteger)size
{
    NSInteger add = size*2 - data.length;
    if (add > 0) {
        NSString* tmp = [[NSString string] stringByPaddingToLength:add withString:@"0" startingAtIndex:0];
        data = [tmp stringByAppendingString:data];
    }else if(add<0){
        NSLog(@"hex too long");
        return [self hexStrToNSData:[data substringFromIndex:-add]];
    }
    return [self hexStrToNSData:data];
}
//十六進位字串轉bytes
-(NSData *)hexStrToNSData:(NSString *)hexString {
    return [MESHTools hex2data:hexString];
}
//bytes轉十六進位字串，不是base64哦，別搞混了
-(NSString *) NSDataToHexString:(NSData *)data
{
    return [MESHTools data2hex:data];
}

- (void)validateSDKKEY{
    NSString *keyString = MESHSDK_APPKEY;
    if (!keyString.length) {
        keyString = DEFAULT_KEY;
    }
    NSData *data = nil;
    if ([self isSupport:BleSupports16Key]) {
        data = [self hexStrToNSData:keyString withSize:16];
        CBCharacteristic *c = self.dict_Service_IB[IB_SERVICE_UUID(IB_Key)];
        if (!c) {
            c = self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_Key16)];
        }
        [self writeValue:data forCharacteristic:c type:CBCharacteristicWriteWithResponse];
    }else{
        data = [self hexStrToNSData:[keyString stringByAppendingString:@"01"] withSize:17];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Key)] type:CBCharacteristicWriteWithResponse];
    }
}
- (void)resetSDKKEY{
    NSString *key = MESHSDK_APPKEY;
    if ([self isSupport:BleSupportsExtension]) {
        [self sendBeaconValue:[self hexStrToNSData:[NSString stringWithFormat:@"0303%@",key]] withCompletion:nil];
    }else if([self isSupport:BleSupportsNordic]){
        NSData *data = [self hexStrToNSData:key withSize:16];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_Key16)] type:CBCharacteristicWriteWithResponse];
    }else{
        NSData *data = [self hexStrToNSData:key withSize:17];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Key)] type:CBCharacteristicWriteWithResponse];
    }
}
#pragma -- Private Metheds
-(void)connectToBeacon{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beaconDidDisconnect:) name:kNotifyDisconnect object:nil];
    if (self.peripheral) {
//        [MESHBeaconSDK stopScan];
        self.peripheral.delegate = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kNotifyConnect object:self.peripheral];
//            [[[MESHBeaconSDK MESHBeaconManager] centralManager] connectPeripheral:self.peripheral options:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey]];
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeOutForConnect) object:nil];
            [self performSelector:@selector(timeOutForConnect) withObject:nil afterDelay:15];
        });
    }else{
        [self beaconDidDisconnect:nil];
    }
}
- (BOOL)isConnecting {
    BOOL isIOS7 =([[[UIDevice currentDevice] systemVersion] intValue]>=7);
    BOOL disconnect = isIOS7?(_peripheral.state == CBPeripheralStateDisconnected||_peripheral.state==3):(![_peripheral performSelector:@selector(isConnected)]);
    return !disconnect;
}
- (void)timeOutForConnect
{
    if ([self isConnecting]) {
        return;
    }else{
        void (^block) (void) = ^void () {
            [[NSNotificationCenter defaultCenter] postNotificationName:kNotifyDisconnect object:self.peripheral userInfo:@{@"error":[NSError errorWithDomain:NSLocalizedString(@"连接超时15s", @"蓝牙连接超时") code:ErrorCodeUnKnown userInfo:nil]}];
        };
        if ([NSThread isMainThread]) {
            block();
        }else{
            dispatch_async(dispatch_get_main_queue(),block);
        }
        [self disconnectBeacon];
    }
}
-(void)connectToBeaconWithCompletion:(MESHCompletionBlock)completion
{
    //    isUpdateVersion = 0;
    
    BOOL isIOS7 =([[[UIDevice currentDevice] systemVersion] intValue]>=7);
    BOOL connected = isIOS7?_peripheral.state == CBPeripheralStateConnected:((BOOL)[_peripheral performSelector:@selector(isConnected)]);
    if(connected) {
        completion(YES,nil);
        self.connectBeaconCompletion = nil;
    }else if([self isConnecting]){
        completion(NO,[NSError errorWithDomain:NSLocalizedString(@"正在连接，请稍后...", @"蓝牙连接提示") code:ErrorCodeUnKnown userInfo:nil]);
        [self disconnectBeacon];
        self.connectBeaconCompletion = nil;
    }else{
        self.connectBeaconCompletion = completion;
        [self connectToBeacon];
    }
}

-(void)disconnectBeacon{
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeOutForConnect) object:nil];
    });
    if(self.peripheral)[[NSNotificationCenter defaultCenter] postNotificationName:kNotifyCancelConnect object:self.peripheral];
        //[[[MESHBeaconSDK MESHBeaconManager] centralManager] cancelPeripheralConnection:self.peripheral];
}

#define isV(v) [self.hardwareVersion isEqual:v]

- (NSString *)hardwareVersion {
    if ([_hardwareVersion isEqualToString:@"0801"]&&_firmwareVersion.intValue == 1) {
        _hardwareVersion = @"0509";
    }
    return _hardwareVersion;
}

- (NSInteger)supportOption
{
    /////////////// 0.tag   1.base1 2.base2 3.plus    4.cb未定义 5.xb 0306.antiLose 其他品牌x-1.Sensoro x-2.四月
    /////////////// 0000     0101     0102  0303~0304 0401      0305 0306          F100               F200
    //温度电量间隔    1       1       1       1         1         1    1             0                  0
    //光感及间隔      0       0       0       1         0         0    0             1                  0
    //Tx4/6档        0       0       0       1         1         1    1             1                  0
    //appKey16/17位  1       1       1
    //支持阿里特征
    //防丢器特征
    if (isV(@"0508")||isV(@"0902")) {
        //AB芯片
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsEddystone|BleSupportsUserData|BleSupportsExtension|BleSupportsAdvRFOff|BleSupportsAB;
    }else if ([self.hardwareVersion hasPrefix:@"08"]) {
        //蓝牙模块固件
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsUserData|BleSupportsExtension|BleSupportsAdvRFOff|BleSupportsSerialData;
    }else if (isV(@"0509")) {
        //加密固件
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsUserData|BleSupportsExtension|BleSupportsAdvRFOff|BleSupportsEncrypt;
    }else if (isV(@"0314")||isV(@"0514")||isV(@"0516")) {
        //多特征：万达3特征
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsUserData|BleSupportsExtension|BleSupportsAdvRFOff;
    }else if ([self.hardwareVersion hasPrefix:@"05"]) {
        //双特征，及050x系列通用
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsEddystone|BleSupportsUserData|BleSupportsExtension|BleSupportsAdvRFOff;
    }else if (isV(@"42")) {
        //旧版 b-tag/b-base
        self.supportOption = BleSupportsCC254x;
    }else if (isV(@"0")||isV(@"1")||isV(@"2")) {
        self.supportOption = BleSupportsCC254x;
        if (isV(@"0")&&[self.firmwareVersion integerValue]>=2) {
            _supportOption |=BleSupportsUpdateName;
        }else if (isV(@"1")&&[self.firmwareVersion integerValue]>=9) {
            _supportOption |=BleSupportsUpdateName;
        }else if (isV(@"2")&&[self.firmwareVersion integerValue]>=3) {
            _supportOption |=BleSupportsUpdateName;
        }
    }else if (isV(@"3")) {
        //旧版 b-plus
        self.supportOption = BleSupportsNordic|BleSupportsLight|BleSupports16Key|BleSupportsUpdateName;
    }else if (isV(@"5")) {
        //旧版 x-beacon
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName;
    }else if (isV(@"0100")||isV(@"0101")||isV(@"0102")) {
        //b-tag
        //b-base
        self.supportOption = BleSupportsCC254x|BleSupportsUpdateName|BleSupports16Key|BleSupportsAli|BleSupportsCombineCharacteristic;
    }else if (isV(@"0304")) {
        //Plus
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsLight|BleSupportsUpdateName|BleSupportsAli|BleSupportsCombineCharacteristic;
        if ([self.firmwareVersion integerValue]>=9) {
            _supportOption |= BleSupportsEddystone;
            if([self.firmwareVersion integerValue]>=10){
                _supportOption |= BleSupportsUserData;
            }
        }
    }else if (isV(@"0305")) {
        //x-Beacon
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsAli|BleSupportsCombineCharacteristic;
        if ([self.firmwareVersion integerValue]>=9) {
            _supportOption |= BleSupportsEddystone;
            if([self.firmwareVersion integerValue]>=10){
                _supportOption |= BleSupportsUserData;
            }
        }
    }else if (isV(@"0306")) {
        //防丢器
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsLight|BleSupportsUpdateName|BleSupportsAntiLose|BleSupportsCombineCharacteristic;
        if ([self.firmwareVersion integerValue]>=9) {
            _supportOption |= BleSupportsEddystone;
            if([self.firmwareVersion integerValue]>=10){
                _supportOption |= BleSupportsUserData;
            }
        }
    }else if (isV(@"0307")) {
        //ali测试样品(废弃)、最新黑色板子带光感
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsLight|BleSupportsUpdateName|BleSupportsAli|BleSupportsCombineCharacteristic;
        if ([self.firmwareVersion integerValue]>=3) {
            _supportOption |= BleSupportsEddystone;
            if([self.firmwareVersion integerValue]>=4){
                _supportOption |= BleSupportsUserData;
            }
        }
    }else if (isV(@"0313")) {
        //0313 唯一可以限制广播频点设备
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsLight|BleSupportsUpdateName|BleSupportsAli|BleSupportsCombineCharacteristic|BleSupportsEddystone|BleSupportsAdvRFOff|BleSupportsUserData;
    }else if ([self.hardwareVersion hasPrefix:@"03"]) {
        //基站版新版0308  B-Tag新版0309 USB0310 AAA0311 AA0312
        //未来其他03版本Nordic产品
        //self.hardwareVersion == nil的版本
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsAli|BleSupportsCombineCharacteristic;
        if ([self.firmwareVersion integerValue]>=3) {
            _supportOption |= BleSupportsEddystone;
            if([self.firmwareVersion integerValue]>=4){
                _supportOption |= BleSupportsUserData;
            }
        }
    }else if ([self.hardwareVersion hasPrefix:@"04"]) {
        //CloudBeacon 0401  0402 带串口通讯，以及未来版本
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsCombineCharacteristic|BleSupportsEddystone|BleSupportsSerialData|BleSupportsUserData;
    }
    else if (isV(@"80E7")){
        //sensoro
        self.supportOption = BleSupportsNordic|BleSupportsLight;
    }else{
        //未知版本(默认Nordic)
        self.supportOption = BleSupportsNordic|BleSupports16Key|BleSupportsUpdateName|BleSupportsAli|BleSupportsCombineCharacteristic;
        if ([self.hardwareVersion hasPrefix:@"09"]) {
            _supportOption |= BleSupportsExtension;
        }
    }
    return _supportOption;
}
- (BOOL)isSupport:(BleSupports)option
{
    //1001|0001 = 1001 Or 1001|0010!=1011
    return (option|self.supportOption)==self.supportOption;
}

- (BOOL)isEqual:(MESHBeacon*)object {
    //object是数组里边的 ，self是containsObject:后边的
    if ([object respondsToSelector:@selector(macAddress)]&&object.macAddress.length&&self.macAddress.length&&[object.macAddress isEqualToString:self.macAddress]) {
        //1、[ConfigBeaconViewController macAddress]: unrecognized selector sent to instance 0x15cf586d0
        //2、防止macAddress为“”
        return YES;
    }
    if ([object respondsToSelector:@selector(peripheral)]&&object.peripheral&&[object.peripheral isEqual:self.peripheral]) {
        //1、防止同时为nil
        //2、误判是同一个。。
        return YES;
    }
    return [super isEqual:object];
}
- (NSUInteger)hash {
    if (self.macAddress.length) {
        return self.macAddress.hash;
    }
    NSInteger result = self.proximityUUID.UUIDString.hash * 31 + self.major.hash;
    result = result * 31 + self.minor.hash;
    return result;
}
#pragma mark - read
- (BOOL)readValueForCharacteristic:(CBCharacteristic*)characteristic{
    if(characteristic){
        [self.peripheral readValueForCharacteristic:characteristic];
        return YES;
    }
    return NO;
}
- (void)readBeaconFirmwareVersionWithCompletion:(MESHDataCompletionBlock)completion
{
    if ([self isSupport:BleSupportsExtension]) {
        if(completion)completion([NSString stringWithFormat:@"%@-%@",self.hardwareVersion,self.firmwareVersion],nil);
    }else
        //当版本号识别错误了。。。
        if ([self isSupport:BleSupportsAntiLose]||([self isSupport:BleSupportsNordic]&&[self isSupport:BleSupportsAli])||(!self.dict_Service_DFU[IB_SERVICE_DFU(IB_DFU_Firmware)])) {
            [self readALDFUCompletion:completion];
        }else{
            if([self readValueForCharacteristic:self.dict_Service_DFU[IB_SERVICE_DFU(IB_DFU_Firmware)]]){
                self.readDFUCompletion = completion;
            }else{
                if(completion)completion(nil,[NSError errorWithDomain:NSLocalizedString(@"获取失败", @"读取硬件版本失败提示") code:ErrorCode103 userInfo:nil]);
            }
        }
}
#pragma mark - write
- (BOOL)writeValue:(NSData*)data forCharacteristic:(CBCharacteristic *)characteristic type:(CBCharacteristicWriteType)type
{
    if (data&&characteristic) {
        [self.peripheral writeValue:data forCharacteristic:characteristic type:type];
        return YES;
    }else{
        return NO;
    }
}
- (void)uploadBeaconValues:(NSDictionary*)values
{
    if (self.macAddress.length==0||[self.macAddress rangeOfString:@"-"].length) {
        return;
    }
    NSMutableDictionary *mdict = [NSMutableDictionary dictionaryWithDictionary:@{@"id": [self.macAddress stringByReplacingOccurrencesOfString:@":" withString:@""],@"appkey":MESHSDK_APPKEY}];
    [mdict setNoNilValue:values[B_NAME] def:self.name forKey:@"name"];
    [mdict setNoNilValue:[values[B_UUID] stringByReplacingOccurrencesOfString:@"-" withString:@""] def:[self.proximityUUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""] forKey:@"uuid"];
    [mdict setNoNilValue:values[B_MAJOR] def:self.major forKey:@"major"];
    [mdict setNoNilValue:values[B_MINOR] def:self.minor forKey:@"minor"];
    [mdict setNoNilValue:values[B_MEASURED] def:self.measuredPower forKey:@"measuredPower"];
    [mdict setNoNilValue:values[B_INTERVAL] def:self.advInterval?:@"" forKey:@"intervalMillis"];//以前必填
    [mdict setNoNilValue:values[B_TX] def:[NSNumber numberWithLong:self.power] forKey:@"tx"];
    [mdict setNoNilValue:values[B_LIGHT_INTERVAL] def:[NSNumber numberWithLong:self.lightCheckInteval] forKey:@"led"];
    [mdict setNoNilValue:values[B_MODE] def:[NSNumber numberWithInt:self.mode] forKey:@"pattern"];
    //    [mdict setNoNilValue:values[B_LIGHT_SLEEP] def:[NSNumber numberWithBool:self.lightSleep] forKey:@"lightsleep"];

    [mdict setNoNilValue:self.temperature def:nil forKey:@"temperature"];
    [mdict setNoNilValue:self.battery def:nil forKey:@"electricity"];
    [mdict setNoNilValue:self.hardwareVersion def:nil forKey:@"hardwareType"];

    [mdict setNoNilValue:@([self.firmwareVersion integerValue]) def:nil forKey:@"firmwareNum"];

    if (!values) {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        NSString *info = [NSString stringWithFormat:@"%@,%@,%@,%@,%@,%@,%@,%@,%ld",SDK_VERSION,[[UIDevice currentDevice] model],[[UIDevice currentDevice] systemVersion], [[UIDevice currentDevice] name],[infoDictionary objectForKey:@"CFBundleName"],[infoDictionary objectForKey:@"CFBundleShortVersionString"],[infoDictionary objectForKey:@"CFBundleVersion"],[infoDictionary objectForKey:@"CFBundleIdentifier"],(long)self.broadcastMode];

        [mdict setValue:info forKey:@"remark"];
    }

    NSString *lat = [[NSUserDefaults standardUserDefaults] valueForKey:@"lat"];
    NSString *lng = [[NSUserDefaults standardUserDefaults] valueForKey:@"lng"];
    NSString *addr = [[NSUserDefaults standardUserDefaults] valueForKey:@"addr"];
    [mdict setValue:lat?lat:@"" forKey:@"lat"];
    [mdict setValue:lng?lng:@"" forKey:@"lng"];
    [mdict setValue:addr?addr:@"" forKey:@"addr"];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"kinsertDeviceInfo" object:mdict];
}
- (void)sendBeaconValue:(NSArray *)values withDelegate:(id<MESHBeaconDelegate>)delegate {
    if(delegate)self.delegate = delegate;
    [self sendBeaconValues:values index:@(0)];
}

- (void)sendBeaconValues:(NSArray *)values index:(NSNumber *)index {
    if (index.integerValue == values.count) {
        return;
    }
    NSInteger idx = index.integerValue;
    NSLog(@"send:%@,%@",values[idx],[NSDate date]);
    [self sendBeaconValue:values[idx] withCompletion:^(id data, NSError *error) {
        void(^runOnMainThead)() = ^{
            [self sendBeaconValues:values index:@(idx+1)];
        };
        if ( [NSThread isMainThread] )runOnMainThead();
        else dispatch_async( dispatch_get_main_queue(), runOnMainThead);
    }];
}
- (void)sendBeaconValue:(NSData *)data withCompletion:(MESHDataCompletionBlock)completion {
    //检查连接状态
    if (![self isConnecting]) {
        if(completion)completion(nil,[NSError errorWithDomain:NSLocalizedString(@"设备已断开连接",nil) code:ErrorCodeUnKnown userInfo:nil]);
        return;
    }
    //发送数据beacon
    if (!self.dict_Service_IB[CB_SERVICE_IBeacon(1)]) {
        if(completion)completion(nil,[NSError errorWithDomain:NSLocalizedString(@"不支持的设备",nil) code:CBErrorCode1 userInfo:nil]);
    }else{
        //不能阻塞，易导致数据无法成功
        [NSThread sleepForTimeInterval:.35];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[CB_SERVICE_IBeacon(CB_RWData)] type:CBCharacteristicWriteWithoutResponse];
        if(completion)self.sendBeaconCompletion = completion;
    }
}

- (void)writeBeaconValues:(NSDictionary*)values withCompletion:(MESHCompletionBlock)completion
{
    //检查连接状态
    if (![self isConnecting]) {
        if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"设备已断开连接",nil) code:ErrorCodeUnKnown userInfo:nil]);
        return;
    }
    if (values[B_UUID]) {
        NSString *uuidRegex = @"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";
        NSPredicate *uuidTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", uuidRegex];
        if(![uuidTest evaluateWithObject:values[B_UUID]]){
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"UUID有误",nil) code:CBErrorCode1 userInfo:nil]);
            return;
        }
    }
    if ([values[B_LIGHT_INTERVAL] boolValue]||[values[B_LIGHT_SLEEP] boolValue]) {
        if (![self isSupport:BleSupportsLight]) {
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"不支持光感",nil) code:CBErrorCode1 userInfo:nil]);
            return;
        }
    }
    if ([values[B_InRange] boolValue]||[values[B_AutoAlarm] boolValue]||[values[B_ActiveFind] boolValue]||[values[B_ButtonAlarm] boolValue]) {
        if (![self isSupport:BleSupportsAntiLose]) {
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"不支持防丢设置",nil) code:CBErrorCode1 userInfo:nil]);
            return;
        }
    }
    if (values[B_SerialData]) {
        if (![self isSupport:BleSupportsSerialData]) {
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"不支持串口数据",nil) code:CBErrorCode1 userInfo:nil]);
            return;
        }else if ([values[B_SerialData] length]>20){
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"串口数据过长(<=20)",nil) code:CBErrorCode1 userInfo:nil]);
            return;
        }
    }
    if (values[B_UserData]) {
        if (![self isSupport:BleSupportsUserData]) {
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"不支持自定义广播数据",nil) code:CBErrorCode1 userInfo:nil]);
            return;
        }else if ([values[B_UserData] length]>8){
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"自定义广播数据过长(<=8)",nil) code:CBErrorCode1 userInfo:nil]);
            return;
        }
    }
    NSInteger v = [values[B_TX] integerValue];
    if (values[B_TX]) {
        if ([self isSupport:BleSupportsExtension]) {
            if(v==8){
                v = 4;
            }else if (v == 7) {
                v = 0;
            }else if (v == 6){
                v = -4;
            }else if (v == 5){
                v = -8;
            }else if (v == 3){
                v = -16;
            }else if (v == 2){
                v = -20;
            }else if (v == 1){
                v = -30;
            }
            if (!(v==-30||v==-20||v==-16||v==-12||v==-8||v==-4||v==0||v==4)) {
                if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"功率值未定义(注：功率值-30,-20,-16,-12,-8,-4,0,4)",nil) code:CBErrorCode1 userInfo:nil]);
                return;
            }
        }
    }
    if (self.dict_Service_IB[CB_SERVICE_IBeacon(1)]) {
        //发送数据beacon换方法
        //        if(completion)completion([NSError errorWithDomain:NSLocalizedString(@"请使用：writeCBeacon获取数据",nil) code:CBErrorCode1 userInfo:nil]);
        NSString *major = values[B_MAJOR];
        NSString *minor = values[B_MINOR];
        if ((major||minor)&&(major.integerValue!=self.major.integerValue||minor.integerValue!=self.minor.integerValue)) {
            NSString *major = values[B_MAJOR]?:self.major.stringValue;
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"0706"]];
            [mdata appendData:[self NumberToNSData:major withSize:2]];

            NSString *minor = values[B_MINOR]?:self.minor.stringValue;
            [mdata appendData:[self NumberToNSData:minor withSize:2]];
            [self sendBeaconValue:mdata withCompletion:nil];
        }
        NSString *mpower = values[B_MPOWER];
        if (mpower&&mpower.integerValue!=self.power) {
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"0903"]];
            NSData *data = [self NumberToNSData:[NSString stringWithFormat:@"%ld",(long)[values[B_MPOWER] integerValue]+256] withSize:1];
            [mdata appendData:data];
            [self sendBeaconValue:mdata withCompletion:nil];
        }
        NSString *power = values[B_TX];
        if (power&&v!=self.power) {
            NSData *data = [MESHTools hex2data:[NSString stringWithFormat:@"0B03%02hhx",(int8_t)v]];
            [self sendBeaconValue:data withCompletion:nil];
        }
        //eddystone url必须先设置，才能修改模式
        NSString *eddy = values[B_EddystoneURL];
        if (eddy&&![self.eddystone_Url isEqualToString:eddy]) {
            NSData *data = [self eddystone_Url_From:values[B_EddystoneURL]];
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:[NSString stringWithFormat:@"17%02lx",(long)data.length+2]]];
            [mdata appendData:data];
            if (mdata.length>20) {
                if(completion)completion(NO,[NSError errorWithDomain:[NSString stringWithFormat:NSLocalizedString(@"Eddystone URL超出(%lu)个字符",nil),(unsigned long)mdata.length-20] code:CBErrorCode1 userInfo:nil]);
                self.writeBeaconCompletion = nil;
                return;
            }
            [self sendBeaconValue:mdata withCompletion:nil];
        }

        if (values[@"flag"]||values[B_MODE]||values[B_BroadcastMode]||values[B_Off2402]||values[B_Off2426]||values[B_Off2480]) {
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"0D04"]];
            uint8_t buf[2] = {0x00};

            buf[1] |=  (values[B_MODE]?[values[B_MODE] boolValue]:self.mode)?0x1:0x0;
            BroadcastMode bMode = values[B_BroadcastMode]?(BroadcastMode)[values[B_BroadcastMode] integerValue]:self.broadcastMode;
            //buf[1] |=  ([mdict[B_LIGHT_SLEEP] boolValue]?0x1:0x0)<<1;已废弃
            buf[1] |=  (bMode&0x07)<<1;
            //            buf[1] |=  (bMode>>1&0x1)<<2;  1 1 1 1
            //            buf[1] |=  (bMode&0x1)<<3;

            //设置13 14 15位
            buf[0] |=  ((values[B_Off2402]?[values[B_Off2402] boolValue]:self.isOff2402)?0x1:0x0)<<5;
            buf[0] |=  ((values[B_Off2426]?[values[B_Off2426] boolValue]:self.isOff2426)?0x1:0x0)<<6;
            buf[0] |=  ((values[B_Off2480]?[values[B_Off2480] boolValue]:self.isOff2480)?0x1:0x0)<<7;

            //还原 8 9 10 11 12位
            buf[0] |= self.flag&0x01;
            buf[0] |= self.flag&0x02;
            buf[0] |= self.flag&0x04;
            buf[0] |= self.flag&0x08;
            buf[0] |= self.flag&0x10;

            //还原 4 5 6 7 位
            buf[1] |= self.flag&0x10;
            buf[1] |= self.flag&0x20;
            buf[1] |= self.flag&0x40;
            buf[1] |= self.flag&0x80;
            [mdata appendBytes:buf length:2];
            [self sendBeaconValue:mdata withCompletion:nil];
        }
        NSString *name = values[B_NAME];
        if(name&&![self.name isEqualToString:name]){
            NSData *data = [name dataUsingEncoding:NSUTF8StringEncoding];
            NSInteger limit = 16;//和之前保持一致
            NSInteger count = name.length;
            while (data.length > limit) {
                data = [[name substringToIndex:--count] dataUsingEncoding:NSUTF8StringEncoding];
            }
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:[NSString stringWithFormat:@"0F%02tx",data.length+2]]];
            [mdata appendData:data];
            char byte_chars[1] = {'\0'};
            [mdata appendBytes:byte_chars length:1];
            [self sendBeaconValue:mdata withCompletion:nil];
        }
        NSString *interval = values[B_INTERVAL];
        NSString *broadcatInterval = values[B_BROADCAT_INTERVAL];
        if(interval||broadcatInterval){
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"1106"]];
            NSData *data = [self NumberToNSData:values[B_INTERVAL]?:self.advInterval.stringValue withSize:2];
            [mdata appendData:data];
            data = [self NumberToNSData:values[B_BROADCAT_INTERVAL]?:self.broadcastInterval withSize:2];
            [mdata appendData:data];
            [self sendBeaconValue:mdata withCompletion:nil];
        }
        if(values[B_BATTERY_INTERVAL]||values[B_TEMPERATURE_INTERVAL]){
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"1306"]];
            NSData *data = [self NumberToNSData:values[B_BATTERY_INTERVAL]?:[NSString stringWithFormat:@"%ld",(long)self.batteryCheckInteval] withSize:2];
            [mdata appendData:data];
            data = [self NumberToNSData:values[B_TEMPERATURE_INTERVAL]?:[NSString stringWithFormat:@"%ld",(long)self.temperatureCheckInteval] withSize:2];
            [mdata appendData:data];
            [self sendBeaconValue:mdata withCompletion:nil];
        }
        NSString *userdata = values[B_UserData];
        if (userdata&&![self.userData isEqualToString:userdata]) {
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"1506"]];
            NSData *data = [self hexStrToNSData:values[B_UserData] withSize:4];
            [mdata appendData:data];
            [self sendBeaconValue:mdata withCompletion:nil];
        }
        NSString *pUUID = values[B_UUID]?:self.proximityUUID.UUIDString;
        if (pUUID) {
            CBUUID *uuid = [CBUUID UUIDWithString:pUUID];
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"0512"]];
            [mdata appendData:uuid.data];
            self.writeBeaconCompletion = completion;
            [self sendBeaconValue:mdata withCompletion:nil];
        }else{
            if(completion){
                [NSThread sleepForTimeInterval:2];
                completion(YES,nil);
            }
        }
        [self uploadBeaconValues:values];
    }else if (self.dict_Service_IB[AL_SERVICE_IBeacon(1)]) {
        if (self.advInterval == nil) {
            [self readBeaconValuesCompletion:^(id data, NSError *error) {
                [self writeALIBeaconValues:values withCompletion:completion];
                [self uploadBeaconValues:values];
            }];
        }else{
            [self writeALIBeaconValues:values withCompletion:completion];
            [self uploadBeaconValues:values];
        }
    }else{
        [self writeiBeaconValues:values withCompletion:completion];
        [self uploadBeaconValues:values];
    }
}
- (void)writeiBeaconValues:(NSDictionary *)values withCompletion:(MESHCompletionBlock)completion{
    if(values[B_NAME]&&![values[B_NAME] isEqualToString:self.name]){
        NSData *data = [values[B_NAME] dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableData *mdata = [NSMutableData dataWithData:data];
        [mdata appendData:[self hexStrToNSData:@"0" withSize:16]];
        data = [mdata subdataWithRange:NSMakeRange(0, 16)];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Name)] type:CBCharacteristicWriteWithResponse];
    }
    if(values[B_MAJOR]&&self.major.integerValue!=[values[B_MAJOR] integerValue]){
        NSData *data = [self NumberToNSData:values[B_MAJOR] withSize:2];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Major)] type:CBCharacteristicWriteWithResponse];
    }
    if(values[B_MINOR]&&self.minor.integerValue!=[values[B_MINOR] integerValue]){
        NSData *data = [self NumberToNSData:values[B_MINOR] withSize:2];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Minor)] type:CBCharacteristicWriteWithResponse];
    }
    if(values[B_INTERVAL]&&self.advInterval.integerValue!=[values[B_INTERVAL] integerValue]){
        NSData *data = [self NumberToNSData:values[B_INTERVAL] withSize:2];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Interval)] type:CBCharacteristicWriteWithResponse];
    }
    if(values[B_TX]&&self.power!=[values[B_TX] integerValue]){
        NSData *data = [self NumberToNSData:values[B_TX] withSize:1];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_TX)] type:CBCharacteristicWriteWithResponse];
    }
    if(values[B_MPOWER]&&self.measuredPower.integerValue!=[values[B_MPOWER] integerValue]){
        NSData *data = [self NumberToNSData:[NSString stringWithFormat:@"%ld",(long)[values[B_MPOWER] integerValue]+256] withSize:1];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_MPower)] type:CBCharacteristicWriteWithResponse];
    }
    if (values[B_MODE]&&self.mode!=[values[B_MODE] boolValue]){
        NSData *data = [self NumberToNSData:values[B_MODE] withSize:1];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_DEVPUB)] type:CBCharacteristicWriteWithResponse];
    }
    if (values[B_BATTERY_INTERVAL]&&self.batteryCheckInteval!=[values[B_BATTERY_INTERVAL] integerValue]){
        NSData *data = [self NumberToNSData:values[B_BATTERY_INTERVAL] withSize:4];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Battery_Interval)] type:CBCharacteristicWriteWithResponse];
    }
    if (values[B_TEMPERATURE_INTERVAL]&&self.temperatureCheckInteval!=[values[B_TEMPERATURE_INTERVAL] integerValue]){
        NSData *data = [self NumberToNSData:values[B_TEMPERATURE_INTERVAL] withSize:4];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Temperature_Interval)] type:CBCharacteristicWriteWithResponse];
    }
    if ([self isSupport:BleSupportsLight]&&values[B_LIGHT_INTERVAL]&&self.lightCheckInteval!=[values[B_LIGHT_INTERVAL] integerValue]){
        NSData *data = [self NumberToNSData:values[B_LIGHT_INTERVAL] withSize:4];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Light_Interval)] type:CBCharacteristicWriteWithResponse];
    }
    if ([self isSupport:BleSupportsLight]&&values[B_LIGHT_SLEEP]&&self.lightSleep!=[values[B_LIGHT_SLEEP] boolValue]){
        NSData *data = [self NumberToNSData:values[B_LIGHT_SLEEP] withSize:1];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Light_Sleep)] type:CBCharacteristicWriteWithResponse];
    }
    //每次都提交，用于返回 competition
    [self writeBeaconProximityUUID:values[B_UUID]?values[B_UUID]:self.proximityUUID.UUIDString withCompletion:^(BOOL complete,NSError *error) {
        if(completion)completion(complete,error);
    }];
}

- (void)writeBeaconProximityUUID:(NSString*)pUUID withCompletion:(MESHCompletionBlock)completion{
    NSString *uuidRegex = @"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";
    NSPredicate *uuidTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", uuidRegex];
    if([uuidTest evaluateWithObject:pUUID]){
        self.writeBeaconCompletion = completion;
        CBUUID *uuid = [CBUUID UUIDWithString:pUUID];
        NSData *data = uuid.data;
        [self writeValue:data forCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_UUID)] type:CBCharacteristicWriteWithResponse];
    }else{
        if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"UUID格式有误",nil) code:8 userInfo:nil]);
    }
}

-(void)updateBeaconFirmwareWithProgress:(MESHDataCompletionBlock)progress andCompletion:(MESHCompletionBlock)completion{

    if ((self.dict_Service_IB[CB_SERVICE_IBeacon(CB_RWData)]||self.dict_Service_DFU[AL_SERVICE_DFU(AL_DFU_Data20)]||self.dict_Service_DFU[IB_SERVICE_DFU(IB_DFU_Firmware)])&&self.firmwareVersionInfo.length) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@",self.firmwareVersionInfo.lastPathComponent]];
        NSData *data = nil;
        if ([fm fileExistsAtPath:path]) {
            data = [fm contentsAtPath:path];
        }else{
            progress(@0,[NSError errorWithDomain:NSLocalizedString(@"正在下载固件数据...",nil) code:0 userInfo:nil]);
            data = [NSData dataWithContentsOfURL:[NSURL URLWithString:self.firmwareVersionInfo]];
            [data writeToFile:path atomically:YES];
        }
        if (!data) {
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"固件下载失败，请重试",nil) code:ErrorCode107 userInfo:nil]);
        }else if ([self isSupport:BleSupportsCC254x]&&[data rangeOfData:[NSData dataWithBytes:([self.firmwareVersion rangeOfString:@"A"].length==1)?"BBBB":"AAAA" length:4] options:NSDataSearchAnchored range:NSMakeRange(8, 4)].location==NSNotFound) {
            if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"固件数据不正确，请重试",nil) code:ErrorCode108 userInfo:nil]);
        }else{
            self.updateBeaconFirmwareProgress = progress;
            self.updateBeaconFirmwareCompletion = completion;
            self.imageFile = data;
            self.canceled = FALSE;
            self.inProgramming = FALSE;
            [self uploadImage];
        }
    }else{
        if(completion)completion(NO,[NSError errorWithDomain:NSLocalizedString(@"暂无版本更新，或未执行版本检测：checkFirmwareUpdateWithCompletion:",nil) code:ErrorCode106 userInfo:nil]);
        return;
    }
}

-(NSData*)toJSON:(NSDictionary*)dict{
    NSError* error =nil;
    id result =[NSJSONSerialization dataWithJSONObject:dict
                                               options:kNilOptions error:&error];
    if(error !=nil)return nil;
    return result;
}

-(NSError*)PostData:(NSDictionary*)dict forUrl:(NSString*)urlString
{
    if((!dict)||dict.allKeys.count==0)
    {
        return nil;
    }
    NSData* postData =[self toJSON:dict];
    NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[postData length]];

    NSURL *baseUrl = [NSURL URLWithString: urlString];

    NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:baseUrl
                                                                   cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                               timeoutInterval:20.0f];


    [urlRequest setHTTPMethod: @"POST"];
    [urlRequest setURL:baseUrl];
    [urlRequest setValue: postLength forHTTPHeaderField:@"Content-Length"];
    [urlRequest setValue: @"application/json" forHTTPHeaderField:@"Content-Type"];
    [urlRequest setHTTPBody: postData];

    NSError *error = nil;
    NSHTTPURLResponse *response = nil;
    NSData *urlData = [NSURLConnection
                       sendSynchronousRequest:urlRequest
                       returningResponse: &response
                       error: &error];
    if (urlData.length) {
        NSDictionary *rlt = [NSJSONSerialization JSONObjectWithData:urlData options:NSJSONReadingAllowFragments error:NULL];
        if ([[rlt valueForKey:@"code"] integerValue]==200) {
            return nil;
        }else{
            return [NSError errorWithDomain:NSLocalizedString(@"网络连接失败",nil) code:ErrorCode102 userInfo:nil];
        }
    }else{
        return [NSError errorWithDomain:NSLocalizedString(@"网络连接失败",nil) code:ErrorCode102 userInfo:nil];
    }
}

- (void)writeBeaconMode:(DevelopPublishMode)mode withCompletion:(MESHCompletionBlock)completion
{
    [self writeBeaconValues:@{B_MODE:(mode==DevelopMode)?@"0":@"1"} withCompletion:completion];
    if(mode==DevelopMode){
        [self resetSDKKEY];
    }
}
-(void)resetBeaconToDefault{
    NSString *mac = [self.macAddress stringByReplacingOccurrencesOfString:@":" withString:@""];
    if (mac.length<12) {
        mac = @"000000000000";
    }
    NSString *dmajor = [mac substringWithRange:NSMakeRange(4,4)];
    NSString *dminor = [mac substringWithRange:NSMakeRange(8,4)];
    NSNumber *tx = I2N([self isSupport:BleSupportsExtension]?DEFAULT_TX_EX:[self isSupport:BleSupportsNordic]?DEFAULT_TX_PLUS:DEFAULT_TX);
    NSDictionary *values = nil;
    if([self isSupport:BleSupportsLight]){
        values = @{B_UUID:DEFAULT_UUID,
                   B_MAJOR:dmajor,
                   B_MINOR:dminor,
                   B_NAME:DEFAULT_NAME,
                   B_MPOWER:I2N(DEFAULT_MEASURED),
                   B_INTERVAL:I2N(DEFAULT_INTERVAL),
                   B_LIGHT_INTERVAL:I2N(DEFAULT_LCHECK_INTERVAL),
                   B_BATTERY_INTERVAL:I2N(DEFAULT_BCHECK_INTERVAL),
                   B_TEMPERATURE_INTERVAL:I2N(DEFAULT_TCHECK_INTERVAL),
                   B_LIGHT_SLEEP:I2N(DEFAULT_LIGHT_SLEEP),
                   B_TX:tx,
                   B_MODE:I2N(DEFAULT_MODE)};
    }else{
        values = @{B_UUID:DEFAULT_UUID,
                   B_MAJOR:dmajor,
                   B_MINOR:dminor,
                   B_NAME:DEFAULT_NAME,
                   B_MPOWER:I2N(DEFAULT_MEASURED),
                   B_INTERVAL:I2N(DEFAULT_INTERVAL),
                   B_BATTERY_INTERVAL:I2N(DEFAULT_BCHECK_INTERVAL),
                   B_TEMPERATURE_INTERVAL:I2N(DEFAULT_TCHECK_INTERVAL),
                   B_TX:tx,
                   B_MODE:I2N(DEFAULT_MODE)};
    }
    [self writeBeaconValues:values withCompletion:nil];
    [self resetSDKKEY];
}
#pragma -- Private Metheds

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

char hexCharToNibble(char nibble)
{
    // 0 - 9
    if (nibble >= '0' && nibble <= '9')
        return (nibble - '0') & 0x0F;
    // A - F
    else if (nibble >= 'A' && nibble <= 'F')
        return (nibble - 'A' + 10) & 0x0F;
    // a - f
    else if (nibble >= 'a' && nibble <= 'f')
        return (nibble - 'a' + 10) & 0x0F;
    return 0; // keep compiler happy
}

- (NSString *)characteristicToProximityUUID:(CBCharacteristic *)characteristic{
    NSString *temp = [MESHTools data2hex:characteristic.value];

    NSString *uuid;
    if (temp.length>=32) {
        NSRange r1 = NSMakeRange(8, 4);
        NSRange r2 = NSMakeRange(12, 4);
        NSRange r3 = NSMakeRange(16, 4);

        uuid = [temp substringToIndex:8];
        uuid = [uuid stringByAppendingString:@"-"];
        uuid = [uuid stringByAppendingString:[temp substringWithRange:r1]];
        uuid = [uuid stringByAppendingString:@"-"];
        uuid = [uuid stringByAppendingString:[temp substringWithRange:r2]];
        uuid = [uuid stringByAppendingString:@"-"];
        uuid = [uuid stringByAppendingString:[temp substringWithRange:r3]];
        uuid = [uuid stringByAppendingString:@"-"];
        uuid = [uuid stringByAppendingString:[temp substringWithRange:NSMakeRange(20, 12)]];
        uuid = [uuid uppercaseString];
    }else{
        NSLog(@"Unable to get UUID:%@",temp);
    }

    return uuid;
}

- (unsigned short)characteristicOneByteToShort:(CBCharacteristic *)characteristic{
    unsigned char data[1];
    [characteristic.value getBytes:data length:1];

    int value = data[0];

    return value;
}
//大端
- (unsigned short)characteristicTwoByteToShort:(CBCharacteristic *)characteristic{
    unsigned char data[2];
    [characteristic.value getBytes:data length:2];
    UInt16 value = data[0] << 8 | data[1];
    return value;
}
//大端
- (NSInteger)characteristicFourByteToInteger:(CBCharacteristic *)characteristic{
    unsigned char data[4];
    [characteristic.value getBytes:data length:4];
    UInt32 value = data[0] << 24 | data[1] << 16 | data[2] << 8 | data[3];
    return value;
}

- (NSString*)characteristicToVersion:(CBCharacteristic *)characteristic
{

    if([self isSupport:BleSupportsAli]){
        NSString *str = [self NSDataToHexString:characteristic.value];
        _hardwareVersion = [str substringToIndex:4];
        NSInteger firmversion = strtol([[str substringFromIndex:4] UTF8String],0,16);
        if([self isSupport:BleSupportsCC254x]){
            _firmwareVersion = [NSString stringWithFormat:@"%ld%@",(long)firmversion/2,(firmversion%2==1)?@"B":@"A"];
        }else{
            _firmwareVersion = [NSString stringWithFormat:@"%ld",(long)firmversion];
        }
        return [NSString stringWithFormat:@"%@-%@",_hardwareVersion,_firmwareVersion];
    }

    static char data[3];
    [characteristic.value getBytes:data length:3];

    UInt8 hardversion = data[0];
    UInt16 firmversion = (data[1]<<8&0xff00) | (data[2]&0xff);
    if ([self isSupport:BleSupportsNordic]) {
        _hardwareVersion = [NSString stringWithFormat:@"%d",hardversion];
        _firmwareVersion = [NSString stringWithFormat:@"%d",[self isSupport:BleSupportsNordic]?firmversion:firmversion/2];
        return [NSString stringWithFormat:@"%@-%@",_hardwareVersion,_firmwareVersion];
    }else{
        _hardwareVersion = [NSString stringWithFormat:@"%d",hardversion];
        _firmwareVersion = [NSString stringWithFormat:@"%d%@",firmversion/2,(firmversion%2==1)?@"B":@"A"];
        return [NSString stringWithFormat:@"%d-%d%@",hardversion,firmversion/2,(firmversion%2==1)?@"B":@"A"];
    }
}

#pragma mark -- CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(nullable NSError *)error
{
    if (error) {
        if (self.connectBeaconCompletion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.connectBeaconCompletion(NO,error);
                self.connectBeaconCompletion = nil;
            });
        }
        return;
    }
    BOOL findMyServices = NO;

    for (CBService *service in peripheral.services) {
        NSString *uuid = [self CBUUID2String:service.UUID];
        if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Service)]||[uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_Service)]||[uuid isEqualToString:CB_SERVICE_IBeacon(CB_Service)]) {
            [peripheral discoverCharacteristics:nil forService:service];
            findMyServices = YES;
            isValidate = 0;
            readedCharacteristicCount = 0;
        }else if ([uuid isEqualToString:IB_SERVICE_DFU(IB_DFU_Service)]||[uuid isEqualToString:AL_SERVICE_DFU(AL_DFU_Service)]) {
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }

    if (!findMyServices) {
//        [[[MESHBeaconSDK MESHBeaconManager] centralManager] cancelPeripheralConnection:self.peripheral];
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotifyCancelConnect object:peripheral];

        if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconConnection:withError:)]) {
            [self.delegate beaconConnection:self withError:error];
        }
        if (self.connectBeaconCompletion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.connectBeaconCompletion(NO,[NSError errorWithDomain:NSLocalizedString(@"未识别的设备",nil) code:ErrorCode101 userInfo:nil]);
                self.connectBeaconCompletion = nil;
                //防止断开连接继续调用
            });
        }
    }else{
        //无法使用验证过关，新增此处作为外部读取使用
        _isConnected = [self isConnecting];//self.peripheral.isConnected;
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    // Deal with errors (if any)
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
//        [[[MESHBeaconSDK MESHBeaconManager] centralManager] cancelPeripheralConnection:peripheral];
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotifyCancelConnect object:peripheral];
        if (self.connectBeaconCompletion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.connectBeaconCompletion(NO,error);
                self.connectBeaconCompletion = nil;
            });
        }
        return;
    }
    NSString *uuid = [self CBUUID2String:service.UUID];
    if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Service)]) {//ibeacon service
        self.dict_Service_IB = [NSMutableDictionary dictionary];
        for (CBCharacteristic *characteristic in service.characteristics) {
            //            [peripheral readValueForCharacteristic:characteristic];
            [self.dict_Service_IB setValue:characteristic forKey:[self CBUUID2String:characteristic.UUID]];
            if ([[self CBUUID2String:characteristic.UUID] isEqualToString:IB_SERVICE_UUID(IB_Key)]) {
                //老版本固件CC254x关闭以开启万能模式,一周失效
                //if([[NSDate date] compare:[NSDate dateWithTimeIntervalSince1970:1449476088+3600*24*7]]==NSOrderedDescending)
                //                 [self readValueForCharacteristic:characteristic];
                [self validateSDKKEY];
            }

        }
    }else if ([uuid isEqualToString:IB_SERVICE_DFU(IB_DFU_Service)]){  //OAD service
        self.dict_Service_DFU  =[NSMutableDictionary dictionary];
        for (CBCharacteristic *characteristic in service.characteristics) {
            [self.dict_Service_DFU setValue:characteristic forKey:[self CBUUID2String:characteristic.UUID]];
            self.imgVersion = 0xFFFF;
            /*if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:MESH_CHARACTERISTIC_OAD_NOTIFY]]) {
             self.characteristic_oad_notify = characteristic;
             [peripheral setNotifyValue:YES forCharacteristic:self.characteristic_oad_notify];
             self.imgVersion = 0xFFFF;
             }else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:MESH_CHARACTERISTIC_OAD_BLOCK]]) {
             self.characteristic_oad_block = characteristic;
             }else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:MESH_CHARACTERISTIC_FIRMWARE_UUID]]) {
             self.firmwareVersionCharacteristic = characteristic;
             [peripheral readValueForCharacteristic:characteristic];
             }*/
        }
    }

    //for anti-lose
    if ([uuid isEqualToString:AL_SERVICE_IBeacon(0)]) {//ibeacon service
        self.dict_Service_IB = [NSMutableDictionary dictionary];
        [service.characteristics enumerateObjectsUsingBlock:^(CBCharacteristic *c, NSUInteger idx, BOOL *stop) {
            [self.dict_Service_IB setValue:c forKey:[self CBUUID2String:c.UUID]];
            if ([[self CBUUID2String:c.UUID] isEqualToString:AL_SERVICE_IBeacon(AL_IB_Key16)]) {
                //新版本固件Nordic验证key
                NSData *appkey = [self hexStrToNSData:MESHSDK_APPKEY];
                [self writeValue:appkey forCharacteristic:c type:CBCharacteristicWriteWithResponse];
                //                [self readValueForCharacteristic:c];
            }else if ([[self CBUUID2String:c.UUID] isEqualToString:AL_SERVICE_IBeacon(AL_IB_SerialData)]){
                [peripheral setNotifyValue:YES forCharacteristic:c];
            }
        }];
    }else if([[self CBUUID2String:service.UUID] isEqualToString:AL_SERVICE_DFU(0)]){
        self.dict_Service_DFU = [NSMutableDictionary dictionary];
        [service.characteristics enumerateObjectsUsingBlock:^(CBCharacteristic *c, NSUInteger idx, BOOL *stop) {
            [self.dict_Service_DFU setValue:c forKey:[self CBUUID2String:c.UUID]];
        }];
        [peripheral setNotifyValue:YES forCharacteristic:self.dict_Service_DFU[AL_SERVICE_DFU(AL_DFU_Ver4_Status4)]];
    }

    //for 050x Series
    if ([uuid isEqualToString:CB_SERVICE_IBeacon(0)]) {
        self.dict_Service_IB = [NSMutableDictionary dictionary];
        [service.characteristics enumerateObjectsUsingBlock:^(CBCharacteristic *c, NSUInteger idx, BOOL *stop) {
            [self.dict_Service_IB setValue:c forKey:[self CBUUID2String:c.UUID]];
        }];
        //验证key
        //00000000(1*8bit) x01+长度(1*8bit) 16位key(8*8bit)
        //const char buff[2] = {0x00,0x10};
        [peripheral setNotifyValue:YES forCharacteristic:self.dict_Service_IB[CB_SERVICE_IBeacon(CB_RData)]];
        [self sendBeaconValue:[self hexStrToNSData:[NSString stringWithFormat:@"0312%@",MESHSDK_APPKEY]] withCompletion:nil];
    }else{
        //连入成功，直接返回，加快连接速度，读取请参见self.readBeaconValuesCompletion
        void (^block) (void) = ^void () {
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(notifyConnectedState) object:nil];
            [self performSelector:@selector(notifyConnectedState) withObject:nil afterDelay:2];
        };
        if ([NSThread isMainThread]) {
            block();
        }else{
            dispatch_async(dispatch_get_main_queue(),block);
        }
    }
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    //    NSLog(@"%@_%@",characteristic.description,error.description);
    //本方法只是设置 开关回调，真正通知数值变化会走下面正常的回调。
}
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
//        [[[MESHBeaconSDK MESHBeaconManager] centralManager] cancelPeripheralConnection:peripheral];
        [[NSNotificationCenter defaultCenter] postNotificationName:kNotifyCancelConnect object:peripheral];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.connectBeaconCompletion) {
                self.connectBeaconCompletion(NO,error);
                self.connectBeaconCompletion = nil;
            }
        });
        return;
    }
    NSString *uuid = [self CBUUID2String:characteristic.UUID];
    if ([uuid isEqualToString:CB_SERVICE_IBeacon(CB_RData)]) {
        NSData *data = characteristic.value;
        if (data.length>=4) {
            NSString *strs = [self NSDataToHexString:data];
            NSInteger msgId = strtol([strs substringToIndex:2].UTF8String,0,16);
            NSData *value = [data subdataWithRange:NSMakeRange(2, data.length-2)];
            NSString *valueStr = [strs substringFromIndex:4];
            switch (msgId) {
                case 0x01:
                {
                    _hardwareVersion = [valueStr substringToIndex:4];
                    NSInteger firmversion = strtol([[valueStr substringWithRange:NSMakeRange(4, 4)] UTF8String],0,16);
                    _firmwareVersion = [NSString stringWithFormat:@"%ld",(long)firmversion];
                    break;
                }
                case 0x02:
                {
                    long tmp = 0;
                    [value getBytes:&tmp length:1];
                    self.temperature = [NSNumber numberWithLong:tmp];
                    [value getBytes:&tmp range:NSMakeRange(1, 1)];
                    self.battery = [NSNumber numberWithLong:tmp];
                    if(self.readBeaconChangesCompletion){
                        dispatch_async(dispatch_get_main_queue(), ^{
                            self.readBeaconChangesCompletion(@{@"battery":self.battery,@"temperature":self.temperature},error);
                            self.readBeaconChangesCompletion = nil;
                        });
                    }
                    break;
                }
                case 0x03:
                    //写入key通知
                    [self notifyConnectedState];
                    return;//防止调用返回。
                case 0x04:
                {
                    self.proximityUUID = [[NSUUID alloc] initWithUUIDBytes:value.bytes];
                    break;
                }
                case 0x05:
                    //批量设置UUID为最后一个写入成功回调
                    if (self.writeBeaconCompletion) {
                        self.writeBeaconCompletion(YES,nil);
                        self.writeBeaconCompletion = nil;
                    }
                    break;
                case 0x06:
                    //                case 0x07:
                {
                    self.major = [NSNumber numberWithUnsignedLong:strtoul([[valueStr substringWithRange:NSMakeRange(0, 4)] UTF8String],0,16)];
                    self.minor = [NSNumber numberWithUnsignedLong:strtoul([[valueStr substringWithRange:NSMakeRange(4, 4)] UTF8String],0,16)];
                    break;
                }
                case 0x08:
                    //                case 0x09:
                {
                    unsigned char buf[1];
                    [value getBytes:buf length:1];
                    int measured = buf[0];
                    self.measuredPower = [NSNumber numberWithShort:measured-(measured?256:0)];
                    break;
                }
                case 0x0A:
                    //                case 0x0B:
                {
                    unsigned char buf[1];
                    [value getBytes:buf length:1];
                    self.power = (int8_t)buf[0];
                    break;
                }
                case 0x0C:
                    //                case 0x0D:
                {
                    unsigned char buf[2];
                    [value getBytes:&buf length:2];
                    //[value getBytes:&_flag length:2];大小端不对
                    //OC是小端，而数据是大端
                    self.flag = (buf[0]<<8)|buf[1];
                    self.mode = buf[1]&0x1;

                    self.broadcastMode = 0;
                    self.broadcastMode |= ((buf[1]>>1)&0x07);
                    //                    self.broadcastMode |= ((buf[1]>>2)&0x1)<<1;
                    //                    self.broadcastMode |= (buf[1]>>3)&0x1;
                    self.isOff2402 = (buf[0]>>5)&0x1;
                    self.isOff2426 = (buf[0]>>6)&0x1;
                    self.isOff2480 = (buf[0]>>7)&0x1;
                    break;
                }
                case 0x0E:
                    //                case 0x0F:
                {
                    self.name = [MESHTools data2UTF8:value];
                    break;
                }
                case 0x10:
                    //                case 0x11:
                {
                    unsigned char buf[2];
                    [value getBytes:buf length:2];
                    self.advInterval = [NSNumber numberWithUnsignedShort:buf[0] << 8 | buf[1]];

                    [[value subdataWithRange:NSMakeRange(2, value.length-2)] getBytes:buf length:2];
                    self.broadcastInterval = [NSNumber numberWithUnsignedShort:buf[0] << 8 | buf[1]];
                    break;
                }
                case 0x12:
                    //                case 0x13:
                {
                    unsigned char buf[2];
                    [value getBytes:buf length:2];
                    self.batteryCheckInteval = buf[0] << 8 | buf[1];

                    [[value subdataWithRange:NSMakeRange(2, value.length-2)] getBytes:buf length:2];
                    self.temperatureCheckInteval = buf[0] << 8 | buf[1];
                    break;
                }
                case 0x14:
                    //                case 0x15:
                {
                    self.userData = [self NSDataToHexString:[value subdataWithRange:NSMakeRange(0, 4)]];
                    break;
                }
                case 0x16:
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if(self.readBeaconValuesCompletion)self.readBeaconValuesCompletion(self,nil);
                        self.readBeaconValuesCompletion = nil;
                    });
                    self.reserved = [self eddystone_Url_To:[self NSDataToHexString:value]];
                    break;
                }
                case 0x19:
                    //固件升级处理
                    [self.dict_DFU_Data removeObjectForKey:[valueStr substringWithRange:NSMakeRange(0, 4)]];
                    break;
                default:
                    break;
            }
        }
        if ([self.delegate respondsToSelector:@selector(beacon:didUpdateValue:error:)]) {
            [self.delegate beacon:self didUpdateValue:data error:error];
        }
        if(self.sendBeaconCompletion){
            self.sendBeaconCompletion(data,nil);
            self.sendBeaconCompletion = nil;
            //NSLog(@"本次结束:%@",characteristic.value);
        }

        return;
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Key)]||[uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_Key16)]) {
        //仅供找回1.0密码使用，2.0未成功屏蔽
        //                NSString *key = [self NSDataToHexString:characteristic.value];
        //                [[NSNotificationCenter defaultCenter] postNotificationName:@"key" object:key];
        //万能连接模式
        //        NSLog(@"%@",key);
        //        NSMutableData *mdata =[NSMutableData dataWithData:characteristic.value];
        //        if (![self isSupport:BleSupports16Key]) {
        //            [mdata appendData:[self hexStrToNSData:@"01"]];
        //        }
        //            [self writeValue:mdata forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
        //        if([MESHSDK_APPKEY isEqualToString:DEFAULT_KEY]){
        //            [self writeValue:characteristic.value forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
        //        }else{
        //            [self validateSDKKEY];
        //        }
    }
    if ([uuid isEqualToString:IB_SERVICE_UUID(IB_UUID)]) {
        self.proximityUUID = [[NSUUID alloc] initWithUUIDString:[self characteristicToProximityUUID:characteristic]];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Major)]) {
        unsigned short major = [self characteristicTwoByteToShort:characteristic];
        self.major = [NSNumber numberWithUnsignedShort:major];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Minor)]) {
        unsigned short minor = [self characteristicTwoByteToShort:characteristic];
        self.minor = [NSNumber numberWithUnsignedShort:minor];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_MPower)]) {
        int measured = [self characteristicOneByteToShort:characteristic];
        self.measuredPower = [NSNumber numberWithShort:measured-(measured?256:0)];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Interval)]) {
        unsigned short advertisingInterval = [self characteristicTwoByteToShort:characteristic];
        self.advInterval = [NSNumber numberWithUnsignedShort:advertisingInterval];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_TX)]) {
        self.power = [self characteristicOneByteToShort:characteristic];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Name)]) {
        self.name = [MESHTools data2UTF8:characteristic.value];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Battery)]) {
        //2.1~3.4v real battery range
        //1200~1900  read characteristic range
        long battery_orig = 0;//[self characteristicTwoByteToShort:characteristic];
        if (characteristic.value.length>1) {
            battery_orig = [self characteristicTwoByteToShort:characteristic];
        }else{
            battery_orig = [self characteristicOneByteToShort:characteristic];
        }
        if (battery_orig > 100) { //5版本以前固件的计算方式
            float maxV = 1900;
            float minV = 1200;
            battery_orig = battery_orig > maxV?maxV:battery_orig;
            battery_orig = battery_orig < minV?minV:battery_orig;
            self.battery = [NSNumber numberWithUnsignedShort:((battery_orig-minV)/(maxV-minV))*100];
        }
        else{
            battery_orig = battery_orig > 0?battery_orig:0;
            self.battery = [NSNumber numberWithLong:battery_orig];
        }
        if(self.readBeaconChangesCompletion){
            dispatch_async(dispatch_get_main_queue(), ^{
                if(self.dict_Service_IB[IB_SERVICE_UUID(IB_Light)])
                    self.readBeaconChangesCompletion(@{@"battery":self.battery,@"temperature":self.temperature?self.temperature:@"",@"light":[NSNumber numberWithLong:self.light]},error);
                else
                    self.readBeaconChangesCompletion(@{@"battery":self.battery,@"temperature":self.temperature},error);
                self.readBeaconChangesCompletion = nil;
            });
        }
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Temperature)]) {
        short temperature = 0;
        if (characteristic.value.length>1) {
            temperature = [self characteristicTwoByteToShort:characteristic];
        }else{
            temperature = [self characteristicOneByteToShort:characteristic];
        }
        //        NSLog(@"temperature:%d",temperature);
        //temperature = 160 * (temperature / 100.0) - 40;
        if (temperature>=-40&&temperature<=100) {
            self.temperature = [NSNumber numberWithShort:temperature];
        }else{
            self.temperature = @127;
            temperature = 127;
            error = [NSError errorWithDomain:NSLocalizedString(@"无法获取温度",nil) code:ErrorCode104 userInfo:nil];
        }
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_DEVPUB)]) {
        self.mode = [self characteristicOneByteToShort:characteristic];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Battery_Interval)]) {
        self.batteryCheckInteval = [self characteristicFourByteToInteger:characteristic];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Temperature_Interval)]) {
        self.temperatureCheckInteval = [self characteristicFourByteToInteger:characteristic];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Light)]) {
        if([self isSupport:BleSupportsLight])self.light = [self characteristicTwoByteToShort:characteristic];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Light_Sleep)]) {
        if([self isSupport:BleSupportsLight])self.lightSleep = [self characteristicOneByteToShort:characteristic];
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Light_Interval)]) {
        self.lightCheckInteval = [self characteristicFourByteToInteger:characteristic];
    }else if ([uuid isEqualToString:IB_SERVICE_DFU(IB_DFU_Notify)]) {
        if (self.imgVersion == 0xFFFF) {
            NSUInteger len = characteristic.value.length;
            unsigned char data[len];
            [characteristic.value getBytes:&data length:len];
            self.imgVersion = ((uint16_t)data[1] << 8 & 0xff00) | ((uint16_t)data[0] & 0xff);
        }
    }else if([uuid isEqualToString:IB_SERVICE_DFU(IB_DFU_Firmware)]){
        [self characteristicToVersion:characteristic];
        if(self.readDFUCompletion){
            dispatch_async(dispatch_get_main_queue(), ^{
                self.readDFUCompletion([NSString stringWithFormat:@"%@-%@",self.hardwareVersion,self.firmwareVersion],nil);
                self.readDFUCompletion = nil;
            });
        }
    }else if ([uuid isEqualToString:IB_SERVICE_UUID(IB_Light_Sleep)]){
        self.lightSleep = [self characteristicOneByteToShort:characteristic];
    }
    //for anti-lose
    else if ([uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_UUID16_Major2_Minor2)]) {
        NSString *UMM = [self NSDataToHexString:characteristic.value];
        if (UMM.length>=40) {
            NSRange r1 = NSMakeRange(8, 4);
            NSRange r2 = NSMakeRange(12, 4);
            NSRange r3 = NSMakeRange(16, 4);
            NSRange r4 = NSMakeRange(20, 12);
            NSRange r5 = NSMakeRange(32, 4);
            NSRange r6 = NSMakeRange(36, 4);
            NSString *UUID = [NSString stringWithFormat:@"%@-%@-%@-%@-%@",[UMM substringToIndex:8],[UMM substringWithRange:r1],[UMM substringWithRange:r2],[UMM substringWithRange:r3],[UMM substringWithRange:r4]];
            self.proximityUUID = [[NSUUID alloc] initWithUUIDString:UUID];
            self.major = [NSNumber numberWithUnsignedLong:strtoul([[UMM substringWithRange:r5] UTF8String],0,16)];
            self.minor = [NSNumber numberWithUnsignedLong:strtoul([[UMM substringWithRange:r6] UTF8String],0,16)];
        }
    }else if([uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_Name20)]){
        //        NSString *name = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
        self.name = [MESHTools data2UTF8:characteristic.value];
    }else if([uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_Battery1_Temperature1)]){
        long tmp = 0;
        [characteristic.value getBytes:&tmp length:1];
        self.battery = [NSNumber numberWithLong:tmp];
        [characteristic.value getBytes:&tmp range:NSMakeRange(1, 1)];
        self.temperature = [NSNumber numberWithLong:tmp];
        if(self.readBeaconChangesCompletion){
            dispatch_async(dispatch_get_main_queue(), ^{
                self.readBeaconChangesCompletion(@{@"battery":self.battery,@"temperature":self.temperature},error);
                self.readBeaconChangesCompletion = nil;
            });
        }
    }else if([uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_Mode2_Tx1_MPower1_Interval2_BateryInterval2_TempInterval2)]){
        unsigned char data[2];
        [characteristic.value getBytes:&data length:2];
        self.flag = (data[0]<<8)|data[1];
        self.mode = data[1]&0x1;
        //for 0307
        if ([self isSupport:BleSupportsAli]) {
            self.lightSleep = (data[1]>>1)&0x1;

            self.broadcastMode = 0;
            self.broadcastMode |= ((data[1]>>2)&0x1)<<2;
            self.broadcastMode |= ((data[1]>>3)&0x1)<<1;
            self.broadcastMode |= (data[1]>>4)&0x1;
        }

        if ([self isSupport:BleSupportsAdvRFOff]){
            self.isOff2402 = (data[0]>>4)&0x1;
            self.isOff2426 = (data[0]>>5)&0x1;
            self.isOff2480 = (data[0]>>6)&0x1;
        }

        NSString *value = [self NSDataToHexString:characteristic.value];
        if(value.length>=24){
            self.power = strtol([[value substringWithRange:NSMakeRange(4, 2)] UTF8String], 0, 16);
            self.measuredPower = [NSNumber numberWithLong:strtol([[value substringWithRange:NSMakeRange(6, 2)] UTF8String], 0, 16)-256];
            self.advInterval = [NSNumber numberWithLong:strtol([[value substringWithRange:NSMakeRange(8, 4)] UTF8String], 0, 16)];
            self.batteryCheckInteval = strtol([[value substringWithRange:NSMakeRange(12, 4)] UTF8String], 0, 16);
            self.temperatureCheckInteval = strtol([[value substringWithRange:NSMakeRange(16, 4)] UTF8String], 0, 16);
            if ([self isSupport:BleSupportsEddystone]){
                self.lightCheckInteval = strtol([[value substringWithRange:NSMakeRange(20, 4)] UTF8String], 0, 16);
            }
            if (value.length>=36) {
                self.userData = [value substringWithRange:NSMakeRange(28, 8)];
            }
        }

    }else if([uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_Reserved20)]){
        self.reserved = [self NSDataToHexString:characteristic.value];
        if([self isSupport:BleSupportsEddystone]){
            NSData *data = characteristic.value;
            self.reserved = [self eddystone_Url_To:[self NSDataToHexString:data]];
            if (data.length>=16&&!self.reserved) {
                self.reserved  = [self characteristicToProximityUUID:characteristic];
            }
        }
    }else if([uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_SerialData)]){
        //新增串口数据
        self.serialData = [self NSDataToHexString:characteristic.value];
    }else if([uuid isEqualToString:AL_SERVICE_DFU(AL_DFU_Ver4_Status4)]){
        if(self.readDFUCompletion){
            NSString *value = [self NSDataToHexString:characteristic.value];
            if(value.length>=8){
                self.hardwareVersion = [value substringWithRange:NSMakeRange(0, 4)];
                self.firmwareVersion = [NSString stringWithFormat:@"%lu",strtol([[value substringWithRange:NSMakeRange(4, 4)] UTF8String], 0, 16)];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.readDFUCompletion([NSString stringWithFormat:@"%@-%@",self.hardwareVersion,self.firmwareVersion],error);
                self.readDFUCompletion = nil;
            });
        }else{
            NSString *value = [self NSDataToHexString:characteristic.value];
            if(value&&(value.length>12)){
                [self.dict_DFU_Data removeObjectForKey:[value substringWithRange:NSMakeRange(8, 4)]];
            }
        }
    }else if([uuid isEqualToString:AL_SERVICE_DFU(AL_DFU_Data20)]){
        //
    }
    if ([self.dict_Service_IB.allKeys containsObject:uuid]){
        //2015.12.11修改为循环读取所有特征，必定==
        if (++readedCharacteristicCount == self.dict_Service_IB.allKeys.count) {
            //获取所有参数完成
            if (self.readBeaconValuesCompletion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.readBeaconValuesCompletion(self,nil);
                });
            }
        }
        //更新一下value
        [self.dict_Service_IB setValue:characteristic forKey:uuid];
    }else if ([self.dict_Service_DFU.allKeys containsObject:uuid]){
        [self.dict_Service_DFU setValue:characteristic forKey:uuid];
    }
}
- (void)notifyConnectedState{
    //连接成功，就更新一次服务端数据。连接失败，别更新appkey
    if([self isConnected])[self uploadBeaconValues:nil];
    //notify develeper
    if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconConnection:withError:)]) {
        [self.delegate beaconConnection:self withError:nil];
    }

    void (^block) (void) = ^void () {
        //如果连接已经断开，防止调用该回调。
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(notifyConnectedState) object:nil];
        if (self.connectBeaconCompletion) {
            self.connectBeaconCompletion([self isConnected],nil);
            self.connectBeaconCompletion = nil;
        }
    };
    if ([NSThread isMainThread]) {
        block();
    }else{
        dispatch_async(dispatch_get_main_queue(),block);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSString *uuid = [self CBUUID2String:characteristic.UUID];
    [self.dict_Service_IB setValue:characteristic forKey:uuid];
    if ([uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_Key16)]||[uuid isEqualToString:IB_SERVICE_UUID(IB_Key)]) {
        //Error Domain=CBATTErrorDomain Code=2 "Reading is not permitted."
        /*isValidate = error?2:1;
         if (isValidate==2) {
         [self notifyConnectedState];
         }*/
    }
    else if ([uuid isEqualToString:AL_SERVICE_IBeacon(AL_IB_Mode2_Tx1_MPower1_Interval2_BateryInterval2_TempInterval2)]||[uuid isEqualToString:IB_SERVICE_UUID(IB_UUID)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.writeBeaconCompletion?self.writeBeaconCompletion(YES,error):nil;
            self.writeBeaconCompletion = nil;
        });
    }else if ([uuid isEqualToString:IB_SERVICE_DFU(IB_DFU_Notify)]) {
        //        老固件升级，移除新固件特征判断，防止意外报错||[uuid isEqualToString:AL_SERVICE_DFU(AL_DFU_Data20)]
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [NSThread sleepForTimeInterval:5];
            [self programmingTimerTick];
        });

    }else if ([uuid isEqualToString:IB_SERVICE_DFU(IB_DFU_BLOCK)]) {
        NSLog(@"A error:%@",[error description]);
    }else if(error){
        NSLog(@"B error:%@",[error description]);
    }
}

#pragma disconnect
- (void)beaconDidDisconnect:(NSNotification*)notify
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeOutForConnect) object:nil];

        if (notify.object == self.peripheral) {
            //            NSError *error = [notify.userInfo valueForKey:@"error"];
            //            if ([error isKindOfClass:[NSError class]]&&error.code==10) {
            //                //循环了。。error.code==7 CBErrorDomain
            //                [self connectToBeacon];
            //            }else{
            [[NSNotificationCenter defaultCenter] removeObserver:self name:kNotifyDisconnect object:nil];
            _isConnected = NO;
            if (self.delegate && [(NSObject *)self.delegate respondsToSelector:@selector(beaconDidDisconnect:withError:)]) {
                [self.delegate beaconDidDisconnect:self withError:notify?notify.userInfo[@"error"]:[NSError errorWithDomain:NSLocalizedString(@"未识别的设备，无法连入",nil) code:ErrorCode101 userInfo:nil]];
            }
            if (self.connectBeaconCompletion) {
                self.connectBeaconCompletion(NO,notify?notify.userInfo[@"error"]:[NSError errorWithDomain:NSLocalizedString(@"未识别的设备，无法连入",nil) code:ErrorCode101 userInfo:nil]);
                self.connectBeaconCompletion = nil;
            }
            //            }
        }
    });
}

//OAD
//CB批量升级有误，延迟.005测试
#define OAD_PACKET_TX_DELAY 0.025
uint16_t crc16_compute(const uint8_t * p_data, uint32_t size, const uint16_t * p_crc)
{
    uint32_t i;
    uint16_t crc = (p_crc == NULL) ? 0xffff : *p_crc;

    for (i = 0; i < size; i++)
    {
        crc  = (unsigned char)(crc >> 8) | (crc << 8);
        crc ^= p_data[i];
        crc ^= (unsigned char)(crc & 0xff) >> 4;
        crc ^= (crc << 8) << 4;
        crc ^= ((crc & 0xff) << 4) << 1;
    }

    return crc;
}
- (void)uploadImage{
    self.dict_DFU_Data = [NSMutableDictionary dictionary];
    self.canceled = NO;
    self.iBlocks = 0;
    self.iBytes = 0;
    self.inProgramming = YES;
    unsigned char imageFileData[self.imageFile.length];
    [self.imageFile getBytes:imageFileData length:self.imageFile.length];
    //    uint8_t requestData[OAD_IMG_HDR_SIZE+2+2]; // 12Bytes
    uint8_t requestData[20]= {0}; // 20Bytes

    img_hdr_t imgHeader;
    memcpy(&imgHeader, &imageFileData[0 + OAD_IMG_HDR_OSET], sizeof(img_hdr_t));
    if ([self isSupport:BleSupportsExtension]) {
        NSInteger len = self.imageFile.length;
        uint16_t crc16 = 0;
        crc16 = crc16_compute(imageFileData, (uint32_t)len, &crc16);
        //        crc16 = crc16_compute(requestData, 16 - len%16, &crc16);
        requestData[0] = 0x1;
        NSInteger ver = self.firmwareVersion.integerValue;
        requestData[1] = (ver>>8)&0xff;
        requestData[2] = (ver>>0)&0xff;
        requestData[3] = (crc16>>8)&0xff;
        requestData[4] = (crc16>>0)&0xff;

        requestData[5] = (len>>24)&0xff;
        requestData[6] = (len>>16)&0xff;
        requestData[7] = (len>>8)&0xff;
        requestData[8] = (len>>0)&0xff;
        NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"180B"]];
        [mdata appendBytes:requestData length:9];
        [self writeValue:mdata forCharacteristic:self.dict_Service_IB[CB_SERVICE_IBeacon(CB_RWData)] type:CBCharacteristicWriteWithoutResponse];
        //余数进一法
        self.nBlocks = (self.imageFile.length+OAD_BLOCK_SIZE-1)/OAD_BLOCK_SIZE;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [NSThread sleepForTimeInterval:5];
            [self programmingTimerTick];
        });
    }else if([self isSupport:BleSupportsAntiLose]||[self isSupport:BleSupportsNordic|BleSupportsAli]){
        requestData[0] = 0x0;
        requestData[1] = 0x0;
        requestData[2] = 0x0;
        requestData[3] = 0x0;
        requestData[4] = 0x0;
        requestData[5] = 0x0;
        NSInteger len = self.imageFile.length;
        requestData[6] = (len>>24)&0xff;
        requestData[7] = (len>>16)&0xff;
        requestData[8] = (len>>8)&0xff;
        requestData[9] = (len>>0)&0xff;

        NSData *data = [NSData dataWithBytes:requestData length:20];
        [self writeValue:data forCharacteristic:self.dict_Service_DFU[AL_SERVICE_DFU(AL_DFU_Data20)] type:CBCharacteristicWriteWithoutResponse];
        //余数进一法
        self.nBlocks = (self.imageFile.length+OAD_BLOCK_SIZE-1)/OAD_BLOCK_SIZE;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [NSThread sleepForTimeInterval:5];
            [self programmingTimerTick];
        });
    }else if ([self isSupport:BleSupportsNordic]) {
        requestData[0] = HI_UINT16(0);
        requestData[1] = LO_UINT16(0);
        requestData[2] = HI_UINT16(self.imageFile.length);
        requestData[3] = LO_UINT16(self.imageFile.length);
        memcpy(requestData + 4, &imgHeader.uid, sizeof(imgHeader.uid));
        [self writeValue:[NSData dataWithBytes:requestData length:OAD_IMG_HDR_SIZE] forCharacteristic:self.dict_Service_DFU[IB_SERVICE_DFU(IB_DFU_Notify)] type:CBCharacteristicWriteWithResponse];
        //余数进一法
        self.nBlocks = (self.imageFile.length+OAD_BLOCK_SIZE-1)/OAD_BLOCK_SIZE;
    }else if([self isSupport:BleSupportsCC254x]){
        //        NSInteger len = (self.imageFile.length+3)/4;
        requestData[0] = LO_UINT16(imgHeader.ver);
        requestData[1] = HI_UINT16(imgHeader.ver);
        requestData[2] = LO_UINT16(imgHeader.len);
        requestData[3] = HI_UINT16(imgHeader.len);
        memcpy(requestData + 4, &imgHeader.uid, sizeof(imgHeader.uid));

        requestData[OAD_IMG_HDR_SIZE + 0] = LO_UINT16(12);
        requestData[OAD_IMG_HDR_SIZE + 1] = HI_UINT16(12);

        requestData[OAD_IMG_HDR_SIZE + 2] = LO_UINT16(15);
        requestData[OAD_IMG_HDR_SIZE + 3] = HI_UINT16(15);

        [self writeValue:[NSData dataWithBytes:requestData length:(OAD_IMG_HDR_SIZE + 2 + 2)] forCharacteristic:self.dict_Service_DFU[IB_SERVICE_DFU(IB_DFU_Notify)] type:CBCharacteristicWriteWithResponse];

        self.nBlocks = imgHeader.len / (OAD_BLOCK_SIZE / HAL_FLASH_WORD_SIZE);
    }
}

- (void)programmingTimerTick{
    NSUInteger len = self.imageFile.length;
    unsigned char imageFileData[len];
    [self.imageFile getBytes:imageFileData length:len];

    //Prepare Block
    uint8_t requestData[2 + OAD_BLOCK_SIZE + 2] = {0};

    // This block is run 4 times, this is needed to get CoreBluetooth to send consequetive packets in the same connection interval.
    //    NSLog(@"%@,开始写人",self.macAddress);
    //    NSMutableData *mdata = [NSMutableData data];
    for (self.iBlocks=0; self.iBlocks<self.nBlocks; self.iBlocks++) {

        if (self.canceled) {
            self.canceled = FALSE;
            if (self.updateBeaconFirmwareCompletion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.updateBeaconFirmwareCompletion(NO,[NSError errorWithDomain:NSLocalizedString(@"更新中断",nil) code:ErrorCode109 userInfo:nil]);
                });
            }
            return;
        }
        //
        if(![self isConnecting]){
            if (self.updateBeaconFirmwareCompletion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.updateBeaconFirmwareCompletion(NO,[NSError errorWithDomain:NSLocalizedString(@"连接已断开",nil) code:ErrorCodeUnKnown userInfo:nil]);
                });
            }
            return;
        }
        unsigned long block_size = OAD_BLOCK_SIZE;
        if (self.iBlocks+1 == self.nBlocks) {
            block_size = (self.imageFile.length%OAD_BLOCK_SIZE)?:OAD_BLOCK_SIZE;
        }
        if ([self isSupport:BleSupportsExtension]) {
            requestData[0] = HI_UINT16(self.iBytes);
            requestData[1] = LO_UINT16(self.iBytes);
            memcpy(&requestData[2] , &imageFileData[self.iBytes], block_size);
            NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"1914"]];
            [mdata appendBytes:requestData length:2+OAD_BLOCK_SIZE];
            [self.dict_DFU_Data setValue:mdata forKey:[NSString stringWithFormat:@"%04lx",(long)self.iBlocks*16]];
            [self writeValue:mdata forCharacteristic:self.dict_Service_IB[CB_SERVICE_IBeacon(CB_RWData)] type:CBCharacteristicWriteWithoutResponse];
        }else if([self isSupport:BleSupportsAli|BleSupportsNordic]||[self isSupport:BleSupportsAntiLose]){
            requestData[0] = HI_UINT16(self.iBlocks+1);
            requestData[1] = LO_UINT16(self.iBlocks+1);
            requestData[2] = HI_UINT16(self.nBlocks);
            requestData[3] = LO_UINT16(self.nBlocks);
            memcpy(&requestData[4] , &imageFileData[self.iBytes], block_size);
            NSData *data = [NSData dataWithBytes:requestData length:(2 + OAD_BLOCK_SIZE +2)];
            [self writeValue:data forCharacteristic:self.dict_Service_DFU[AL_SERVICE_DFU(AL_DFU_Data20)] type:CBCharacteristicWriteWithoutResponse];
            //04之后，所有升级数据将不会立即通知，只当最后结束才通知一次。
            //[self.dict_DFU_Data setValue:data forKey:[NSString stringWithFormat:@"%04lx",(long)self.iBlocks+1]];
        }else{
            requestData[0] = LO_UINT16(self.iBlocks);
            requestData[1] = HI_UINT16(self.iBlocks);
            memcpy(&requestData[2] , &imageFileData[self.iBytes], block_size);
            [self writeValue:[NSData dataWithBytes:requestData length:(2 + OAD_BLOCK_SIZE)] forCharacteristic:self.dict_Service_DFU[IB_SERVICE_DFU(IB_DFU_BLOCK)] type:CBCharacteristicWriteWithoutResponse];
        }

        self.iBytes += OAD_BLOCK_SIZE;
        float percentageLeft = (float)((float)self.iBlocks / (float)self.nBlocks);
        NSNumber * percentage = [NSNumber numberWithFloat:percentageLeft];

        if (self.updateBeaconFirmwareProgress) {
            self.inProgramming = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.updateBeaconFirmwareProgress(@(percentage.floatValue * 100),nil);
            });
        }
        if ([self isSupport:BleSupportsSerialData]) {
            [NSThread sleepForTimeInterval:OAD_PACKET_TX_DELAY];
        }else{
            [NSThread sleepForTimeInterval:OAD_PACKET_TX_DELAY];
        }
    }
    //    NSLog(@"%d(%d)",self.nBlocks,self.iBlocks);
    if(self.iBlocks == self.nBlocks) {//update complete
        //self.inProgramming = NO;
        //延迟2s，等待通知结束，如果检查是否有为写完的数据包
        [NSThread sleepForTimeInterval:2];
        [self checkFirmware];
    }
}

- (void)checkFirmware {
    NSLog(@"lost:%@",[self.dict_DFU_Data.allKeys componentsJoinedByString:@","]);

    //只有0304才写入了dict_DFU_Data,1.x,2.x直接为空可以通过
    if (self.dict_DFU_Data.allKeys.count < 1) {
        if ([self isSupport:BleSupportsExtension]) {
            //发送结束符，并重启
            [self sendBeaconValue:[self hexStrToNSData:@"181800"] withCompletion:nil];
            [self sendBeaconValue:[self hexStrToNSData:@"0000"] withCompletion:nil];
        }
        if (self.updateBeaconFirmwareCompletion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.updateBeaconFirmwareCompletion(YES,nil);
            });
        }
    }else{
        if ([self isSupport:BleSupportsExtension]) {
            NSArray *allkeys = self.dict_DFU_Data.allKeys;
            for (NSString *key in allkeys) {
                [self sendBeaconValue:self.dict_DFU_Data[key] withCompletion:nil];
                [NSThread sleepForTimeInterval:OAD_PACKET_TX_DELAY];
            }
            [NSThread sleepForTimeInterval:5];
            //发送结束符，并重启
            [self sendBeaconValue:[self hexStrToNSData:@"181800"] withCompletion:nil];
            [self sendBeaconValue:[self hexStrToNSData:@"0000"] withCompletion:nil];
        }
        if (self.updateBeaconFirmwareCompletion) {
            BOOL flag = !!self.dict_DFU_Data.allKeys.count;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.updateBeaconFirmwareCompletion(!flag,flag?[NSError errorWithDomain:NSLocalizedString(@"固件升级失败",nil) code:ErrorCode108 userInfo:nil]:nil);
            });
        }
    }
}
#pragma mark - Beacon
- (void)readBeaconChangesWithCompletion:(MESHDataCompletionBlock)completion
{
    if(![self isConnecting]){
        completion?completion(nil,[NSError errorWithDomain:NSLocalizedString(@"设备连接已断开",nil) code:ErrorCodeUnKnown userInfo:nil]):nil;
        return;
    }
    self.readBeaconChangesCompletion = completion;
    if ([self isSupport:BleSupportsExtension]) {
        /*NSMutableData *mdata = [NSMutableData dataWithData:[self hexStrToNSData:@"1313"]];
         NSData *data = [self NumberToNSData:@"1" withSize:2];
         [mdata appendData:data];
         data = [self NumberToNSData:@"1" withSize:2];
         [mdata appendData:data];
         //设置间隔1s
         [self sendBeaconValue:mdata withCompletion:nil];
         [NSThread sleepForTimeInterval:1.2];*/
        //读取温度电量
        [self sendBeaconValue:[self hexStrToNSData:@"0202"] withCompletion:nil];
        //        completion?completion(@{@"battery":self.battery?:@"",@"temperature":self.temperature?:@""},nil):nil;

    }else if ([self isSupport:BleSupportsCombineCharacteristic]) {
        [self readValueForCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_Battery1_Temperature1)]];
        //        [self readValueForCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_SerialData)]];//notify会自动调用。
    }else{
        [self readValueForCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Light)]];
        [self readValueForCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Temperature)]];
        [self readValueForCharacteristic:self.dict_Service_IB[IB_SERVICE_UUID(IB_Battery)]];
    }
}
#pragma mark - Anti-Lose
- (void)readALButtonAlarmCompletion:(MESHCompletionBlock)completion{
    self.readALButtonAlarmCompletion = completion;
    [self readValueForCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_Mode2_Tx1_MPower1_Interval2_BateryInterval2_TempInterval2)]];
}

- (void)readALDFUCompletion:(MESHDataCompletionBlock)completion{
    if(completion)self.readDFUCompletion = completion;
    [self readValueForCharacteristic:self.dict_Service_DFU[AL_SERVICE_DFU(AL_DFU_Ver4_Status4)]];
    [self readValueForCharacteristic:self.dict_Service_DFU[AL_SERVICE_DFU(AL_DFU_Data20)]];
}
//注意事项：data写入过长，会保存失败，不会来写成功回调
- (void)writeALIBeaconValues:(NSDictionary *)values withCompletion:(MESHCompletionBlock)completion{
    self.writeBeaconCompletion = completion;
    NSString *name = values[B_NAME];
    if(name&&![name isEqualToString:self.name]){
        NSData *data = [name dataUsingEncoding:NSUTF8StringEncoding];
        NSInteger limit = [self isSupport:BleSupportsNordic]?20:16;
        NSInteger count = name.length;
        while (data.length > limit) {
            data = [[name substringToIndex:--count] dataUsingEncoding:NSUTF8StringEncoding];
        }
        [self writeValue:data forCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_Name20)] type:CBCharacteristicWriteWithResponse];
        [NSThread sleepForTimeInterval:.1];
    }
    if (values[B_SerialData]&&[self isSupport:BleSupportsSerialData]&&![values[B_SerialData] isEqualToString:self.serialData]) {
        int len = (int)[values[B_SerialData] length];
        NSData *data = [self hexStrToNSData:values[B_SerialData] withSize:len];
        [self writeValue:data forCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_SerialData)] type:CBCharacteristicWriteWithResponse];
        [NSThread sleepForTimeInterval:.1];
    }
    if(values[B_Reserved]){
        NSString *uuidRegex = @"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";
        NSPredicate *uuidTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", uuidRegex];
        NSString * reserved= values[B_Reserved];
        if([uuidTest evaluateWithObject:reserved]&&![reserved isEqualToString:self.reserved]){
            CBUUID *puuid = [CBUUID UUIDWithString:reserved];
            NSMutableData *mdata =[NSMutableData dataWithData:puuid.data];
            [mdata appendData:[self hexStrToNSData:@"00" withSize:20]];
            [self writeValue:[mdata subdataWithRange:NSMakeRange(0, 20)] forCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_Reserved20)] type:CBCharacteristicWriteWithResponse];
            [NSThread sleepForTimeInterval:.1];
        }else if(reserved.length){
            NSMutableData *mdata = [NSMutableData data];
            NSRange range;
            NSArray *array = @[@"http://www.",@"https://www.",@"http://",@"https://"];
            for (NSString *str in array) {
                range = [reserved rangeOfString:str];
                if (range.location==0) {
                    reserved = [reserved substringFromIndex:str.length];
                    [mdata appendData:[self hexStrToNSData:[NSString stringWithFormat:@"%2ld",(long)[array indexOfObject:str]]]];
                    break;
                }
            }
            array = @[@".com/",@".org/",@".edu/",@".net/",@".info/",@".biz/",@".gov/",@".com",@".org",@".edu",@".net",@".info",@".biz",@".gov"];
            NSData *data = [reserved dataUsingEncoding:NSUTF8StringEncoding];
            NSString *hexStr = [self NSDataToHexString:data];
            for (NSString *str in array) {
                NSString *hex = [self NSDataToHexString:[str dataUsingEncoding:NSUTF8StringEncoding]];
                hexStr = [hexStr stringByReplacingOccurrencesOfString:hex withString:[NSString stringWithFormat:@"%02lx",(unsigned long)[array indexOfObject:str]]];
            }
            [mdata appendData:[self hexStrToNSData:hexStr]];
            //超过限制会无法保存回调。
            //            [mdata appendData:[self hexStrToNSData:@"00" withSize:20]];
            if (mdata.length>18) {
                if(completion)completion(NO,[NSError errorWithDomain:[NSString stringWithFormat:NSLocalizedString(@"Eddystone URL超出(%lu)个字符",nil),(unsigned long)mdata.length-18] code:CBErrorCode1 userInfo:nil]);
                self.writeBeaconCompletion = nil;
                return;
            }
            [self writeValue:mdata forCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_Reserved20)] type:CBCharacteristicWriteWithResponse];
            [NSThread sleepForTimeInterval:.1];
        }
    }
    NSMutableDictionary *mdict = [NSMutableDictionary dictionary];
    [mdict setNoNilValue:values[B_UUID] def:self.proximityUUID.UUIDString forKey:B_UUID];
    [mdict setNoNilValue:values[B_MAJOR] def:[self.major stringValue] forKey:B_MAJOR];
    [mdict setNoNilValue:values[B_MINOR] def:[self.minor stringValue] forKey:B_MINOR];
    [mdict setNoNilValue:values[B_MODE] def:I2S(self.mode) forKey:B_MODE];

    [mdict setNoNilValue:values[B_TX] def:L2S(self.power) forKey:B_TX];
    [mdict setNoNilValue:values[B_MPOWER] def:[self.measuredPower stringValue] forKey:B_MPOWER];
    [mdict setNoNilValue:values[B_INTERVAL] def:[self.advInterval stringValue] forKey:B_INTERVAL];
    [mdict setNoNilValue:values[B_BATTERY_INTERVAL] def:L2S(self.batteryCheckInteval) forKey:B_BATTERY_INTERVAL];
    [mdict setNoNilValue:values[B_TEMPERATURE_INTERVAL] def:L2S(self.temperatureCheckInteval) forKey:B_TEMPERATURE_INTERVAL];

    //for new
    [mdict setNoNilValue:values[B_UserData] def:_userData forKey:B_UserData];
    //for 0313
    [mdict setNoNilValue:values[B_Off2402] def:I2S(_isOff2402) forKey:B_Off2402];
    [mdict setNoNilValue:values[B_Off2426] def:I2S(_isOff2426) forKey:B_Off2426];
    [mdict setNoNilValue:values[B_Off2480] def:I2S(_isOff2480) forKey:B_Off2480];

    uint8_t buf[2] = {0x00};

    buf[1] |=  [mdict[B_MODE] boolValue]?0x1:0x0;
    //for 0307  第2位是光感休眠开关
    if([self isSupport:BleSupportsAli]){
        [mdict setNoNilValue:values[B_LIGHT_INTERVAL] def:nil forKey:B_LIGHT_INTERVAL];
        [mdict setNoNilValue:values[B_LIGHT_SLEEP] def:I2S(self.lightSleep) forKey:B_LIGHT_SLEEP];
        [mdict setNoNilValue:values[B_BroadcastMode] def:I2S(self.broadcastMode) forKey:B_BroadcastMode];
        BroadcastMode bMode = (BroadcastMode)[mdict[B_BroadcastMode] integerValue];
        buf[1] |=  ([mdict[B_LIGHT_SLEEP] boolValue]?0x1:0x0)<<1;
        buf[1] |=  (bMode>>2&0x1)<<2;
        buf[1] |=  (bMode>>1&0x1)<<3;
        buf[1] |=  (bMode&0x1)<<4;

        buf[1] |= self.flag&0x10;//还原5~7位
        buf[1] |= self.flag&0x20;
        buf[1] |= self.flag&0x40;
    }
    buf[0] |= self.flag&0x01;
    buf[0] |= self.flag&0x02;
    buf[0] |= self.flag&0x04;
    buf[0] |= self.flag&0x08;

    if ([self isSupport:BleSupportsAdvRFOff]) {
        buf[0] |=  ([mdict[B_Off2402] boolValue]?0x1:0x0)<<4;
        buf[0] |=  ([mdict[B_Off2426] boolValue]?0x1:0x0)<<5;
        buf[0] |=  ([mdict[B_Off2480] boolValue]?0x1:0x0)<<6;

        buf[0] |= self.flag&0x80;
    }else{
        buf[0] |=  ([mdict[B_InRange] boolValue]?0x1:0x0)<<4;
        buf[0] |=  ([mdict[B_AutoAlarm] boolValue]?0x1:0x0)<<5;
        buf[0] |=  ([mdict[B_ActiveFind] boolValue]?0x1:0x0)<<6;
        buf[0] |=  ([mdict[B_ButtonAlarm] boolValue]?0x1:0x0)<<7;
    }
    //7       0 7       0
    //0011 0000 0001 1100

    NSMutableData *mdata = [NSMutableData dataWithBytes:buf length:2];
    if(mdict[B_TX])[mdata appendData:[self NumberToNSData:mdict[B_TX] withSize:1]];
    if(mdict[B_MPOWER])[mdata appendData:[self NumberToNSData:[NSString stringWithFormat:@"%ld",(long)[mdict[B_MPOWER] integerValue]+256] withSize:1]];
    if(mdict[B_INTERVAL])[mdata appendData:[self NumberToNSData:mdict[B_INTERVAL] withSize:2]];
    if(mdict[B_BATTERY_INTERVAL])[mdata appendData:[self NumberToNSData:mdict[B_BATTERY_INTERVAL] withSize:2]];
    [mdata appendData:[self NumberToNSData:mdict[B_TEMPERATURE_INTERVAL] withSize:2]];
    if ([self isSupport:BleSupportsAli]) {
        [mdata appendData:[self NumberToNSData:[mdict valueForKey:B_LIGHT_INTERVAL] withSize:2]];
        [mdata appendData:[self NumberToNSData:@"1" withSize:2]];//广播切换间隔
        int len = MIN(8, (int)[[mdict valueForKey:B_UserData] length]);//最多8个字符(4byte)
        [mdata appendData:[self hexStrToNSData:[mdict valueForKey:B_UserData] withSize:MIN(4, (len+1)/2)]];//2015.12.11 0401\0402 自定义字段
        [mdata appendData:[self NumberToNSData:@"0" withSize:2+(8-len)/2]];//未用，补齐全0
    }else{
        [mdata appendData:[self NumberToNSData:[mdict valueForKey:B_AutoAlarmTimeOut] withSize:2]];
        [mdata appendData:[self NumberToNSData:@"0" withSize:8]];
    }

    [self writeValue:mdata forCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_Mode2_Tx1_MPower1_Interval2_BateryInterval2_TempInterval2)] type:CBCharacteristicWriteWithResponse];
    [NSThread sleepForTimeInterval:.1];

    if ([mdict[B_UUID] isEqualToString:self.proximityUUID.UUIDString]&&[mdict[B_MAJOR] integerValue]==self.major.integerValue&&[mdict[B_MINOR] integerValue]==self.minor.integerValue){/*do nothing*/}else {
        CBUUID *puuid = [CBUUID UUIDWithString:mdict[B_UUID]];
        NSMutableData *mdata = [NSMutableData dataWithData:puuid.data];
        [mdata appendData:[self NumberToNSData:mdict[B_MAJOR] withSize:2]];
        [mdata appendData:[self NumberToNSData:mdict[B_MINOR] withSize:2]];
        [self writeValue:mdata forCharacteristic:self.dict_Service_IB[AL_SERVICE_IBeacon(AL_IB_UUID16_Major2_Minor2)] type:CBCharacteristicWriteWithResponse];
        self.proximityUUID = [[NSUUID alloc] initWithUUIDString:mdict[B_UUID]];
    }
    [NSThread sleepForTimeInterval:.1];
}

#pragma mark - **************** readIBeacon
- (void)readBeaconValuesCompletion:(MESHDataCompletionBlock)completion {
    if (![self isConnecting]) {
        if(completion)completion(nil,[NSError errorWithDomain:NSLocalizedString(@"设备已断开连接",nil) code:ErrorCodeUnKnown userInfo:nil]);
        NSLog(NSLocalizedString(@"设备已断开连接",nil));
        return;
    }
    if(completion)self.readBeaconValuesCompletion = completion;
    if ([self isSupport:BleSupportsExtension]) {
        [self sendBeaconValue:[self hexStrToNSData:@"0102"] withCompletion:nil];//硬件类型
        [self sendBeaconValue:[self hexStrToNSData:@"0202"] withCompletion:nil];//温度电量
        [self sendBeaconValue:[self hexStrToNSData:@"0402"] withCompletion:nil];//UUID
        [self sendBeaconValue:[self hexStrToNSData:@"0602"] withCompletion:nil];//Major Minor
        [self sendBeaconValue:[self hexStrToNSData:@"0802"] withCompletion:nil];//MPower
        [self sendBeaconValue:[self hexStrToNSData:@"0A02"] withCompletion:nil];//Tx
        [self sendBeaconValue:[self hexStrToNSData:@"0C02"] withCompletion:nil];//Mode+BroadcatMode
        [self sendBeaconValue:[self hexStrToNSData:@"0E02"] withCompletion:nil];//Name
        [self sendBeaconValue:[self hexStrToNSData:@"1002"] withCompletion:nil];//Tx Interval
        [self sendBeaconValue:[self hexStrToNSData:@"1202"] withCompletion:nil];//温度电量间隔
        [self sendBeaconValue:[self hexStrToNSData:@"1402"] withCompletion:nil];//自定义广播数据
        [self sendBeaconValue:[self hexStrToNSData:@"1602"] withCompletion:nil];//Eddystone url
    }else{
        for (CBCharacteristic *c in self.dict_Service_IB.allValues) {
            [self readValueForCharacteristic:c];
        }
    }
}
@end
