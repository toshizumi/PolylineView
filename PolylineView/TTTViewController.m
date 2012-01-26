//
//  TTTViewController.m
//  PolylineView
//
//  Created by 敏純 堀田 on 12/01/26.
//  Copyright (c) 2012年 Garage Standard Inc. All rights reserved.
//

#import "TTTViewController.h"
#import <CoreLocation/CoreLocation.h>

#pragma mark - http utility
@interface HttpClient : NSObject

+ (void)request:(NSURLRequest *)request 
        success:(void (^)(NSData *, NSHTTPURLResponse *))onSuccess 
          error:(void (^)(NSError *, NSHTTPURLResponse *))onError;
@end

@implementation HttpClient

+ (void)request:(NSURLRequest *)request 
        success:(void (^)(NSData *, NSHTTPURLResponse *))onSuccess 
          error:(void (^)(NSError *, NSHTTPURLResponse *))onError 
{
  dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_async(q, ^{
    NSHTTPURLResponse *response = nil;
    NSError       *error    = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                         returningResponse:&response
                                                     error:&error];
    if (error) {
      onError(error, response);
    }
    else {
      onSuccess(data, response);
    }
  });
}
@end


#pragma mark - PolylineView
@interface TTTViewController()

@property (strong, nonatomic) IBOutlet MKMapView *mapView;
@property (strong, nonatomic) IBOutlet UITextField *fromField;
@property (strong, nonatomic) IBOutlet UITextField *toField;
@property (strong, nonatomic) IBOutlet UISegmentedControl *modeSegment;
@property (strong, nonatomic) IBOutlet UISegmentedControl *sourceSegment;
@property (strong, nonatomic) IBOutlet UIButton *renderButton; 
@property (strong, nonatomic) IBOutlet UILabel *descriptionLabel;

- (IBAction)render:(id)sender;

- (void)_enableUI:(BOOL)yesno;
- (NSArray *)_decodePolyline:(NSString *)encoded;
- (NSString *)_urlEncodeString:(NSString *)stringToEncode;

@end


@implementation TTTViewController

@synthesize  mapView, fromField, toField, modeSegment, sourceSegment, renderButton, descriptionLabel;

#pragma mark - Map view delegate
- (MKOverlayView *)mapView:(MKMapView *)_mapView viewForOverlay:(id<MKOverlay>)overlay 
{
  MKPolylineView *view = [[MKPolylineView alloc] initWithOverlay:overlay];
  view.strokeColor = [UIColor purpleColor];
  view.lineWidth = 5.0;
  
  return view;
}

#pragma mark - sample

/*
 http://code.google.com/intl/ja-JP/apis/maps/documentation/utilities/polylinealgorithm.html
 
 緯度と経度をエンコードする
 エンコード プロセスでは、一般的な base64 エンコーディング スキームを使用して 2 進数値を一連の ASCII 文字に変換します。これらの文字が適切に表示されるようにするため、エンコードされる値は、63（ASCII 文字の「?」）を加算してからASCII に変換されます。また、このアルゴリズムでは、各バイト グループの最下位ビットをチェックし、指定された地点の文字がさらに続いているかどうかを確認します。最下位ビットが 1 の場合、その地点はまだ完全なものではなく、その後にもデータが続いています。
 データ量を節約するために、各地点には直前の地点からのオフセットのみが格納されます（最初の地点は除く）。緯度と経度は符号付きの値なので、地点はすべて符号付き整数として base64 にエンコードされます。ポリラインのエンコード形式では、緯度と経度を表す 2 つの座標を妥当な精度で表す必要があります。最大経度（+/- 180 度）を小数第 5 位までの精度（180.00000～-180.00000）で表す場合、32 ビットの符号付き 2 進整数値を必要とします。
 バックスラッシュ（\）は、文字列リテラル内でエスケープ文字として解釈されます。このような文字列をエンコードする場合は、文字列リテラル内のバックスラッシュをバックスラッシュ 2 個に変換する必要があります。
 このような符号付きの値をエンコードする手順は以下のとおりです。
 最初の符合付き値を取得します:
 1. -179.9832104
 2. 10 進値を取得して 1e5 で乗算すると、結果は丸められます:
 -17998321
 3. この 10 進値を 2 進値に変換します。負の値は2 進値に変換し、2 の補数を使用して算出して、1 を加える必要があることに注意してください。
 00000001 00010010 10100001 11110001
 11111110 11101101 01011110 00001110
 11111110 11101101 01011110 00001111
 4. 2 進値の 1 ビットを左にシフトします。
 11111101 11011010 10111100 00011110
 5. 元の 10 進値が負の場合は、このエンコーディング結果を反転します。
 00000010 00100101 01000011 11100001
 6. 2 進値を 5 ビット単位に分割します（右側から）。
 00001 00010 01010 10000 11111 00001
 7. 5 ビットの集合を逆の順序に並べ替えます。
 00001 11111 10000 01010 00010 00001
 8. 後続のビット集合が続く場合は、各値に 0x20 の論理和演算を行います。
 100001 111111 110000 101010 100010 000001
 9. 各値を 10 進値に変換します。
 33 63 48 42 34 1
 10. 各値に 63 を加算します。
 96 126 111 105 97 64
 11. 各値を対応する ASCII 文字に変換します。
 `~oia@
 
 実装参考：
 http://jeffreysambells.com/posts/2010/05/27/decoding-polylines-from-google-maps-direction-api-with-java/
 
 */
- (NSArray *)_decodePolyline:(NSString *)encoded
{
  NSMutableString *e = [[NSMutableString alloc] initWithCapacity:[encoded length]];  
  [e appendString:encoded];  
  [e replaceOccurrencesOfString:@"\\\\" withString:@"\\"  
                        options:NSLiteralSearch  
                          range:NSMakeRange(0, [encoded length])];  
  
  NSMutableArray *ret = [[NSMutableArray alloc] init];
  
  NSInteger index = 0;
  NSInteger len = [encoded length];
  NSInteger lat = 0, lng = 0;
  
  while (index < len) {
    NSInteger b, shift = 0, result = 0;
    do {
      b = [encoded characterAtIndex:(index++)] - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } 
    while (b >= 0x20);
    NSInteger dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;
    
    shift = 0;
    result = 0;
    do {
      b = [encoded characterAtIndex:(index++)] - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    NSInteger dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;
    
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:lat*1e-5 longitude:lng*1e-5];
    [ret addObject:loc];
  }
  return ret;
}

- (NSString *)_urlEncodeString:(NSString *)stringToEncode
{
  return (__bridge NSString *)CFURLCreateStringByAddingPercentEscapes(
                                                                      NULL,
                                                                      (__bridge CFStringRef)stringToEncode,
                                                                      NULL,
                                                                      (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                                                      kCFStringEncodingUTF8 );
}

- (NSArray *)_getSteps:routes
{
  
  NSArray *legs = [[routes objectAtIndex:0] objectForKey:@"legs"];
  if (legs == nil || [legs count] == 0) {
    return nil;
  }
  
  NSArray *steps = [[legs objectAtIndex:0] objectForKey:@"steps"];
  if (steps == nil || [steps count] == 0) {
    return nil;
  }
  
  NSMutableArray *ret = [[NSMutableArray alloc] init];
  for (NSDictionary *step in steps) {
    CGFloat lat = [[[step objectForKey:@"end_location"] objectForKey:@"lat"] floatValue];
    CGFloat lng = [[[step objectForKey:@"end_location"] objectForKey:@"lng"] floatValue];
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:lat longitude:lng];
    [ret addObject:loc];
  }
  return ret;
}

- (IBAction)render:(id)sender
{
  [self.fromField resignFirstResponder];
  [self.toField resignFirstResponder];
  [self.mapView removeOverlays:self.mapView.overlays];
  self.descriptionLabel.text = @"";
  
  [self _enableUI:NO];
  
  NSString *strURL = [NSString stringWithFormat:
                      @"http://maps.google.com/maps/api/directions/json?origin=%@&destination=%@&sensor=false&mode=%@", 
                      [self _urlEncodeString:self.fromField.text],
                      [self _urlEncodeString:self.toField.text],
                      self.modeSegment.selectedSegmentIndex == 0 ? @"walking" : @"driving"
                      ];
  
  NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:strURL]
                                       cachePolicy:NSURLRequestUseProtocolCachePolicy
                                   timeoutInterval:20];
  
  void (^onSuccess)(NSData *, NSHTTPURLResponse *) = ^(NSData *data, NSHTTPURLResponse *res) {
    if (data == nil) {
      return;
    }
    else {
      if ([res statusCode] >= 400) {
        self.descriptionLabel.text = [NSString stringWithFormat:@"Response: status code:<%d>",[ res statusCode]];
        return;
      }
      
      NSDictionary *res = [NSJSONSerialization JSONObjectWithData:data 
                                                          options:NSJSONReadingMutableContainers 
                                                            error:nil];
      
      if (!([[res objectForKey:@"status"] isEqualToString:@"OK"])) {
        return;
      }
      NSArray *routes = [res objectForKey:@"routes"];
      if (routes == nil || [routes count] == 0) {
        return;
      }
      
      NSString *polylineString = [[[routes objectAtIndex:0] objectForKey:@"overview_polyline"] objectForKey:@"points"];
      
      NSArray *locs;
      if (self.sourceSegment.selectedSegmentIndex) {
        locs = [self _decodePolyline:polylineString];
      }
      else {
        locs = [self _getSteps:routes];
      }
      
      NSInteger stepCount = [locs count];
      self.descriptionLabel.text = [NSString stringWithFormat:@"step count:<%d>", stepCount];
      CLLocationCoordinate2D coords[stepCount];
      CLLocationCoordinate2D *p = coords;
      
      for (CLLocation *loc in locs) {
        p->latitude = loc.coordinate.latitude, p->longitude = loc.coordinate.longitude;
        p++;
      }
      
      MKPolyline *line = [MKPolyline polylineWithCoordinates:coords count:stepCount];
      
      CLLocationCoordinate2D from = [[locs objectAtIndex:0] coordinate];
      CLLocationCoordinate2D to = [[locs objectAtIndex:stepCount-1] coordinate];
      CLLocationCoordinate2D center = CLLocationCoordinate2DMake((from.latitude+to.latitude)/2,
                                                                 (from.longitude+to.longitude)/2);
      CLLocationDegrees latDelta = fabs(from.latitude - to.latitude);
      CLLocationDegrees lngDelta = fabs(from.longitude - to.longitude);
      MKCoordinateSpan span = MKCoordinateSpanMake(latDelta,lngDelta);
      MKCoordinateRegion region = MKCoordinateRegionMake(center, span);
      
      dispatch_async(dispatch_get_main_queue(), ^{
        [self.mapView setRegion:region animated:YES];
        [self.mapView addOverlay:line];
        [self _enableUI:YES];
      });
    }  };
  void (^onError)(NSError *, NSHTTPURLResponse *) = ^(NSError *error, NSHTTPURLResponse *res) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self _enableUI:YES];
      self.descriptionLabel.text = [error description];
    });
  };
  [HttpClient request:req success:onSuccess error:onError];
}



- (void)_enableUI:(BOOL)yesno
{
  [self.toField setEnabled:yesno];
  [self.fromField setEnabled:yesno];
  [self.modeSegment setEnabled:yesno];
  [self.renderButton setEnabled:yesno];
}


- (void)didReceiveMemoryWarning
{
  [super didReceiveMemoryWarning];
  self.toField = nil;
  self.fromField = nil;
  self.modeSegment = nil;
  self.renderButton = nil;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
  [super viewDidLoad];
  [self.mapView setDelegate:self];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
  // Return YES for supported orientations
  return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
