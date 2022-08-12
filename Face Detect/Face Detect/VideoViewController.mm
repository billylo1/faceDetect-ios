//
//  VideoViewController.m
//
/*
    TODO:

    Preview full screen
    Shutter to invoke count
    
 
 */

#define kScreenW [UIScreen mainScreen].bounds.size.width
#define kScreenH [UIScreen mainScreen].bounds.size.height



#import "VideoViewController.h"
#import "FaceModel.h"
#import "FaceRegModel.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SetupResult) {
    SetupResultSuccess,
    SetupResultCameraNotAuthorized,
    SetupResultSessionConfigurationFailed
};

@interface VideoViewController ()<AVCapturePhotoCaptureDelegate>
@property (strong, nonatomic) UIImageView *imageView;
@property (strong, nonatomic) dispatch_queue_t queue;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (strong, nonatomic) FaceModel *faceModel;
@property (strong, nonatomic) FaceRegModel *faceRegModel;

@property (nonatomic) SetupResult setupResult;
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) AVCaptureSession* session;
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
@property (nonatomic) AVCaptureDeviceInput* videoDeviceInput;
@property (nonatomic) AVCaptureDeviceDiscoverySession* videoDeviceDiscoverySession;
@property (nonatomic, retain) UIActivityIndicatorView *spinner;
@property (nonatomic) AVCapturePhotoOutput* photoOutput;

@end

@implementation VideoViewController

- (FaceModel *)faceModel{
    if(!_faceModel){
        _faceModel = [FaceModel new];
    }
    return _faceModel;
}


- (FaceRegModel *)faceRegModel{
    if(!_faceRegModel){
        _faceRegModel = [FaceRegModel new];
    }
    return _faceRegModel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
   
    self.session = [[AVCaptureSession alloc] init];

    _queue = dispatch_queue_create("com.evergreenlabs.facecount", NULL);

    // Create a device discovery session.
    NSArray<AVCaptureDeviceType>* deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDualCamera, AVCaptureDeviceTypeBuiltInTrueDepthCamera, AVCaptureDeviceTypeBuiltInDualWideCamera];
    self.videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    
    // Set up the preview view.
    self.previewView.session = self.session;
    
    // Communicate with the session and other session objects on this queue.
    self.sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
    
    self.setupResult = SetupResultSuccess;

    /*
     Check video authorization status. Video access is required and audio
     access is optional. If audio access is denied, audio is not recorded
     during movie recording.
    */
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo])
    {
        case AVAuthorizationStatusAuthorized:
        {
            // The user has previously granted access to the camera.
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            /*
             The user has not yet been presented with the option to grant
             video access. We suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
            */
            dispatch_suspend(self.sessionQueue);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (!granted) {
                    self.setupResult = SetupResultCameraNotAuthorized;
                }
                dispatch_resume(self.sessionQueue);
            }];
            break;
        }
        default:
        {
            // The user has previously denied access.
            self.setupResult = SetupResultCameraNotAuthorized;
            break;
        }
    }
    
    /*
     Setup the capture session.
     In general, it is not safe to mutate an AVCaptureSession or any of its
     inputs, outputs, or connections from multiple threads at the same time.
     
     Don't perform these tasks on the main queue because
     AVCaptureSession.startRunning() is a blocking call, which can
     take a long time. We dispatch session setup to the sessionQueue, so
     that the main queue isn't blocked, which keeps the UI responsive.
    */
    dispatch_async(self.sessionQueue, ^{

        
        NSError *error;
        
        [self.session beginConfiguration];
        
        /*
         We do not create an AVCaptureMovieFileOutput when setting up the session because
         Live Photo is not supported when AVCaptureMovieFileOutput is added to the session.
        */
//        self.session.sessionPreset = AVCaptureSessionPresetPhoto;
        
        // Add video input.
        
        // Choose the back dual camera if available, otherwise default to a wide angle camera.
        AVCaptureDevice* videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDualCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
        if (!videoDevice) {
            // If a rear dual camera is not available, default to the rear dual wide angle camera.
            videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDualWideCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
        }
        if (!videoDevice) {
            // If a rear dual wide camera is not available, default to the rear wide angle camera.
            videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
        }
        if (!videoDevice) {
            // If a rear wide angle camera is not available, default to the front wide angle camera.
            videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
        }
        AVCaptureDeviceInput* videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        if (!videoDeviceInput) {
            NSLog(@"Could not create video device input: %@", error);
            self.setupResult = SetupResultSessionConfigurationFailed;
            [self.session commitConfiguration];
            return;
        }
        
        if ([self.session canAddInput:videoDeviceInput]) {
            [self.session addInput:videoDeviceInput];
            self.videoDeviceInput = videoDeviceInput;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                /*
                 Dispatch video streaming to the main queue because AVCaptureVideoPreviewLayer is the backing layer for PreviewView.
                 You can manipulate UIView only on the main thread.
                 Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
                 on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
                 
                 Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
                 handled by CameraViewController.viewWillTransition(to:with:).
                */
                AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
                if (self.windowOrientation != UIInterfaceOrientationUnknown) {
                    initialVideoOrientation = (AVCaptureVideoOrientation)self.windowOrientation;
                }
                
                self.previewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation;
            });
        }
        else {
            NSLog(@"Could not add video device input to the session");
            self.setupResult = SetupResultSessionConfigurationFailed;
            [self.session commitConfiguration];
            return;
        }
        
        // [self.session setSessionPreset:AVCaptureSessionPreset640x480];

        // Add photo output.
        AVCapturePhotoOutput* photoOutput = [[AVCapturePhotoOutput alloc] init];
        if ([self.session canAddOutput:photoOutput]) {
            [self.session addOutput:photoOutput];
            self.photoOutput = photoOutput;
            
            self.photoOutput.highResolutionCaptureEnabled = YES;
            self.photoOutput.maxPhotoQualityPrioritization = AVCapturePhotoQualityPrioritizationQuality;
            
        } else {
            NSLog(@"Could not add photo output to the session");
            self.setupResult = SetupResultSessionConfigurationFailed;
            [self.session commitConfiguration];
            return;
        }
                
        [self.session commitConfiguration];

        
    });
    dispatch_async(dispatch_get_main_queue(), ^{
        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        self.spinner.color = [UIColor yellowColor];
        [self.previewView addSubview:self.spinner];
    });

    
    NSLog(@"session started");
    

}

- (void)viewDidLayoutSubviews {

    NSLog(@"viewDidLayoutSubviews");
    
    self.imageView = [[UIImageView alloc]initWithFrame:self.previewView.bounds];
    [self.previewView addSubview:self.imageView];

}
- (UIInterfaceOrientation)windowOrientation {
    return self.view.window.windowScene.interfaceOrientation;
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    dispatch_async(self.sessionQueue, ^{
        switch (self.setupResult)
        {
            case SetupResultSuccess:
            {
                // Only setup observers and start the session running if setup succeeded.
//                [self addObservers];
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
                break;
            }
            case SetupResultCameraNotAuthorized:
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString* message = NSLocalizedString(@"AVCam doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera");
                    UIAlertController* alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    // Provide quick access to Settings.
                    UIAlertAction* settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings", @"Alert button to open Settings") style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                    }];
                    [alertController addAction:settingsAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                });
                break;
            }
            case SetupResultSessionConfigurationFailed:
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString* message = NSLocalizedString(@"Unable to capture media", @"Alert message when something goes wrong during capture session configuration");
                    UIAlertController* alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                });
                break;
            }
        }
    });
}

- (void) viewDidDisappear:(BOOL)animated
{
    dispatch_async(self.sessionQueue, ^{
        if (self.setupResult == SetupResultSuccess) {
            [self.session stopRunning];
        }
    });
    
    [super viewDidDisappear:animated];
}


- (UIImage*)imageFromPixelBuffer:(CMSampleBufferRef)p {
    CVImageBufferRef buffer;
    buffer = CMSampleBufferGetImageBuffer(p);
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base;
    size_t width, height, bytesPerRow;
    base = (uint8_t *)CVPixelBufferGetBaseAddress(buffer);
    width = CVPixelBufferGetWidth(buffer);
    height = CVPixelBufferGetHeight(buffer);
    bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    CGColorSpaceRef colorSpace;
    CGContextRef cgContext;
    colorSpace = CGColorSpaceCreateDeviceRGB();
    cgContext = CGBitmapContextCreate(base, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    CGImageRef cgImage;
    UIImage *image;
    cgImage = CGBitmapContextCreateImage(cgContext);
    image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    CGContextRelease(cgContext);
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return image;
}


-(UIImage *)drawFaces:(std::vector<FaceInfo>)face_info  InImage:(UIImage *)image {
    CGSize imageSize = [image size];
    UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0.0);
    [image drawAtPoint:CGPointMake(0, 0)];
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextDrawPath(context, kCGPathStroke);
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithRed:0/255.0 green:255/255.0 blue:0/255.0 alpha:1].CGColor);
    CGContextSetLineCap(context, kCGLineCapButt);
    CGContextSetLineJoin(context, kCGLineJoinMiter);
    CGContextSetLineWidth(context, 2.0f);
    CGContextStrokePath(context);
    NSLog(@"# of faces = %ld", face_info.size());
    
    if(face_info.size() > 0){
        for (int i = 0; i < face_info.size(); i++) {
            auto face = face_info[i];
            NSLog(@"x1 = %f, x2 = %f",face.x1,face.x2);
            CGContextAddRect(context, CGRectMake(face.x1, face.y1, face.x2 - face.x1, face.y2-face.y1));
            CGContextDrawPath(context, kCGPathStroke);
        }
    }
   return UIGraphicsGetImageFromCurrentImageContext();
}


- (void) handleShutterButton {
    
    NSString     *key           = (NSString *)kCVPixelBufferPixelFormatTypeKey;
    NSNumber     *value         = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    NSDictionary *formatSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    AVCapturePhotoSettings *photoSettings = [AVCapturePhotoSettings photoSettingsWithFormat:formatSettings];

    AVCapturePhotoOutput *output = self.session.outputs.firstObject;
    [output capturePhotoWithSettings:photoSettings delegate:self]
    
}



#pragma mark AVCapturePhotoCaptureDelegate
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo
                error:(NSError *)error {
    
    NSLog(@"> didFinishProcessingPhoto");
    
    CGImageRef ref = [photo CGImageRepresentation];
    int orientation = [photo.metadata[(NSString *)kCGImagePropertyOrientation] intValue];
    
    // map kCGImagePropertyOrientation to UIImageOrientation
    /*

     Apple            UIImage.imageOrientation     TIFF/IPTC kCGImagePropertyOrientation

     iPhone native     UIImageOrientationUp    = 0  =  Landscape left  = 1
     rotate 180deg     UIImageOrientationDown  = 1  =  Landscape right = 3
     rotate 90CCW      UIImageOrientationLeft  = 2  =  Portrait  down  = 8
     rotate 90CW       UIImageOrientationRight = 3  =  Portrait  up    = 6

     */
    
    UIImageOrientation uiOrientation = UIImageOrientationUp;
    
//    if (orientation == 3)
//        uiOrientation = UIImageOrientationDown;
//    else if (orientation == 8)
//        uiOrientation = UIImageOrientationLeft;
//    else if (orientation == 6)
//        uiOrientation = UIImageOrientationRight;
    
    UIImage *image = [UIImage imageWithCGImage:ref];
    std::vector<FaceInfo> face_info;
//     UIImage *image = [self imageFromPixelBuffer:sampleBuffer];
     NSLog(@"begin to recoganize card...........");
     face_info = [self.faceModel detectImg:image];
     dispatch_async(dispatch_get_main_queue(), ^{
        self.imageView.image  = [self drawFaces:face_info InImage:image];
    });
    
    NSLog(@"< didFinishProcessingPhoto");

}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSLog(@"didReceiveMemoryWarning");
}

- (IBAction)countAction:(id)sender {
    
    [self handleShutterButton];
}
@end
