//
//  VideoViewController.h
//  sdkTest
//
//  Created by IanWong on 2019/10/9.
//  Copyright © 2019 com.SunYard.IanWong. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "PreviewView.h"

NS_ASSUME_NONNULL_BEGIN

@protocol bankCardVideoControllerDelegate <NSObject>
- (void)videoDidGetOneFrameToImage:(UIImage *)image;

@end

@interface VideoViewController : UIViewController
@property (nonatomic, weak) id<bankCardVideoControllerDelegate> delegate;
@property (strong, nonatomic) IBOutlet PreviewView *previewView;
- (IBAction)countAction:(id)sender;
@property (strong, nonatomic) IBOutlet UIButton *countButton;
@end

NS_ASSUME_NONNULL_END
