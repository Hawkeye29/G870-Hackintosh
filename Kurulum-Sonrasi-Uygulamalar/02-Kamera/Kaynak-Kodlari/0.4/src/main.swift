import Foundation
import CoreMediaIO
let source = QuantaProvider()
CMIOExtensionProvider.startService(provider:source.provider)
CFRunLoopRun()
