//
//  somnusWidgetBundle.swift
//  somnusWidget
//
//  Created by Ric Messier on 8/3/26.
//

import WidgetKit
import SwiftUI

@main
struct somnusWidgetBundle: WidgetBundle {
    var body: some Widget {
        somnusWidget()
        MealLogWidget()
    }
}
