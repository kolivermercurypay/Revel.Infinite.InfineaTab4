//
//  MercuryViewController.h
//  WebServices-InfineaTab4
//
//  Created by Kevin Oliver on 11/15/13.
//  Copyright (c) 2013 Kevin Oliver. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MercuryViewController : UIViewController

@property (weak, nonatomic) IBOutlet UILabel *lblConnectionStatus;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityLoading;
@property (weak, nonatomic) IBOutlet UILabel *lblMessaging;

@end
