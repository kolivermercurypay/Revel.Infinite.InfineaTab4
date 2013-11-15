//
//  MercuryViewController.m
//  WebServices-InfineaTab4
//
//  Created by Kevin Oliver on 11/15/13.
//  Copyright (c) 2013 Kevin Oliver. All rights reserved.
//

#import "MercuryViewController.h"
#import "DTDevices.h"
#import "MercuryHelper.h"

@interface MercuryViewController ()

@property (strong, nonatomic) DTDevices *dtdev;

@end

@implementation MercuryViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    self.dtdev = [DTDevices sharedDevice];
    [self.dtdev addDelegate:self];
    [self.dtdev connect];
    
    self.activityLoading.hidden = true;
    self.activityLoading.color = [UIColor orangeColor];
    [self.activityLoading startAnimating];
    self.lblMessaging.hidden = true;
    self.lblMessaging.textColor = [UIColor orangeColor];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)btnProcessClick:(id)sender {
}

#pragma mark Infinite Peripheral Events

- (void)updateConnectionState:(int)state
{
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateStyle:NSDateFormatterLongStyle];
    
	switch (state) {
		case CONN_DISCONNECTED:
		case CONN_CONNECTING:
            self.lblConnectionStatus.text = @"(x) - device not connected";
            self.activityLoading.hidden = true;
            self.lblMessaging.hidden = true;
            break;
		case CONN_CONNECTED:
        {
            self.lblConnectionStatus.text =[NSString stringWithFormat:@"device connected [current firmware: %@]",self.dtdev.firmwareRevision];
            
            self.lblMessaging.hidden = false;
            self.lblMessaging.text = @"Swipe credit card to process transaction";
            
            //set the active encryption algorithm - MAGTEK, using DUKPT key 1
            NSDictionary *params=[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:KEY_EH_DUKPT_MASTER1],@"keyID", nil];
            [self.dtdev emsrSetEncryption:ALG_EH_MAGTEK params:params error:nil];
			break;
        }
	}
}

//linea connection state
-(void)connectionState:(int)state
{
    [self updateConnectionState:state];
}

//notification when card is read
-(void)magneticCardEncryptedData:(int)encryption tracks:(int)tracks data:(NSData *)data track1masked:(NSString *)track1masked track2masked:(NSString *)track2masked track3:(NSString *)track3
{
    NSMutableString *status=[NSMutableString string];
    if(tracks!=0)
    {
        //you can check here which tracks are read and discard the data if the requred ones are missing
        // for example:
        //if(!(tracks&2)) return; //bail out if track 2 is not read
    }
	
    if(encryption==ALG_EH_MAGTEK)
    {
        //find the tracks, turn to ascii hex the data
        int index=0;
        uint8_t *bytes=(uint8_t *)[data bytes];
        
        index++; //card encoding typeB
        index++; //track status
        int t1Len=bytes[index++]; //track 1 unencrypted length
        int t2Len=bytes[index++]; //track 2 unencrypted length
        int t3Len=bytes[index++]; //track 3 unencrypted length
        NSString *t1masked=[[NSString alloc] initWithBytes:&bytes[index] length:t1Len encoding:NSASCIIStringEncoding];
        index+=t1Len; //track 1 masked
        NSString *t2masked=[[NSString alloc] initWithBytes:&bytes[index] length:t2Len encoding:NSASCIIStringEncoding];
        index+=t2Len; //track 2 masked
        NSString *t3masked=[[NSString alloc] initWithBytes:&bytes[index] length:t3Len encoding:NSASCIIStringEncoding];
        index+=t3Len; //track 3 masked
        uint8_t *t1Encrypted=&bytes[index]; //encrypted track 1
        int t1EncLen=((t1Len+7)/8)*8; //calculated encrypted track length as unencrypted one padded to 8 bytes
        index+=t1EncLen;
        uint8_t *t2Encrypted=&bytes[index]; //encrypted track 2
        int t2EncLen=((t2Len+7)/8)*8; //calculated encrypted track length as unencrypted one padded to 8 bytes
        index+=t2EncLen;
        
        index+=20; //track1 sha1
        index+=20; //track2 sha1
        uint8_t *ksn=&bytes[index]; //dukpt serial number
        
        [status appendFormat:@"MAGTEK card format\n"];
        [status appendFormat:@"Track1: %@\n",t1masked];
        [status appendFormat:@"Track2: %@\n",t2masked];
        [status appendFormat:@"Track3: %@\n",t3masked];
        
        if(t2Len>0) {
            
            if ([self.dtdev msProcessFinancialCard:t1masked track2:t2masked]) {
                //if the card is a financial card, try sending to a processor for verification
                NSMutableDictionary *dictionaryReq = [NSMutableDictionary new];
                [dictionaryReq setObject:@"118725340908147" forKey:@"MerchantID"];
                [dictionaryReq setObject:@"Credit" forKey:@"TranType"];
                [dictionaryReq setObject:@"Sale" forKey:@"TranCode"];
                [dictionaryReq setObject:@"54321" forKey:@"InvoiceNo"];
                [dictionaryReq setObject:@"54321" forKey:@"RefNo"];
                [dictionaryReq setObject:@"Testing InfinitePeripherals" forKey:@"Memo"];
                // EncryptedFormat is always set to MagneSafe
                [dictionaryReq setObject:@"MagneSafe" forKey:@"EncryptedFormat"];
                // AccountSource set to Swiped if read from MSR
                [dictionaryReq setObject:@"Swiped" forKey:@"AccountSource"];
                // EncryptedBlock is the encrypted payload in 3DES DUKPT format
                [dictionaryReq setObject:[self toHexString:t2Encrypted length:t2EncLen space:false] forKey:@"EncryptedBlock"];
                // EncryptedKey is the Key Serial Number (KSN)
                [dictionaryReq setObject:[self toHexString:ksn length:10 space:false] forKey:@"EncryptedKey"];
                [dictionaryReq setObject:@"4.32" forKey:@"Purchase"];
                [dictionaryReq setObject:@"test" forKey:@"OperatorID"];
                [dictionaryReq setObject:@"OneTime" forKey:@"Frequency"];
                [dictionaryReq setObject:@"RecordNumberRequested" forKey:@"RecordNo"];
                [dictionaryReq setObject:@"Allow" forKey:@"PartialAuth"];
                
                MercuryHelper *mgh = [MercuryHelper new];
                mgh.delegate = self;
                [mgh transctionFromDictionary:dictionaryReq andPassword:@"xyz"];
                
                self.activityLoading.hidden = false;
                self.lblMessaging.text = @"Processing transaction";
            }
        }
        
    }
    
}

-(void) transactionDidFailWithError:(NSError *)error {
    self.activityLoading.hidden = true;
    self.lblMessaging.text = @"Swipe credit card to process transaction";
    [self displayAlert:@"Mercury Error!" message:error.localizedDescription];
}

-(void) transactionDidFinish:(NSDictionary *)result {
    [self.activityLoading stopAnimating];
    NSMutableString *message = [NSMutableString new];
    
    for (NSString *key in [result allKeys])
    {
        [message appendFormat:@"%@: %@;\n", key, [result objectForKey:key]];
    }
    
    self.activityLoading.hidden = true;
    self.lblMessaging.text = @"Swipe credit card to process transaction";
    [self displayAlert:@"Mercury Complete!" message:message];
}

-(NSString *)toHexString:(void *)data length:(int)length space:(bool)space {
	const char HEX[]="0123456789ABCDEF";
	char s[2000];
	
	int len=0;
	for(int i=0;i<length;i++)
	{
		s[len++]=HEX[((uint8_t *)data)[i]>>4];
		s[len++]=HEX[((uint8_t *)data)[i]&0x0f];
        if(space)
            s[len++]=' ';
	}
	s[len]=0;
	return [NSString stringWithCString:s encoding:NSASCIIStringEncoding];
}

-(void)displayAlert:(NSString *)title message:(NSString *)message
{
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil, nil];
	[alert show];
}



@end
