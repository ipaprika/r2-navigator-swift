//
//  TTSBridgeModel.swift
//  r2-navigator-swift
//
//  Created by Kofktu on 02/12/2018.
//  Copyright © 2018 Readium. All rights reserved.
//

import Foundation
import ObjectMapper
import AVFoundation

public enum TTSBridgeEvent: String {
    case ready
    case current
    case finish
    case last
}

public typealias TTSBridgeModelDefaultHandler = () -> Void
public class TTSBridgeModel: NSObject, ImmutableMappable {
    
    public let event: TTSBridgeEvent
    public let index: Int
    public let text: String?
    public let isAutoPage: Bool
    
    required public init(map: Map) throws {
        event = try map.value("event", using: EnumTransform<TTSBridgeEvent>())
        index = (try? map.value("index")) ?? 0
        text = try? map.value("text")
        isAutoPage = (try? map.value("auto")) ?? false
    }
    
    // Ready 상태의 init
    override init() {
        event = .ready
        index = 0
        text = nil
        isAutoPage = false
        super.init()
    }
    
    init(event: TTSBridgeEvent) {
        self.event = event
        index = 0
        text = nil
        isAutoPage = false
        super.init()
    }
    
}
