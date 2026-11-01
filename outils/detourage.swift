// Détourage automatique avec Vision (sujet au premier plan), sur la machine, sans réseau.
// Usage : detourage <entrée> <sortie.png>   — code 2 : aucun sujet trouvé.
import CoreImage
import Foundation
import Vision

let args = CommandLine.arguments
guard args.count == 3, let source = CIImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("usage: detourage <entrée> <sortie.png>\n".data(using: .utf8)!)
    exit(1)
}
let requete = VNGenerateForegroundInstanceMaskRequest()
let gestion = VNImageRequestHandler(ciImage: source)
do {
    try gestion.perform([requete])
    guard let res = requete.results?.first, !res.allInstances.isEmpty else { exit(2) }
    let tampon = try res.generateMaskedImage(ofInstances: res.allInstances, from: gestion,
                                             croppedToInstancesExtent: false)
    let image = CIImage(cvPixelBuffer: tampon)
    let ctx = CIContext()
    try ctx.writePNGRepresentation(of: image, to: URL(fileURLWithPath: args[2]),
                                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
} catch {
    FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
