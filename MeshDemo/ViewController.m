//
//  ViewController.m
//  MeshDemo
//
//  Created by thomasho on 2018/5/2.
//  Copyright © 2018年 o2o. All rights reserved.
//

#import "ViewController.h"
#import <MeshSDK/MeshSDK.h>

@interface ViewController ()<UITextViewDelegate,BLEScannerDelegate> {
    BLEBroadcast *_broadCast;
    BLEScanner *_bleScanner;
}

@property (nonatomic,strong) UITextView *textForSend;
@property (nonatomic,strong) UILabel *labelOfReceive;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
//    self.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIButton *sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    sendButton.backgroundColor  =[UIColor lightGrayColor];
    [sendButton setTitle:@"发送" forState:UIControlStateNormal];
    [sendButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [sendButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [sendButton addTarget:self action:@selector(sendButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:sendButton];
    
    _textForSend = [[UITextView alloc] init];
    _textForSend.translatesAutoresizingMaskIntoConstraints = NO;
    _textForSend.layer.borderWidth = 1;
    _textForSend.layer.borderColor = [UIColor blackColor].CGColor;
    _textForSend.delegate = self;
    [self.view addSubview:_textForSend];
    
    UIButton *receiveButton = [UIButton buttonWithType:UIButtonTypeCustom];
    receiveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [receiveButton setBackgroundColor:[UIColor greenColor]];
    [receiveButton setTitle:@"接收" forState:UIControlStateNormal];
    [receiveButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [receiveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    [receiveButton addTarget:self action:@selector(receiveButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:receiveButton];
    
    _labelOfReceive = [[UILabel alloc] init];
    _labelOfReceive.translatesAutoresizingMaskIntoConstraints = NO;
    _labelOfReceive.numberOfLines = 0;
    _labelOfReceive.layer.borderColor = [UIColor blackColor].CGColor;
    _labelOfReceive.layer.borderWidth = 1;
    [self.view addSubview:_labelOfReceive];
    
    NSDictionary *dict = @{@"sendButton":sendButton,@"textForSend":_textForSend,@"receiveButton":receiveButton,@"label":_labelOfReceive};
    NSDictionary *metrics = @{@"pad":@10};
    NSString *vfl0 = @"H:|-pad-[sendButton]-pad-|";
    NSString *vfl1 = @"H:|-pad-[textForSend]-pad-|";
    NSString *vfl2 = @"H:|-pad-[receiveButton]-pad-|";
    NSString *vfl3 = @"H:|-pad-[label]-pad-|";
    NSString *vfl4 = @"V:|-100-[sendButton(==31)]-pad-[textForSend(==100)]-pad-[receiveButton(==31)]-pad-[label(>=100)]-|";
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:vfl0 options:0 metrics:metrics views:dict]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:vfl1 options:0 metrics:metrics views:dict]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:vfl2 options:0 metrics:metrics views:dict]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:vfl3 options:0 metrics:metrics views:dict]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:vfl4 options:0 metrics:metrics views:dict]];
}

#pragma mark - **************** Actions

- (IBAction)sendButtonClicked:(UIButton *)sender {
    [sender setTitle:@"发送中..." forState:UIControlStateNormal];
    if (self.textForSend.text.length) {
        if (_broadCast == nil) {
            _broadCast = [[BLEBroadcast alloc] initWithDataStorage:nil];
        }
        NSData *data = [self.textForSend.text dataUsingEncoding:NSUTF8StringEncoding];
        [_broadCast setMeshCast:[self supportMeshServiceUUIDs].firstObject data:data];
        //[_broadCast advertBeaconRegion:[[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:@"E71E63CE-42A4-0F3D-43B3-E47C64344075"] identifier:@"regionIdentify"]];
        //[_broadCast stopBeaconRegion:[[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:@"E71E63CE-42A4-0F3D-43B3-E47C64344075"] identifier:@"regionIdentify"]];
        [_broadCast start];
    }
}

- (IBAction)receiveButtonClicked:(UIButton *)sender {
    [sender setTitle:@"接收中..." forState:UIControlStateNormal];
    if (_bleScanner == nil) {
        _bleScanner = [[BLEScanner alloc] initWithDataStorage:nil];
        _bleScanner.delegate = self;
    }
    [_bleScanner start];
}

#pragma mark - **************** DataSources

- (NSArray <CBUUID *>*)supportMeshServiceUUIDs {
    return @[[CBUUID UUIDWithString:@"FFDD"]];
}

#pragma mark - **************** Delegates

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if ([text isEqualToString:@"\n"]) {
        [textView resignFirstResponder];
        return NO;
    }
    return YES;
}

- (void)bleScanner:(BLEScanner *)scanner didDiscoverUUID:(CBUUID *)uuid advertisementData:(NSData *)advertisementData RSSI:(NSNumber *)RSSI {
    NSLog(@"%@_%@",[NSString stringWithUTF8String:advertisementData.bytes],uuid);
    void(^runOnMainThead)(void) = ^{
        self.labelOfReceive.text = [[NSString alloc] initWithData:advertisementData encoding:NSUTF8StringEncoding];
    };
    dispatch_async( dispatch_get_main_queue(), runOnMainThead);
}

@end
