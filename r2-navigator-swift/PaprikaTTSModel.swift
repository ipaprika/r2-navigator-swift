//
//  PaprikaTTSModel.swift
//  r2-navigator-swift
//
//  Created by Kofktu on 02/12/2018.
//  Copyright © 2018 Readium. All rights reserved.
//

import Foundation
import ObjectMapper
import AVFoundation

public enum PaprikaTTSEvent: String {
    case ready
    case current
    case finish
}

public class PaprikaTTSModel: NSObject, ImmutableMappable {
    
    let event: PaprikaTTSEvent
    let index: Int
    let text: String?
    
    typealias TTSFinishedHandler = () -> Void
    private var onFinishedHandler: TTSFinishedHandler?
    
    private lazy var speechSynthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    
    required public init(map: Map) throws {
        event = try map.value("event", using: EnumTransform<PaprikaTTSEvent>())
        index = try map.value("index")
        text = try? map.value("text")
    }
    
    // Ready 상태의 init
    override init() {
        event = .ready
        index = 0
        text = nil
        super.init()
    }
    
}

extension PaprikaTTSModel: AVSpeechSynthesizerDelegate {
    
    func execute(with completion: @escaping TTSFinishedHandler) {
        guard let text = text else {
            return
        }
        guard !speechSynthesizer.isSpeaking else {
            return
        }
        
        onFinishedHandler = completion
        speechSynthesizer.speak(text.utterance)
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinishedHandler?()
    }
    
}

fileprivate extension String {
    
    var utterance: AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: self)
//        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        return utterance
    }
    
}
