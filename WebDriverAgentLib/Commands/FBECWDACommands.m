/**
 * ECWDA Extended Commands
 * 扩展功能命令 - 包含找色、OCR、长按、双击等功能
 */

#import "FBECWDACommands.h"

#import <CommonCrypto/CommonDigest.h>
#import <Vision/Vision.h>
#import <XCTest/XCTest.h>

#import "FBCommandStatus.h"
#import "FBConfiguration.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBScreenshot.h"
#import "FBSession.h"
#import "FBXCodeCompatibility.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIDevice+FBHelpers.h"
#import "XCUIElement+FBFind.h"


@interface FBECWDACommands (Private)
+ (NSInteger)parseColor:(NSString *)colorStr;
@end

@implementation FBECWDACommands

#pragma mark - Routes

+ (NSArray *)routes {
  return @[
    // 设备信息
    [[FBRoute GET:@"/wda/ecwda/info"].withoutSession
        respondWithTarget:self
                   action:@selector(handleGetInfo:)],

    // 找色功能
    [[FBRoute POST:@"/wda/findColor"].withoutSession
        respondWithTarget:self
                   action:@selector(handleFindColor:)],

    // 多点找色
    [[FBRoute POST:@"/wda/findMultiColor"].withoutSession
        respondWithTarget:self
                   action:@selector(handleFindMultiColor:)],

    // 比色
    [[FBRoute POST:@"/wda/cmpColor"].withoutSession
        respondWithTarget:self
                   action:@selector(handleCmpColor:)],

    // 获取像素颜色
    [[FBRoute POST:@"/wda/pixel"].withoutSession
        respondWithTarget:self
                   action:@selector(handleGetPixel:)],

    // OCR 识别
    [[FBRoute POST:@"/wda/ocr/recognize"].withoutSession
        respondWithTarget:self
                   action:@selector(handleOCR:)],

    // 长按
    [[FBRoute POST:@"/wda/longPress"].withoutSession
        respondWithTarget:self
                   action:@selector(handleLongPress:)],

    // 双击
    [[FBRoute POST:@"/wda/doubleTap"].withoutSession
        respondWithTarget:self
                   action:@selector(handleDoubleTap:)],

    // 文字查找点击
    [[FBRoute POST:@"/wda/clickText"].withoutSession
        respondWithTarget:self
                   action:@selector(handleClickText:)],

    // 工具函数 - 随机数
    [[FBRoute POST:@"/wda/utils/random"].withoutSession
        respondWithTarget:self
                   action:@selector(handleRandom:)],

    // 工具函数 - MD5
    [[FBRoute POST:@"/wda/utils/md5"].withoutSession
        respondWithTarget:self
                   action:@selector(handleMD5:)],
  ];
}

#pragma mark - Info

+ (id<FBResponsePayload>)handleGetInfo:(FBRouteRequest *)request {
  return FBResponseWithObject(@{
    @"version" : @"1.0.0",
    @"name" : @"ECWDA",
    @"features" : @[
      @"findColor", @"multiColor", @"cmpColor", @"pixel", @"ocr", @"longPress",
      @"doubleTap", @"clickText"
    ]
  });
}

#pragma mark - Color Finding

+ (id<FBResponsePayload>)handleFindColor:(FBRouteRequest *)request {
  NSString *colorStr = request.arguments[@"color"];
  NSDictionary *region = request.arguments[@"region"];
  NSNumber *similarity = request.arguments[@"similarity"] ?: @(0.9);

  if (!colorStr) {
    return FBResponseWithStatus([FBCommandStatus
        invalidArgumentErrorWithMessage:@"color is required"
                              traceback:nil]);
  }

  // 获取截图
  NSError *error;
  NSData *screenshotData =
      [FBScreenshot takeInOriginalResolutionWithQuality:2 error:&error];
  if (!screenshotData) {
    return FBResponseWithUnknownError(error);
  }

  UIImage *screenshot = [UIImage imageWithData:screenshotData];
  CGImageRef imageRef = screenshot.CGImage;

  // 解析目标颜色
  NSInteger targetColor = [self parseColor:colorStr];
  NSInteger targetR = (targetColor >> 16) & 0xFF;
  NSInteger targetG = (targetColor >> 8) & 0xFF;
  NSInteger targetB = targetColor & 0xFF;

  // 搜索区域
  CGFloat startX = 0, startY = 0;
  CGFloat endX = CGImageGetWidth(imageRef);
  CGFloat endY = CGImageGetHeight(imageRef);

  if (region) {
    startX = [region[@"x"] floatValue];
    startY = [region[@"y"] floatValue];
    endX = startX + [region[@"width"] floatValue];
    endY = startY + [region[@"height"] floatValue];
  }

  // 获取像素数据
  CFDataRef pixelData =
      CGDataProviderCopyData(CGImageGetDataProvider(imageRef));
  const UInt8 *data = CFDataGetBytePtr(pixelData);
  size_t bytesPerRow = CGImageGetBytesPerRow(imageRef);
  size_t bytesPerPixel = CGImageGetBitsPerPixel(imageRef) / 8;

  CGFloat sim = similarity.floatValue;
  NSInteger tolerance = (NSInteger)((1.0 - sim) * 255 * 3);

  // 搜索颜色
  for (NSInteger y = (NSInteger)startY; y < (NSInteger)endY; y++) {
    for (NSInteger x = (NSInteger)startX; x < (NSInteger)endX; x++) {
      NSInteger offset = y * bytesPerRow + x * bytesPerPixel;
      NSInteger r = data[offset];
      NSInteger g = data[offset + 1];
      NSInteger b = data[offset + 2];

      NSInteger diff = abs((int)(r - targetR)) + abs((int)(g - targetG)) +
                       abs((int)(b - targetB));
      if (diff <= tolerance) {
        CFRelease(pixelData);
        return FBResponseWithObject(
            @{@"x" : @(x), @"y" : @(y), @"found" : @YES});
      }
    }
  }

  CFRelease(pixelData);
  return FBResponseWithObject(@{@"x" : @(-1), @"y" : @(-1), @"found" : @NO});
}

+ (id<FBResponsePayload>)handleFindMultiColor:(FBRouteRequest *)request {
  NSString *firstColor = request.arguments[@"firstColor"];
  NSArray *offsetColors = request.arguments[@"offsetColors"];
  NSDictionary *region = request.arguments[@"region"];
  NSNumber *similarity = request.arguments[@"similarity"] ?: @(0.9);

  if (!firstColor || !offsetColors) {
    return FBResponseWithStatus([FBCommandStatus
        invalidArgumentErrorWithMessage:
            @"firstColor and offsetColors are required"
                              traceback:nil]);
  }

  // 获取截图
  NSError *error;
  NSData *screenshotData =
      [FBScreenshot takeInOriginalResolutionWithQuality:2 error:&error];
  if (!screenshotData) {
    return FBResponseWithUnknownError(error);
  }

  UIImage *screenshot = [UIImage imageWithData:screenshotData];
  CGImageRef imageRef = screenshot.CGImage;

  NSInteger firstColorVal = [self parseColor:firstColor];
  NSInteger firstR = (firstColorVal >> 16) & 0xFF;
  NSInteger firstG = (firstColorVal >> 8) & 0xFF;
  NSInteger firstB = firstColorVal & 0xFF;

  CGFloat startX = 0, startY = 0;
  CGFloat endX = CGImageGetWidth(imageRef);
  CGFloat endY = CGImageGetHeight(imageRef);

  if (region) {
    startX = [region[@"x"] floatValue];
    startY = [region[@"y"] floatValue];
    endX = startX + [region[@"width"] floatValue];
    endY = startY + [region[@"height"] floatValue];
  }

  CFDataRef pixelData =
      CGDataProviderCopyData(CGImageGetDataProvider(imageRef));
  const UInt8 *data = CFDataGetBytePtr(pixelData);
  size_t bytesPerRow = CGImageGetBytesPerRow(imageRef);
  size_t bytesPerPixel = CGImageGetBitsPerPixel(imageRef) / 8;
  size_t width = CGImageGetWidth(imageRef);
  size_t height = CGImageGetHeight(imageRef);

  CGFloat sim = similarity.floatValue;
  NSInteger tolerance = (NSInteger)((1.0 - sim) * 255 * 3);

  for (NSInteger y = (NSInteger)startY; y < (NSInteger)endY; y++) {
    for (NSInteger x = (NSInteger)startX; x < (NSInteger)endX; x++) {
      NSInteger offset = y * bytesPerRow + x * bytesPerPixel;
      NSInteger r = data[offset];
      NSInteger g = data[offset + 1];
      NSInteger b = data[offset + 2];

      NSInteger diff = abs((int)(r - firstR)) + abs((int)(g - firstG)) +
                       abs((int)(b - firstB));
      if (diff > tolerance)
        continue;

      // 检查偏移颜色
      BOOL allMatch = YES;
      for (NSDictionary *offsetColor in offsetColors) {
        NSInteger ox = [offsetColor[@"offsetX"] integerValue];
        NSInteger oy = [offsetColor[@"offsetY"] integerValue];
        NSString *colorHex = offsetColor[@"color"];

        NSInteger checkX = x + ox;
        NSInteger checkY = y + oy;

        if (checkX < 0 || checkX >= (NSInteger)width || checkY < 0 ||
            checkY >= (NSInteger)height) {
          allMatch = NO;
          break;
        }

        NSInteger checkOffset = checkY * bytesPerRow + checkX * bytesPerPixel;
        NSInteger checkR = data[checkOffset];
        NSInteger checkG = data[checkOffset + 1];
        NSInteger checkB = data[checkOffset + 2];

        NSInteger targetColorVal = [self parseColor:colorHex];
        NSInteger targetR = (targetColorVal >> 16) & 0xFF;
        NSInteger targetG = (targetColorVal >> 8) & 0xFF;
        NSInteger targetB = targetColorVal & 0xFF;

        NSInteger checkDiff = abs((int)(checkR - targetR)) +
                              abs((int)(checkG - targetG)) +
                              abs((int)(checkB - targetB));
        if (checkDiff > tolerance) {
          allMatch = NO;
          break;
        }
      }

      if (allMatch) {
        CFRelease(pixelData);
        return FBResponseWithObject(
            @{@"x" : @(x), @"y" : @(y), @"found" : @YES});
      }
    }
  }

  CFRelease(pixelData);
  return FBResponseWithObject(@{@"x" : @(-1), @"y" : @(-1), @"found" : @NO});
}

+ (id<FBResponsePayload>)handleCmpColor:(FBRouteRequest *)request {
  NSNumber *xNum = request.arguments[@"x"];
  NSNumber *yNum = request.arguments[@"y"];
  NSString *colorStr = request.arguments[@"color"];
  NSNumber *similarity = request.arguments[@"similarity"] ?: @(0.9);

  if (!xNum || !yNum || !colorStr) {
    return FBResponseWithStatus([FBCommandStatus
        invalidArgumentErrorWithMessage:@"x, y and color are required"
                              traceback:nil]);
  }

  NSError *error;
  NSData *screenshotData =
      [FBScreenshot takeInOriginalResolutionWithQuality:2 error:&error];
  if (!screenshotData) {
    return FBResponseWithUnknownError(error);
  }

  UIImage *screenshot = [UIImage imageWithData:screenshotData];
  CGImageRef imageRef = screenshot.CGImage;

  NSInteger x = xNum.integerValue;
  NSInteger y = yNum.integerValue;

  CFDataRef pixelData =
      CGDataProviderCopyData(CGImageGetDataProvider(imageRef));
  const UInt8 *data = CFDataGetBytePtr(pixelData);
  size_t bytesPerRow = CGImageGetBytesPerRow(imageRef);
  size_t bytesPerPixel = CGImageGetBitsPerPixel(imageRef) / 8;

  NSInteger offset = y * bytesPerRow + x * bytesPerPixel;
  NSInteger r = data[offset];
  NSInteger g = data[offset + 1];
  NSInteger b = data[offset + 2];

  CFRelease(pixelData);

  NSInteger targetColor = [self parseColor:colorStr];
  NSInteger targetR = (targetColor >> 16) & 0xFF;
  NSInteger targetG = (targetColor >> 8) & 0xFF;
  NSInteger targetB = targetColor & 0xFF;

  CGFloat sim = similarity.floatValue;
  NSInteger tolerance = (NSInteger)((1.0 - sim) * 255 * 3);
  NSInteger diff = abs((int)(r - targetR)) + abs((int)(g - targetG)) +
                   abs((int)(b - targetB));

  return FBResponseWithObject(
      @{@"match" : @(diff <= tolerance), @"diff" : @(diff)});
}

+ (id<FBResponsePayload>)handleGetPixel:(FBRouteRequest *)request {
  NSNumber *xNum = request.arguments[@"x"];
  NSNumber *yNum = request.arguments[@"y"];

  if (!xNum || !yNum) {
    return FBResponseWithStatus([FBCommandStatus
        invalidArgumentErrorWithMessage:@"x and y are required"
                              traceback:nil]);
  }

  NSError *error;
  NSData *screenshotData =
      [FBScreenshot takeInOriginalResolutionWithQuality:2 error:&error];
  if (!screenshotData) {
    return FBResponseWithUnknownError(error);
  }

  UIImage *screenshot = [UIImage imageWithData:screenshotData];
  CGImageRef imageRef = screenshot.CGImage;

  NSInteger x = xNum.integerValue;
  NSInteger y = yNum.integerValue;

  CFDataRef pixelData =
      CGDataProviderCopyData(CGImageGetDataProvider(imageRef));
  const UInt8 *data = CFDataGetBytePtr(pixelData);
  size_t bytesPerRow = CGImageGetBytesPerRow(imageRef);
  size_t bytesPerPixel = CGImageGetBitsPerPixel(imageRef) / 8;

  NSInteger offset = y * bytesPerRow + x * bytesPerPixel;
  NSInteger r = data[offset];
  NSInteger g = data[offset + 1];
  NSInteger b = data[offset + 2];

  CFRelease(pixelData);

  NSString *hex = [NSString
      stringWithFormat:@"#%02lX%02lX%02lX", (long)r, (long)g, (long)b];
  NSInteger colorInt = (r << 16) | (g << 8) | b;

  return FBResponseWithObject(@{
    @"color" : hex,
    @"value" : @(colorInt),
    @"r" : @(r),
    @"g" : @(g),
    @"b" : @(b)
  });
}

#pragma mark - OCR

+ (id<FBResponsePayload>)handleOCR:(FBRouteRequest *)request {
  if (@available(iOS 13.0, *)) {
    NSDictionary *region = request.arguments[@"region"];
    NSArray *languages =
        request.arguments[@"languages"] ?: @[ @"zh-Hans", @"en-US" ];

    NSError *error;
    NSData *screenshotData =
        [FBScreenshot takeInOriginalResolutionWithQuality:2 error:&error];
    if (!screenshotData) {
      return FBResponseWithUnknownError(error);
    }

    UIImage *screenshot = [UIImage imageWithData:screenshotData];
    CIImage *ciImage = [[CIImage alloc] initWithImage:screenshot];

    if (region) {
      CGFloat x = [region[@"x"] floatValue];
      CGFloat y = [region[@"y"] floatValue];
      CGFloat w = [region[@"width"] floatValue];
      CGFloat h = [region[@"height"] floatValue];
      CGFloat imgH = screenshot.size.height;
      ciImage =
          [ciImage imageByCroppingToRect:CGRectMake(x, imgH - y - h, w, h)];
    }

    __block NSMutableArray *results = [NSMutableArray array];

    VNRecognizeTextRequest *textRequest = [[VNRecognizeTextRequest alloc]
        initWithCompletionHandler:^(VNRequest *req, NSError *err) {
          for (VNRecognizedTextObservation *observation in req.results) {
            VNRecognizedText *topCandidate =
                [observation topCandidates:1].firstObject;
            if (topCandidate) {
              CGRect box = observation.boundingBox;
              CGFloat imgW = screenshot.size.width;
              CGFloat imgH = screenshot.size.height;

              [results addObject:@{
                @"text" : topCandidate.string,
                @"confidence" : @(topCandidate.confidence),
                @"x" : @(box.origin.x * imgW),
                @"y" : @((1 - box.origin.y - box.size.height) * imgH),
                @"width" : @(box.size.width * imgW),
                @"height" : @(box.size.height * imgH)
              }];
            }
          }
        }];

    textRequest.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    textRequest.recognitionLanguages = languages;
    textRequest.usesLanguageCorrection = YES;

    VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc] initWithCIImage:ciImage options:@{}];
    [handler performRequests:@[ textRequest ] error:&error];

    if (error) {
      return FBResponseWithUnknownError(error);
    }

    return FBResponseWithObject(@{@"results" : results});
  } else {
    return FBResponseWithStatus([FBCommandStatus
        unsupportedOperationErrorWithMessage:@"OCR requires iOS 13+"
                                   traceback:nil]);
  }
}

#pragma mark - Touch Actions

+ (id<FBResponsePayload>)handleLongPress:(FBRouteRequest *)request {
  NSNumber *x = request.arguments[@"x"];
  NSNumber *y = request.arguments[@"y"];
  NSNumber *duration = request.arguments[@"duration"] ?: @(1.0);

  if (!x || !y) {
    return FBResponseWithStatus([FBCommandStatus
        invalidArgumentErrorWithMessage:@"x and y are required"
                              traceback:nil]);
  }

  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  XCUICoordinate *coord =
      [app coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
  XCUICoordinate *target =
      [coord coordinateWithOffset:CGVectorMake(x.doubleValue, y.doubleValue)];
  [target pressForDuration:duration.doubleValue];

  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleDoubleTap:(FBRouteRequest *)request {
  NSNumber *x = request.arguments[@"x"];
  NSNumber *y = request.arguments[@"y"];

  if (!x || !y) {
    return FBResponseWithStatus([FBCommandStatus
        invalidArgumentErrorWithMessage:@"x and y are required"
                              traceback:nil]);
  }

  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  XCUICoordinate *coord =
      [app coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
  XCUICoordinate *target =
      [coord coordinateWithOffset:CGVectorMake(x.doubleValue, y.doubleValue)];
  [target doubleTap];

  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleClickText:(FBRouteRequest *)request {
  NSString *text = request.arguments[@"text"];

  if (!text) {
    return FBResponseWithStatus([FBCommandStatus
        invalidArgumentErrorWithMessage:@"text is required"
                              traceback:nil]);
  }

  XCUIApplication *app = XCUIApplication.fb_activeApplication;
  NSPredicate *predicate =
      [NSPredicate predicateWithFormat:@"label CONTAINS[cd] %@", text];
  NSArray *elements = [app fb_descendantsMatchingPredicate:predicate
                               shouldReturnAfterFirstMatch:YES];

  if (elements.count == 0) {
    return FBResponseWithObject(
        @{@"success" : @NO, @"message" : @"Element not found"});
  }

  XCUIElement *element = elements.firstObject;
  [element tap];

  return FBResponseWithObject(@{@"success" : @YES});
}

#pragma mark - Utility Functions

+ (id<FBResponsePayload>)handleRandom:(FBRouteRequest *)request {
  NSNumber *min = request.arguments[@"min"] ?: @0;
  NSNumber *max = request.arguments[@"max"] ?: @100;

  NSInteger minVal = min.integerValue;
  NSInteger maxVal = max.integerValue;
  NSInteger random =
      minVal + arc4random_uniform((uint32_t)(maxVal - minVal + 1));

  return FBResponseWithObject(@{@"value" : @(random)});
}

+ (id<FBResponsePayload>)handleMD5:(FBRouteRequest *)request {
  NSString *text = request.arguments[@"text"];
  if (!text) {
    return FBResponseWithStatus([FBCommandStatus
        invalidArgumentErrorWithMessage:@"text is required"
                              traceback:nil]);
  }

  const char *cStr = [text UTF8String];
  unsigned char digest[CC_MD5_DIGEST_LENGTH];
  CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);

  NSMutableString *output =
      [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
  for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
    [output appendFormat:@"%02x", digest[i]];
  }

  return FBResponseWithObject(@{@"md5" : output});
}

#pragma mark - Helper Methods

+ (NSInteger)parseColor:(NSString *)colorStr {
  NSString *hex = colorStr;
  if ([hex hasPrefix:@"#"]) {
    hex = [hex substringFromIndex:1];
  }
  if ([hex hasPrefix:@"0x"] || [hex hasPrefix:@"0X"]) {
    hex = [hex substringFromIndex:2];
  }

  unsigned int colorValue = 0;
  [[NSScanner scannerWithString:hex] scanHexInt:&colorValue];
  return colorValue;
}

@end
