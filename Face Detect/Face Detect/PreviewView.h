//
//  PreviewView.h
//  Face Detect
//
//  Created by Billy Lo on 2022-05-18.
//  Copyright © 2022 Evergreen. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class AVCaptureSession;

@interface PreviewView : UIView

@property (nonatomic, readonly) AVCaptureVideoPreviewLayer *videoPreviewLayer;
@property (nonatomic) AVCaptureSession *session;

@end
