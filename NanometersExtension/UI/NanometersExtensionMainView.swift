//
//  NanometersExtensionMainView.swift
//  NanometersExtension
//
//  Created by hguandl on 2024/5/21.
//

import SwiftUI

struct NanometersExtensionMainView: View {
    var parameterTree: ObservableAUParameterGroup
    
    var body: some View {
        ParameterSlider(param: parameterTree.global.gain)
    }
}
