//
//  ResponsePipeline.swift
//
//  Copyright (c) 2016-present, LINE Corporation. All rights reserved.
//
//  You are hereby granted a non-exclusive, worldwide, royalty-free license to use,
//  copy and distribute this software in source code or binary form for use
//  in connection with the web services and APIs provided by LINE Corporation.
//
//  As with any software that integrates with the LINE Corporation platform, your use of this software
//  is subject to the LINE Developers Agreement [http://terms2.line.me/LINE_Developers_Agreement].
//  This copyright notice shall be included in all copies or substantial portions of the software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
//  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Foundation

// Use class protocol for easier Equatable conforming
protocol ResponsePipelineTerminator: class {
    func parse<T: Request>(request: T, data: Data) throws -> T.Response
}

// Use class protocol for easier Equatable conforming
protocol ResponsePipelineRedirector: class {
    func shouldApply<T: Request>(reqeust: T, data: Data, response: HTTPURLResponse) -> Bool
    func redirect<T: Request>(reqeust: T, data: Data, response: HTTPURLResponse, done closure: (ResponsePipelineRedirectorAction) throws -> Void) throws
}

enum ResponsePipelineRedirectorAction {
    case restart
    case restartWithout(ResponsePipeline)
    case stop(Error)
    case `continue`
}

enum ResponsePipeline {
    case terminator(ResponsePipelineTerminator)
    case redirector(ResponsePipelineRedirector)
}

extension ResponsePipeline: Equatable {
    static func == (lhs: ResponsePipeline, rhs: ResponsePipeline) -> Bool {
        switch (lhs, rhs) {
        case (.terminator(let l), .terminator(let r)): return l === r
        case (.redirector(let l), .redirector(let r)): return l === r
        default: return false
        }
    }
}

class ParsePipeline: ResponsePipelineTerminator {
    
    let parser: JSONDecoder
    
    init(_ parser: JSONDecoder) {
        self.parser = parser
    }
    
    func parse<T: Request>(request: T, data: Data) throws -> T.Response {
        return try parser.decode(T.Response.self, from: data)
    }
}

class RefreshTokenRedirector: ResponsePipelineRedirector {
    
    func shouldApply<T: Request>(reqeust: T, data: Data, response: HTTPURLResponse) -> Bool {
        return response.statusCode == 403
    }
    
    func redirect<T: Request>(reqeust: T, data: Data, response: HTTPURLResponse, done closure: (ResponsePipelineRedirectorAction) throws -> Void) throws {
        // Do refrest request here.
        try closure(.restartWithout(.redirector(self)))
    }
}

class BadHTTPStatusRedirector: ResponsePipelineRedirector {
    let valid: Range<Int>
    
    init(valid: Range<Int>) {
        self.valid = valid
    }
    
    func shouldApply<T: Request>(reqeust: T, data: Data, response: HTTPURLResponse) -> Bool {
        let code = response.statusCode
        return !valid.contains(code)
    }
    
    func redirect<T: Request>(reqeust: T, data: Data, response: HTTPURLResponse, done closure: (ResponsePipelineRedirectorAction) throws -> Void) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let error = try decoder.decode(APIError.self, from: data)
            try closure(.stop(
                LineSDKError.responseFailed(
                    reason: .invalidHTTPStatus(code: response.statusCode, error: error, body: data))
                )
            )
        } catch {
            try closure(.stop(
                LineSDKError.responseFailed(
                    reason: .invalidHTTPStatus(code: response.statusCode, error: nil, body: data))
                )
            )
        }
    }
}