//
//  NanometersExtensionAudioUnit.h
//  NanometersExtension
//
//  Created by hguandl on 2024/5/21.
//

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@interface NanometersExtensionAudioUnit : AUAudioUnit
- (void)setupParameterTree:(AUParameterTree *)parameterTree;
@end
