//
//  PreviewView.m
//  Face Detect
//
//  Created by Billy Lo on 2022-05-18.
//  Copyright © 2022 Evergreen. All rights reserved.
//

#import "PreviewView.h"

@implementation PreviewView

+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureVideoPreviewLayer*) videoPreviewLayer
{
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

- (AVCaptureSession*) session
{
    return self.videoPreviewLayer.session;
}

- (void)setSession:(AVCaptureSession*) session
{
    self.videoPreviewLayer.session = session;
}



@end
