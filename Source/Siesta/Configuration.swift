//
//  Configuration.swift
//  Siesta
//
//  Created by Paul on 2015/8/8.
//  Copyright © 2016 Bust Out Solutions. All rights reserved.
//

import Foundation

/**
  Options which control the behavior of a `Resource`.

  - SeeAlso: `Service.configure(...)`
*/
public struct Configuration
    {
    // MARK: General Resource Behavior

    /**
      Time before valid data is considered stale by `Resource.loadIfNeeded()`.

      The default is 30 seconds.

      - Note: This property is configured at the resource level, and does not depend on the HTTP method of any request.
        Siesta uses the value configured for GET; if you override this for other HTTP methods, Siesta will ignore it.
    */
    public var expirationTime: NSTimeInterval = 30

    /**
      Time `Resource.loadIfNeeded()` will wait before allowing a retry after a failed request.

      The default is 1 second.

      - Note: This property is configured at the resource level, and does not depend on the HTTP method of any request.
        Siesta uses the value configured for GET; if you override this for other HTTP methods, Siesta will ignore it.
    */
    public var retryTime: NSTimeInterval = 1

    // MARK: Request Handling

    /**
      Default request headers.

      - Note: `Resource.request(...)` accepts a `requestMutation` closure than can change the HTTP method of a request.
        If you override configuration based on HTTP method, then unlike other configuration properties, `headers`
        depends on the initially requested, _pre-mutation_ method of a request. All other configuration properties
        will depend on the _post-mutation_ request method.
    */
    public var headers: [String:String] = [:]

    /**
      Adds a closure to be called after a `Request` is created, but before it is started. Use this to globally observe
      requests, or wrap them in special behavior that is transparent to outside observers.

      You can add any number of decorators. Decorators are called in the order they were added, and each receives the
      request returns by the previous one.

      If the closure returns a different request than the one passed to it, then that request replaces the original one.
      In other words, a caller of `Service.request(...)` or `Service.load(...)` sees _only_ the request returned by the
      last decorator, not the originally created one.

      - Note: If a decorator returns a different request, but still retains the original one internally, then the
          original request is still started. However, if a decorator not only replaces but _discards_ the input request,
          then the upstream request is _never_ started. This means that a decorator may choose to prevent requests from
          ever reaching the network.

     - SeeAlso: `Request.chained(...)`
    */
    public mutating func decorateRequests(decorator: (Resource, Request) -> Request)
        { requestDecorators.append(decorator) }

    internal var requestDecorators: [(Resource, Request) -> Request] = []

    /**
      The sequence of transformations used to process server responses, optionally interspesed with cache(s) which may
      provide fast app startup & offline access.
    */
    public var pipeline = Pipeline()

    /**
      Interval at which request hooks & observers receive progress updates. This affects how frequently
      `Request.onProgress(_:)` and `ResourceObserver.resourceRequestProgress(_:progress:)` are called, and how often the
      `Request.progress` property (which is partially time-based) is updated.
    */
    public var progressReportingInterval: NSTimeInterval = 0.05

    // MARK: Creating Configurations

    /**
      Holds a mutable configuration while closures passed to `Service.configure(...)` modify it.

      The reason that method doesn’t just accept a closure with an `inout` param is that doing so requires a messy
      flavor of closure declaration that makes the API much harder to use:

          configure("/things/​*") { (inout config: Configuration) in config.retryTime = 1 }

      This wrapper class allows usage to instead look like:

          configure("/things/​*") { $0.config.retryTime = 1 }
    */
    public final class Builder
        {
        /// Mutable for modification while building a resource’s config.
        public var config: Configuration = Configuration()
        }
    }
