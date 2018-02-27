//
//  MESHTools.m
//  MeshSDK
//
//  Created by arron on 18/2/18.
//  Copyright © 2018年 arron. All rights reserved.
//

#import "MESHTools.h"

@implementation MESHTools

+ (NSString *)data2UTF8:(NSData *)data{
    NSRange range = [data rangeOfData:[MESHTools hex2data:@"00"] options:0 range:NSMakeRange(0, data.length)];
    if(range.location!=NSNotFound){
        data = [data subdataWithRange:NSMakeRange(0, range.location+1)];
    }
    if (data.length == 0) {
        return @"";
    }
    NSString *name = [NSString stringWithUTF8String:data.bytes];
    //    name = [[NSString alloc] initWithUTF8String:data.bytes];
    while (name.length==0&&data.length) {
        data = [data subdataWithRange:NSMakeRange(0, data.length-1)];
        if(data.length)name = [NSString stringWithUTF8String:data.bytes];
        else name = @"";
    }
    return name;
}

+ (NSData *)hex2data:(NSString *)hex {
    NSMutableData *data = [[NSMutableData alloc] init];
    unsigned char whole_byte;
    char byte_chars[3] = {'\0','\0','\0'};
    
    //奇数就会跳过 半个字节。造成数据丢失。特此左补0
    if (hex.length%2) {
        hex = [@"0" stringByAppendingString:hex];
    }
    int i;
    for (i = 0; i < [hex length]/2; i++) {
        byte_chars[0] = [hex characterAtIndex:i * 2];
        byte_chars[1] = [hex characterAtIndex:i * 2 + 1];
        whole_byte = strtol(byte_chars, NULL, 16);
        [data appendBytes:&whole_byte length:1];
    }
    return data;
}

+ (NSString *)data2hex:(NSData *)data
{
    if (data == nil) {
        return nil;
    }
    NSMutableString* hexString = [NSMutableString string];
    const unsigned char *p = [data bytes];
    for (int i=0; i < [data length]; i++) {
        [hexString appendFormat:@"%02x", *p++];
    }
    return hexString;
}

+ (int32_t )data2Integer:(NSData *)data {
    if (data == nil) {
        return 0;
    }
    int len = (int)data.length;
    if (len>4) {
        return 0;
    }
    //    unsigned char byte[len];
    //    [data getBytes:byte length:len];
    //    for (int i=0; i<len; i++) {
    //        value |=byte[i]<<((len-i-1)*8);
    //    }
    int32_t value = 0;
    [data getBytes:&value length:len];
    return value;
}

+ (uint32_t)data2UInteger:(NSData *)data {
    return [self data2Integer:data];
}

+ (NSData *)integer2data:(int32_t )i {
    return [NSData dataWithBytes: &i length: sizeof(i)];
}
+ (NSData *)uinteger2data:(uint32_t )i {
    return [NSData dataWithBytes: &i length: sizeof(i)];
}

@end
