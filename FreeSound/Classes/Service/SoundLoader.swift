//
//  SoundLoader.swift
//  FreeSound
//
//  Created by Anton Shcherba on 5/5/16.
//  Copyright © 2016 Anton Shcherba. All rights reserved.
//

import Foundation
import SwiftyJSON
import OAuthSwift
import CoreData
import RxSwift
import RxCocoa

fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}

enum SortParameter: String {
    case relevance = "score"
    case duration = "duration_asc"
    case rating = "rating_desc"
    case downloads = "downloads_desc"
}

enum FilterParameter: String {
    case username = "username"
    case tag = "tag"
    case description = "description"
    case comment = "comment"
}

func getParamsString(params: [String: String]) -> String {
        var strings:[String] = []
        
        for (param,value) in params {
            strings.append(param+"="+value)
        }

        return strings.joined(separator: "&").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
}

class SoundLoader {
    
    fileprivate let resourcePath = ResourcePathManager()
    
    fileprivate let defaultSessionConfig = URLSessionConfiguration.default
    
    fileprivate var defaultSession: URLSession!
    
    fileprivate var searchResult: SearchResult?
    
    fileprivate let oauthClient: OAuthSwiftClient
    
    init() {
        oauthClient = OAuthSwiftClient(
            consumerKey: resourcePath.clientID,
            consumerSecret: resourcePath.clientSecret)
    }
    
    func loadSoundWithID(_ id: Int) -> Observable<SoundDetailInfo> {
        
        guard let url = URL(string: resourcePath.soundPathFor("\(id)")) else {
            return Observable.error(SomeError.wrongData)
        }

        let request = RequestBuilder.create(request: SoundInstanceRequest(id: id))
        
        defaultSession = URLSession(configuration: defaultSessionConfig,
                                      delegate: nil,
                                      delegateQueue: OperationQueue.main)
        
        return self.defaultSession.rx.response(request: request)
            .map({ (httpResponse, data) -> SoundDetailInfo in
                if httpResponse.statusCode == 200 {
                    if let soundDetailInfo = self.parseSoundDetailFrom(data) {
                        return soundDetailInfo
                    }
                    
                    throw SomeError.wrongData
                } else {
                    print("Server Error: \(httpResponse.statusCode)")
                    
                    let error = NetworkError.responseStatusError(status: httpResponse.statusCode,
                                                                 message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
                    throw error
                }
        })
    }
    
    
    
    func searchSoundWith(_ text: String, loadedCount: Int = 0, handler: @escaping (_ sounds: [SoundInfo]) -> Void) {
        guard let url = URL(string: resourcePath.searchPathWith(text)) else {
            return
        }
        
        let request = URLRequest(url: url)
        
        defaultSession = URLSession(configuration: defaultSessionConfig,
                                      delegate: nil,
                                      delegateQueue: OperationQueue.main)
        
        
        let task = defaultSession.dataTask(with: request, completionHandler: {[unowned self] (data, response, error) in
            if error != nil {
                print("Error: \(error?.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let page = try! Page.init(data: data!)
                    
                    
                    let result = SearchResult()
                    let json = JSON(data: data!)
                    
                    result.configureWithJson(json)
                    print(page)
                    
                    handler(result.results as! [SoundInfo])
                } else {
                    print("Server Error: \(httpResponse.statusCode)")
                }
            } else {
                print("Error")
            }
        }) 
        task.resume()
    }
    
    func sounds(for user: User, loadedCount: Int = 0, handler: @escaping (_ sounds: [SoundInfo]) -> Void) {
        guard let url = URL(string: resourcePath.soundsPath(for: user)) else {
            return
        }
        
        let request = URLRequest(url: url)
        
        defaultSession = URLSession(configuration: defaultSessionConfig,
                                    delegate: nil,
                                    delegateQueue: OperationQueue.main)
        
        
        let task = defaultSession.dataTask(with: request, completionHandler: {[unowned self] (data, response, error) in
            if error != nil {
                print("Error: \(error?.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let result = SearchResult()
                    let json = JSON(data: data!)
                    
                    result.configureWithJson(json)
                    handler(result.results as! [SoundInfo])
                    
                } else {
                    print("Server Error: \(httpResponse.statusCode)")
                }
            } else {
                print("Error")
            }
        })
        task.resume()
    }
    
//    func searchSoundWith(_ text: String, loadedCount: Int = 0,
//                          sortParameter: SortParameter?,
//                          filterParameter: FilterParameter?,
//                          handler: @escaping (_ sounds: [SoundInfo]) -> Void) {
//        var text = text
//        var params: [String: String] = [:]
//
//        if let sortParameter = sortParameter {
//            params["sort"] = sortParameter.rawValue
//        }
//        if let filterParameter = filterParameter {
//            params["filter"] = filterParameter.rawValue + ":\(text)"
//            text = ""
//        }
//
//        guard let url = URL(string: resourcePath.searchPathWith(text, queryParams: params) /*+ getParamsString(params: params)*/) else {
//            return
//        }
//
//        let request = URLRequest(url: url)
//
//        defaultSession = URLSession(configuration: defaultSessionConfig,
//                                    delegate: nil,
//                                    delegateQueue: OperationQueue.main)
//
//
//        let task = defaultSession.dataTask(with: request, completionHandler: {[unowned self] (data, response, error) in
//            if error != nil {
//                print("Error: \(error?.localizedDescription)")
//                return
//            }
//
//            if let httpResponse = response as? HTTPURLResponse {
//                if httpResponse.statusCode == 200 {
//                    if let result = self.parseSearchResultFrom(data!, loadedCount: loadedCount) {
//                        handler(result.results as! [SoundInfo])
//                    }
//
//                } else {
//                    print("Server Error: \(httpResponse.statusCode)")
//                }
//            } else {
//                print("Error")
//            }
//        })
//        task.resume()
//    }

    func searchSoundWith(_ text: String, loadedCount: Int = 0,
                         sortParameter: SortParameter?,
                         filterParameter: FilterParameter?) -> Observable<[SoundInfo]> {
        
        defaultSession = URLSession(configuration: defaultSessionConfig,
                                    delegate: nil,
                                    delegateQueue: OperationQueue.main)
        
        let obs: Observable<SearchResult> = loadd(request: SearchRequest(query: text, filter: filterParameter, sort: sortParameter))
        
        return obs.map { $0.results as! [SoundInfo] }
    }
    
    func searchSoundWith(_ text: String, loadedCount: Int = 0,
                         sortParameter: SortParameter?,
                         filterParameter: FilterParameter?) -> Observable<[Result]> {
        
        defaultSession = URLSession(configuration: defaultSessionConfig,
                                    delegate: nil,
                                    delegateQueue: OperationQueue.main)
        
        //        let obs: Observable<SearchResult> = loadd(request: SearchRequest(query: text, filter: filterParameter, sort: sortParameter))
        
        let obs: Observable<Page> = loadd(request: SearchRequest(query: text, filter: filterParameter, sort: sortParameter))
        
        return obs.map { $0.results as! [Result] }
    }
    
    
    func loadUser(withName name: String, authRequired: Bool = false) -> Observable<User> {
        guard let url = URL(string: resourcePath.userPathFor(name)) else {
            return Observable.error(SomeError.wrongData)
        }

        return loadd(request: UserInstanceRequest(username: name))
    }
    
    func loadd<T:Parsable>(request: FRRequest) -> Observable<T> {
        let request = RequestBuilder.create(request: request)
        
        defaultSession = URLSession(configuration: defaultSessionConfig,
                                    delegate: nil,
                                    delegateQueue: OperationQueue.main)
        
        return self.defaultSession.rx.response(request: request)
            .map({ (httpResponse, data) -> T in
                if httpResponse.statusCode == 200 {
                    let parsed = T.init()
                    parsed.configureWithJson(JSON(data: data))
                    
                    return parsed
                } else {
                    print("Server Error: \(httpResponse.statusCode)")
                    
                    let error = NetworkError.responseStatusError(status: httpResponse.statusCode,
                                                                 message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
                    throw error
                }
            })
    }
    
    func loadd(request: FRRequest) -> Observable<Page> {
        let request = RequestBuilder.create(request: request)
        
        defaultSession = URLSession(configuration: defaultSessionConfig,
                                    delegate: nil,
                                    delegateQueue: OperationQueue.main)
        
        return self.defaultSession.rx.response(request: request)
            .map({ (httpResponse, data) -> Page in
                if httpResponse.statusCode == 200 {
    
                    let page = try! Page.init(data: data)
                    print(page)
                    print(page)
                    return page
                    
//                    let parsed = T.init()
//                    parsed.configureWithJson(JSON(data: data))
//
//                    return parsed
                } else {
                    print("Server Error: \(httpResponse.statusCode)")
                    
                    let error = NetworkError.responseStatusError(status: httpResponse.statusCode,
                                                                 message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
                    throw error
                }
            })
    }
    
    func parseSoundDetailFrom(_ data: Data) -> SoundDetailInfo? {
        let soundDetailJSON = JSON(data: data)
        
        let database = DatabaseManager()
        let detailInfo = database.newSoundDetailInfo
        detailInfo.configureWithJson(soundDetailJSON)
        
        return detailInfo
    }
    
    func stopLoading() {
        defaultSession?.getAllTasks { (tasks) in
            tasks.forEach { $0.cancel() }
        }
    }
}
