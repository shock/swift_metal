//
//  TextureManager.swift
//  MetalGemini
//
//  Created by Bill Doughty on 4/30/24.
//

import Foundation
import MetalKit

class TextureManager {
    private(set) var textureURLs: [URL] = []
    public private(set) var mtlTextures:[MTLTexture] = []
    var debug = true

    init() {    }
    
    // parses the shader file to look for a @texture declarations
    // which define which image files to load as shader textures
    // eg.
    //
    //    // @texture '../assets/images/wood2.jpg'
    //    // @texture "../assets/images/wood3.jpg"
    //
    // would load wood2.jpg and wood3.jpg using the relative URLs
    // from the shader file.  The order in which they are declared
    // determines the order in which they are passed to the shader
    // functions.
    // TODO: improve documentation.  Add unit tests.  Add type checking (vectors only)
    func loadTexturesFromShader(srcURL: URL, shaderSource: String) -> [URL]
    {
        print("TextureManager: loadTexturesFromShader() - starting on thread \(Thread.current)")

        let lines = shaderSource.components(separatedBy: "\n")

        let textureRegex = /\s*\/\/\s*@texture\s+['"]{1}([\w\.\/]+)['"]{1}/

        var texturePaths: [String] = []
        for line in lines {
            if let firstMatch = line.firstMatch(of: textureRegex) {
                texturePaths.append(String(firstMatch.1))
            }
        }
        
        if debug { print("TextureManager: \(texturePaths.count) textures declared")}
        if texturePaths.count == 0 { return [] }

        let shaderDir = srcURL.deletingLastPathComponent()

        textureURLs.removeAll()

        for filePath in texturePaths {
            let resolvedURL = appendPathToURL(directoryURL: shaderDir, relativePath: filePath)
            textureURLs.append( URL(fileURLWithPath: resolvedURL.path()) )
        }
        return textureURLs
    }

    private func appendPathToURL( directoryURL: URL, relativePath: String ) -> URL {
        // Split the relative path into components and process each one
        let pathComponents = relativePath.split(separator: "/")
        var finalURL = directoryURL

        for component in pathComponents {
            if component == ".." {
                // Move up in the directory structure
                finalURL = finalURL.deletingLastPathComponent()
            } else if component != "." {
                // Append the current component to the path
                finalURL = finalURL.appendingPathComponent(String(component))
            }
        }

        if debug { print(finalURL.path) }  // Output should be the absolute path
        return finalURL
    }
}
