//
//  NanometersExtensionParameterAddresses.h
//  NanometersExtension
//
//  Created by hguandl on 2024/5/21.
//

#pragma once

#include <AudioToolbox/AUParameters.h>

#ifdef __cplusplus
namespace NanometersExtensionParameterAddress {
#endif

typedef NS_ENUM(AUParameterAddress, NanometersExtensionParameterAddress) {
    gain = 0
};

#ifdef __cplusplus
}
#endif
