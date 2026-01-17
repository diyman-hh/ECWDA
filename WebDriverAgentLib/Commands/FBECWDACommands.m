/**
 * ECWDA Extended Commands
 * 扩展功能命令 - 包含找色、OCR、脚本执行等功能
 */

#import "FBECWDACommands.h"

#import <XCTest/XCUIDevice.h>
#import <XCTest/XCUIScreen.h>

#import "FBApplication.h"
#import "FBCommandHandler.h"
#import "FBConfiguration.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBSession.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIDevice+FBHelpers.h"
#import "XCUIScreen+FBSnapshot.h"

@implementation FBECWDACommands

#pragma mark - Routes

+ (NSArray *)routes
{
  return @[
    // 设备信息
    [[FBRoute GET:@"/wda/device/info"].withoutSession respondWithTarget:self action:@selector(handleGetDeviceInfo:)],
    [[FBRoute GET:@"/wda/device/info"] respondWithTarget:self action:@selector(handleGetDeviceInfo:)],
    
    // 找色功能
    [[FBRoute POST:@"/wda/findColor"].withoutSession respondWithTarget:self action:@selector(handleFindColor:)],
    [[FBRoute POST:@"/wda/findColor"] respondWithTarget:self action:@selector(handleFindColor:)],
    
    // 多点找色
    [[FBRoute POST:@"/wda/findMultiColor"].withoutSession respondWithTarget:self action:@selector(handleFindMultiColor:)],
    [[FBRoute POST:@"/wda/findMultiColor"] respondWithTarget:self action:@selector(handleFindMultiColor:)],
    
    // 比色
    [[FBRoute POST:@"/wda/cmpColor"].withoutSession respondWithTarget:self action:@selector(handleCmpColor:)],
    [[FBRoute POST:@"/wda/cmpColor"] respondWithTarget:self action:@selector(handleCmpColor:)],
    
    // 获取像素颜色
    [[FBRoute POST:@"/wda/pixel"].withoutSession respondWithTarget:self action:@selector(handleGetPixel:)],
    [[FBRoute POST:@"/wda/pixel"] respondWithTarget:self action:@selector(handleGetPixel:)],
    
    // OCR 识别
    [[FBRoute POST:@"/wda/ocr/recognize"].withoutSession respondWithTarget:self action:@selector(handleOCR:)],
    [[FBRoute POST:@"/wda/ocr/recognize"] respondWithTarget:self action:@selector(handleOCR:)],
    
    // 脚本执行 (脱机模式)
    [[FBRoute POST:@"/wda/script/execute"].withoutSession respondWithTarget:self action:@selector(handleExecuteScript:)],
    [[FBRoute POST:@"/wda/script/execute"] respondWithTarget:self action:@selector(handleExecuteScript:)],
    
    // 脚本状态
    [[FBRoute GET:@"/wda/script/status"].withoutSession respondWithTarget:self action:@selector(handleScriptStatus:)],
    [[FBRoute GET:@"/wda/script/status"] respondWithTarget:self action:@selector(handleScriptStatus:)],
    
    // 停止脚本
    [[FBRoute POST:@"/wda/script/stop"].withoutSession respondWithTarget:self action:@selector(handleStopScript:)],
    [[FBRoute POST:@"/wda/script/stop"] respondWithTarget:self action:@selector(handleStopScript:)],
    
    // 长按
    [[FBRoute POST:@"/wda/longPress"].withoutSession respondWithTarget:self action:@selector(handleLongPress:)],
    [[FBRoute POST:@"/wda/longPress"] respondWithTarget:self action:@selector(handleLongPress:)],
    
    // 双击
    [[FBRoute POST:@"/wda/doubleTap"].withoutSession respondWithTarget:self action:@selector(handleDoubleTap:)],
    [[FBRoute POST:@"/wda/doubleTap"] respondWithTarget:self action:@selector(handleDoubleTap:)],
  ];
}

#pragma mark - Device Info

+ (id<FBResponsePayload>)handleGetDeviceInfo:(FBRouteRequest *)request
{
  UIDevice *device = [UIDevice currentDevice];
  CGRect screenBounds = [UIScreen mainScreen].bounds;
  CGFloat scale = [UIScreen mainScreen].scale;
  
  NSDictionary *info = @{
    @"name": device.name ?: @"Unknown",
    @"systemName": device.systemName ?: @"iOS",
    @"systemVersion": device.systemVersion ?: @"Unknown",
    @"model": device.model ?: @"Unknown",
    @"localizedModel": device.localizedModel ?: @"Unknown",
    @"identifierForVendor": device.identifierForVendor.UUIDString ?: @"Unknown",
    @"screenWidth": @(screenBounds.size.width),
    @"screenHeight": @(screenBounds.size.height),
    @"scale": @(scale),
    @"batteryLevel": @(device.batteryLevel),
    @"batteryState": @(device.batteryState),
  };
  
  return FBResponseWithObject(info);
}

#pragma mark - Color Finding

+ (id<FBResponsePayload>)handleFindColor:(FBRouteRequest *)request
{
  NSString *colorHex = request.arguments[@"color"];
  NSDictionary *region = request.arguments[@"region"];
  NSNumber *tolerance = request.arguments[@"tolerance"] ?: @(10);
  
  if (!colorHex) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"color is required" traceback:nil]);
  }
  
  // 截取屏幕
  NSError *error;
  CGImageRef screenshot = [[XCUIScreen mainScreen] fb_takeScreenshot:&error].CGImage;
  if (!screenshot) {
    return FBResponseWithUnknownError(error);
  }
  
  // 解析目标颜色
  UIColor *targetColor = [self colorFromHexString:colorHex];
  if (!targetColor) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Invalid color format" traceback:nil]);
  }
  
  CGFloat targetR, targetG, targetB, targetA;
  [targetColor getRed:&targetR green:&targetG blue:&targetB alpha:&targetA];
  
  // 获取图像数据
  size_t width = CGImageGetWidth(screenshot);
  size_t height = CGImageGetHeight(screenshot);
  
  // 设置搜索区域
  NSInteger startX = 0, startY = 0, endX = width, endY = height;
  if (region) {
    startX = [region[@"x"] integerValue];
    startY = [region[@"y"] integerValue];
    endX = startX + [region[@"width"] integerValue];
    endY = startY + [region[@"height"] integerValue];
  }
  
  // 创建位图上下文
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(screenshot));
  const UInt8 *data = CFDataGetBytePtr(pixelData);
  size_t bytesPerRow = CGImageGetBytesPerRow(screenshot);
  size_t bytesPerPixel = CGImageGetBitsPerPixel(screenshot) / 8;
  
  NSInteger toleranceInt = tolerance.integerValue;
  
  // 遍历查找颜色
  for (NSInteger y = startY; y < MIN(endY, (NSInteger)height); y++) {
    for (NSInteger x = startX; x < MIN(endX, (NSInteger)width); x++) {
      NSInteger offset = y * bytesPerRow + x * bytesPerPixel;
      
      CGFloat r = data[offset] / 255.0;
      CGFloat g = data[offset + 1] / 255.0;
      CGFloat b = data[offset + 2] / 255.0;
      
      if (fabs(r - targetR) * 255 <= toleranceInt &&
          fabs(g - targetG) * 255 <= toleranceInt &&
          fabs(b - targetB) * 255 <= toleranceInt) {
        CFRelease(pixelData);
        return FBResponseWithObject(@{
          @"found": @YES,
          @"x": @(x),
          @"y": @(y)
        });
      }
    }
  }
  
  CFRelease(pixelData);
  return FBResponseWithObject(@{@"found": @NO});
}

+ (id<FBResponsePayload>)handleFindMultiColor:(FBRouteRequest *)request
{
  NSString *firstColor = request.arguments[@"firstColor"];
  NSArray *offsetColors = request.arguments[@"offsetColors"];
  NSDictionary *region = request.arguments[@"region"];
  NSNumber *tolerance = request.arguments[@"tolerance"] ?: @(10);
  
  if (!firstColor || !offsetColors) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"firstColor and offsetColors are required" traceback:nil]);
  }
  
  // 截取屏幕
  NSError *error;
  CGImageRef screenshot = [[XCUIScreen mainScreen] fb_takeScreenshot:&error].CGImage;
  if (!screenshot) {
    return FBResponseWithUnknownError(error);
  }
  
  // 解析第一个颜色
  UIColor *targetColor = [self colorFromHexString:firstColor];
  if (!targetColor) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Invalid firstColor format" traceback:nil]);
  }
  
  CGFloat targetR, targetG, targetB, targetA;
  [targetColor getRed:&targetR green:&targetG blue:&targetB alpha:&targetA];
  
  // 获取图像数据
  size_t width = CGImageGetWidth(screenshot);
  size_t height = CGImageGetHeight(screenshot);
  
  NSInteger startX = 0, startY = 0, endX = width, endY = height;
  if (region) {
    startX = [region[@"x"] integerValue];
    startY = [region[@"y"] integerValue];
    endX = startX + [region[@"width"] integerValue];
    endY = startY + [region[@"height"] integerValue];
  }
  
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(screenshot));
  const UInt8 *data = CFDataGetBytePtr(pixelData);
  size_t bytesPerRow = CGImageGetBytesPerRow(screenshot);
  size_t bytesPerPixel = CGImageGetBitsPerPixel(screenshot) / 8;
  
  NSInteger toleranceInt = tolerance.integerValue;
  
  // 遍历查找
  for (NSInteger y = startY; y < MIN(endY, (NSInteger)height); y++) {
    for (NSInteger x = startX; x < MIN(endX, (NSInteger)width); x++) {
      NSInteger offset = y * bytesPerRow + x * bytesPerPixel;
      
      CGFloat r = data[offset] / 255.0;
      CGFloat g = data[offset + 1] / 255.0;
      CGFloat b = data[offset + 2] / 255.0;
      
      // 检查第一个颜色
      if (fabs(r - targetR) * 255 > toleranceInt ||
          fabs(g - targetG) * 255 > toleranceInt ||
          fabs(b - targetB) * 255 > toleranceInt) {
        continue;
      }
      
      // 检查偏移颜色
      BOOL allMatch = YES;
      for (NSDictionary *oc in offsetColors) {
        NSArray *offsetArr = oc[@"offset"];
        NSString *colorStr = oc[@"color"];
        
        NSInteger ox = x + [offsetArr[0] integerValue];
        NSInteger oy = y + [offsetArr[1] integerValue];
        
        if (ox < 0 || ox >= width || oy < 0 || oy >= height) {
          allMatch = NO;
          break;
        }
        
        UIColor *ocColor = [self colorFromHexString:colorStr];
        CGFloat ocR, ocG, ocB, ocA;
        [ocColor getRed:&ocR green:&ocG blue:&ocB alpha:&ocA];
        
        NSInteger ocOffset = oy * bytesPerRow + ox * bytesPerPixel;
        CGFloat pr = data[ocOffset] / 255.0;
        CGFloat pg = data[ocOffset + 1] / 255.0;
        CGFloat pb = data[ocOffset + 2] / 255.0;
        
        if (fabs(pr - ocR) * 255 > toleranceInt ||
            fabs(pg - ocG) * 255 > toleranceInt ||
            fabs(pb - ocB) * 255 > toleranceInt) {
          allMatch = NO;
          break;
        }
      }
      
      if (allMatch) {
        CFRelease(pixelData);
        return FBResponseWithObject(@{
          @"found": @YES,
          @"x": @(x),
          @"y": @(y)
        });
      }
    }
  }
  
  CFRelease(pixelData);
  return FBResponseWithObject(@{@"found": @NO});
}

+ (id<FBResponsePayload>)handleCmpColor:(FBRouteRequest *)request
{
  NSNumber *xNum = request.arguments[@"x"];
  NSNumber *yNum = request.arguments[@"y"];
  NSString *colorHex = request.arguments[@"color"];
  NSNumber *tolerance = request.arguments[@"tolerance"] ?: @(10);
  
  if (!xNum || !yNum || !colorHex) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"x, y and color are required" traceback:nil]);
  }
  
  // 截取屏幕
  NSError *error;
  CGImageRef screenshot = [[XCUIScreen mainScreen] fb_takeScreenshot:&error].CGImage;
  if (!screenshot) {
    return FBResponseWithUnknownError(error);
  }
  
  NSInteger x = xNum.integerValue;
  NSInteger y = yNum.integerValue;
  
  size_t width = CGImageGetWidth(screenshot);
  size_t height = CGImageGetHeight(screenshot);
  
  if (x < 0 || x >= width || y < 0 || y >= height) {
    return FBResponseWithObject(@{@"match": @NO, @"error": @"Coordinates out of bounds"});
  }
  
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(screenshot));
  const UInt8 *data = CFDataGetBytePtr(pixelData);
  size_t bytesPerRow = CGImageGetBytesPerRow(screenshot);
  size_t bytesPerPixel = CGImageGetBitsPerPixel(screenshot) / 8;
  
  NSInteger offset = y * bytesPerRow + x * bytesPerPixel;
  CGFloat r = data[offset] / 255.0;
  CGFloat g = data[offset + 1] / 255.0;
  CGFloat b = data[offset + 2] / 255.0;
  
  CFRelease(pixelData);
  
  UIColor *targetColor = [self colorFromHexString:colorHex];
  CGFloat targetR, targetG, targetB, targetA;
  [targetColor getRed:&targetR green:&targetG blue:&targetB alpha:&targetA];
  
  NSInteger toleranceInt = tolerance.integerValue;
  BOOL match = (fabs(r - targetR) * 255 <= toleranceInt &&
                fabs(g - targetG) * 255 <= toleranceInt &&
                fabs(b - targetB) * 255 <= toleranceInt);
  
  return FBResponseWithObject(@{
    @"match": @(match),
    @"actualColor": [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r*255), (int)(g*255), (int)(b*255)]
  });
}

+ (id<FBResponsePayload>)handleGetPixel:(FBRouteRequest *)request
{
  NSNumber *xNum = request.arguments[@"x"];
  NSNumber *yNum = request.arguments[@"y"];
  
  if (!xNum || !yNum) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"x and y are required" traceback:nil]);
  }
  
  // 截取屏幕
  NSError *error;
  CGImageRef screenshot = [[XCUIScreen mainScreen] fb_takeScreenshot:&error].CGImage;
  if (!screenshot) {
    return FBResponseWithUnknownError(error);
  }
  
  NSInteger x = xNum.integerValue;
  NSInteger y = yNum.integerValue;
  
  size_t width = CGImageGetWidth(screenshot);
  size_t height = CGImageGetHeight(screenshot);
  
  if (x < 0 || x >= width || y < 0 || y >= height) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"Coordinates out of bounds" traceback:nil]);
  }
  
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(screenshot));
  const UInt8 *data = CFDataGetBytePtr(pixelData);
  size_t bytesPerRow = CGImageGetBytesPerRow(screenshot);
  size_t bytesPerPixel = CGImageGetBitsPerPixel(screenshot) / 8;
  
  NSInteger offset = y * bytesPerRow + x * bytesPerPixel;
  int r = data[offset];
  int g = data[offset + 1];
  int b = data[offset + 2];
  
  CFRelease(pixelData);
  
  return FBResponseWithObject(@{
    @"color": [NSString stringWithFormat:@"#%02X%02X%02X", r, g, b],
    @"r": @(r),
    @"g": @(g),
    @"b": @(b)
  });
}

#pragma mark - OCR

+ (id<FBResponsePayload>)handleOCR:(FBRouteRequest *)request
{
  // 使用 iOS Vision Framework 进行 OCR
  // 需要 iOS 13+
  
  NSDictionary *region = request.arguments[@"region"];
  
  // 截取屏幕
  NSError *error;
  UIImage *screenshot = [[XCUIScreen mainScreen] fb_takeScreenshot:&error];
  if (!screenshot) {
    return FBResponseWithUnknownError(error);
  }
  
  // 裁剪区域
  if (region) {
    CGFloat x = [region[@"x"] floatValue];
    CGFloat y = [region[@"y"] floatValue];
    CGFloat w = [region[@"width"] floatValue];
    CGFloat h = [region[@"height"] floatValue];
    
    CGRect cropRect = CGRectMake(x, y, w, h);
    CGImageRef imageRef = CGImageCreateWithImageInRect(screenshot.CGImage, cropRect);
    screenshot = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
  }
  
  // 使用 Vision Framework 进行 OCR
  if (@available(iOS 13.0, *)) {
    NSMutableArray *results = [NSMutableArray array];
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:screenshot.CGImage options:@{}];
    
    VNRecognizeTextRequest *textRequest = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *error) {
      if (error) {
        return;
      }
      
      for (VNRecognizedTextObservation *observation in request.results) {
        VNRecognizedText *text = [[observation topCandidates:1] firstObject];
        if (text) {
          CGRect boundingBox = observation.boundingBox;
          CGFloat imageWidth = screenshot.size.width;
          CGFloat imageHeight = screenshot.size.height;
          
          [results addObject:@{
            @"text": text.string,
            @"confidence": @(text.confidence),
            @"x": @(boundingBox.origin.x * imageWidth),
            @"y": @((1 - boundingBox.origin.y - boundingBox.size.height) * imageHeight),
            @"width": @(boundingBox.size.width * imageWidth),
            @"height": @(boundingBox.size.height * imageHeight)
          }];
        }
      }
    }];
    
    textRequest.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    textRequest.recognitionLanguages = @[@"zh-Hans", @"en"];
    textRequest.usesLanguageCorrection = YES;
    
    NSError *performError;
    [handler performRequests:@[textRequest] error:&performError];
    
    if (performError) {
      return FBResponseWithUnknownError(performError);
    }
    
    return FBResponseWithObject(@{@"texts": results});
  } else {
    return FBResponseWithStatus([FBCommandStatus unsupportedOperationErrorWithMessage:@"OCR requires iOS 13+" traceback:nil]);
  }
}

#pragma mark - Script Execution

static NSString *currentScriptId = nil;
static BOOL scriptRunning = NO;
static NSMutableArray *scriptLog = nil;

+ (id<FBResponsePayload>)handleExecuteScript:(FBRouteRequest *)request
{
  // 脚本执行 - 用于脱机模式
  NSArray *commands = request.arguments[@"commands"];
  NSString *scriptId = request.arguments[@"scriptId"] ?: [[NSUUID UUID] UUIDString];
  
  if (!commands || commands.count == 0) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"commands array is required" traceback:nil]);
  }
  
  if (scriptRunning) {
    return FBResponseWithStatus([FBCommandStatus sessionNotCreatedErrorWithMessage:@"Another script is running" traceback:nil]);
  }
  
  // 初始化脚本状态
  currentScriptId = scriptId;
  scriptRunning = YES;
  scriptLog = [NSMutableArray array];
  
  // 在后台线程执行脚本
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    for (NSDictionary *cmd in commands) {
      if (!scriptRunning) {
        [scriptLog addObject:@{@"action": @"stopped", @"message": @"Script stopped by user"}];
        break;
      }
      
      NSString *action = cmd[@"action"];
      NSDictionary *params = cmd[@"params"];
      
      [self executeCommand:action params:params];
    }
    
    scriptRunning = NO;
    [scriptLog addObject:@{@"action": @"completed", @"message": @"Script execution completed"}];
  });
  
  return FBResponseWithObject(@{
    @"scriptId": scriptId,
    @"status": @"started"
  });
}

+ (void)executeCommand:(NSString *)action params:(NSDictionary *)params
{
  NSError *error;
  
  if ([action isEqualToString:@"tap"]) {
    CGFloat x = [params[@"x"] floatValue];
    CGFloat y = [params[@"y"] floatValue];
    
    XCUIApplication *app = XCUIApplication.fb_activeApplication;
    XCUICoordinate *coordinate = [app coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
    XCUICoordinate *target = [coordinate coordinateWithOffset:CGVectorMake(x, y)];
    [target tap];
    
    [scriptLog addObject:@{@"action": action, @"x": @(x), @"y": @(y), @"status": @"success"}];
    
  } else if ([action isEqualToString:@"swipe"]) {
    CGFloat fromX = [params[@"fromX"] floatValue];
    CGFloat fromY = [params[@"fromY"] floatValue];
    CGFloat toX = [params[@"toX"] floatValue];
    CGFloat toY = [params[@"toY"] floatValue];
    CGFloat duration = [params[@"duration"] floatValue] ?: 0.5;
    
    XCUIApplication *app = XCUIApplication.fb_activeApplication;
    XCUICoordinate *start = [[app coordinateWithNormalizedOffset:CGVectorMake(0, 0)] coordinateWithOffset:CGVectorMake(fromX, fromY)];
    XCUICoordinate *end = [[app coordinateWithNormalizedOffset:CGVectorMake(0, 0)] coordinateWithOffset:CGVectorMake(toX, toY)];
    [start pressForDuration:0 thenDragToCoordinate:end withVelocity:XCUIGestureVelocityDefault thenHoldForDuration:0];
    
    [scriptLog addObject:@{@"action": action, @"status": @"success"}];
    
  } else if ([action isEqualToString:@"sleep"]) {
    NSTimeInterval seconds = [params[@"seconds"] doubleValue] ?: 1.0;
    [NSThread sleepForTimeInterval:seconds];
    
    [scriptLog addObject:@{@"action": action, @"seconds": @(seconds), @"status": @"success"}];
    
  } else if ([action isEqualToString:@"home"]) {
    [[XCUIDevice sharedDevice] pressButton:XCUIDeviceButtonHome];
    
    [scriptLog addObject:@{@"action": action, @"status": @"success"}];
    
  } else {
    [scriptLog addObject:@{@"action": action, @"status": @"unknown_action"}];
  }
}

+ (id<FBResponsePayload>)handleScriptStatus:(FBRouteRequest *)request
{
  return FBResponseWithObject(@{
    @"scriptId": currentScriptId ?: [NSNull null],
    @"running": @(scriptRunning),
    @"log": scriptLog ?: @[]
  });
}

+ (id<FBResponsePayload>)handleStopScript:(FBRouteRequest *)request
{
  scriptRunning = NO;
  return FBResponseWithObject(@{
    @"status": @"stopped"
  });
}

#pragma mark - Touch Actions

+ (id<FBResponsePayload>)handleLongPress:(FBRouteRequest *)request
{
  NSNumber *xNum = request.arguments[@"x"];
  NSNumber *yNum = request.arguments[@"y"];
  NSNumber *durationNum = request.arguments[@"duration"] ?: @(1.0);
  
  if (!xNum || !yNum) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"x and y are required" traceback:nil]);
  }
  
  CGFloat x = xNum.floatValue;
  CGFloat y = yNum.floatValue;
  CGFloat duration = durationNum.floatValue;
  
  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  XCUICoordinate *coordinate = [[app coordinateWithNormalizedOffset:CGVectorMake(0, 0)] coordinateWithOffset:CGVectorMake(x, y)];
  [coordinate pressForDuration:duration];
  
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleDoubleTap:(FBRouteRequest *)request
{
  NSNumber *xNum = request.arguments[@"x"];
  NSNumber *yNum = request.arguments[@"y"];
  
  if (!xNum || !yNum) {
    return FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:@"x and y are required" traceback:nil]);
  }
  
  CGFloat x = xNum.floatValue;
  CGFloat y = yNum.floatValue;
  
  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  XCUICoordinate *coordinate = [[app coordinateWithNormalizedOffset:CGVectorMake(0, 0)] coordinateWithOffset:CGVectorMake(x, y)];
  [coordinate doubleTap];
  
  return FBResponseWithOK();
}

#pragma mark - Helpers

+ (UIColor *)colorFromHexString:(NSString *)hexString
{
  unsigned rgbValue = 0;
  NSScanner *scanner = [NSScanner scannerWithString:hexString];
  [scanner setScanLocation:[hexString hasPrefix:@"#"] ? 1 : 0];
  [scanner scanHexInt:&rgbValue];
  
  return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16) / 255.0
                         green:((rgbValue & 0x00FF00) >> 8) / 255.0
                          blue:(rgbValue & 0x0000FF) / 255.0
                         alpha:1.0];
}

@end
