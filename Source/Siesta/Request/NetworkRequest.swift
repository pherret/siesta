//
//  NetworkRequest.swift
//  Siesta
//
//  Created by Paul on 2015/12/15.
//  Copyright © 2016 Bust Out Solutions. All rights reserved.
//

import Foundation

internal final class NetworkRequest: RequestWithDefaultCallbacks, CustomDebugStringConvertible
    {
    // Basic metadata
    private let resource: Resource
    private let requestDescription: String
    internal var config: Configuration
        { return resource.configuration(forRequest: nsreq) }

    // Networking
    private let requestBuilder: Void -> NSURLRequest
    private let nsreq: NSURLRequest
    internal var networking: RequestNetworking?  // present only after start()
    internal var underlyingNetworkRequestCompleted = false  // so tests can wait for it to finish

    // Progress
    private var progressTracker: ProgressTracker
    var progress: Double
        { return progressTracker.progress }

    // Result
    private var responseCallbacks = CallbackGroup<ResponseInfo>()
    private var wasCancelled: Bool = false
    var isCompleted: Bool
        {
        dispatch_assert_main_queue()
        return responseCallbacks.completedValue != nil
        }

    // MARK: Managing request

    init(resource: Resource, requestBuilder: Void -> NSURLRequest)
        {
        self.resource = resource
        self.requestBuilder = requestBuilder  // for repeated()
        self.nsreq = requestBuilder()
        self.requestDescription = debugStr([nsreq.HTTPMethod, nsreq.URL])

        progressTracker = ProgressTracker(isGet: nsreq.HTTPMethod == "GET")
        }

    func start()
        {
        dispatch_assert_main_queue()

        guard self.networking == nil else
            { fatalError("NetworkRequest.start() called twice") }

        guard !wasCancelled else
            {
            debugLog(.Network, [requestDescription, "will not start because it was already cancelled"])
            underlyingNetworkRequestCompleted = true
            return
            }

        debugLog(.Network, [requestDescription])

        let networking = resource.service.networkingProvider.startRequest(nsreq)
            {
            res, data, err in
            dispatch_async(dispatch_get_main_queue())
                { self.responseReceived(nsres: res, body: data, error: err) }
            }
        self.networking = networking

        progressTracker.start(
            networking,
            reportingInterval: config.progressReportingInterval)
        }

    func cancel()
        {
        dispatch_assert_main_queue()

        guard !isCompleted else
            {
            debugLog(.Network, ["cancel() called but request already completed:", requestDescription])
            return
            }

        debugLog(.Network, ["Cancelled", requestDescription])

        networking?.cancel()

        // Prevent start() from have having any effect if it hasn't been called yet
        wasCancelled = true

        broadcastResponse(ResponseInfo.cancellation)
        }

    func repeated() -> Request
        {
        let req = NetworkRequest(resource: resource, requestBuilder: requestBuilder)
        req.start()
        return req
        }

    // MARK: Callbacks

    internal func addResponseCallback(callback: ResponseCallback) -> Self
        {
        responseCallbacks.addCallback(callback)
        return self
        }

    func onProgress(callback: Double -> Void) -> Self
        {
        progressTracker.callbacks.addCallback(callback)
        return self
        }

    // MARK: Response handling

    // Entry point for response handling. Triggered by RequestNetworking completion callback.
    private func responseReceived(nsres nsres: NSHTTPURLResponse?, body: NSData?, error: ErrorType?)
        {
        dispatch_assert_main_queue()

        underlyingNetworkRequestCompleted = true

        debugLog(.Network, [nsres?.statusCode ?? error, "←", requestDescription])
        debugLog(.NetworkDetails, ["Raw response headers:", nsres?.allHeaderFields])
        debugLog(.NetworkDetails, ["Raw response body:", body?.length ?? 0, "bytes"])

        let responseInfo = interpretResponse(nsres, body, error)

        if shouldIgnoreResponse(responseInfo.response)
            { return }

        transformResponse(responseInfo, then: broadcastResponse)
        }

    private func interpretResponse(nsres: NSHTTPURLResponse?, _ body: NSData?, _ error: ErrorType?)
        -> ResponseInfo
        {
        if nsres?.statusCode >= 400 || error != nil
            {
            return ResponseInfo(response: .Failure(Error(response:nsres, content: body, cause: error)))
            }
        else if nsres?.statusCode == 304
            {
            if let entity = resource.latestData
                {
                return ResponseInfo(response: .Success(entity), isNew: false)
                }
            else
                {
                return ResponseInfo(
                    response: .Failure(Error(
                        userMessage: NSLocalizedString("No data available", comment: "userMessage"),
                        cause: Error.Cause.NoLocalDataFor304())))
                }
            }
        else
            {
            return ResponseInfo(response: .Success(Entity(response: nsres, content: body ?? NSData())))
            }
        }

    private func transformResponse(rawInfo: ResponseInfo, then afterTransformation: ResponseInfo -> Void)
        {
        let processor = config.pipeline.makeProcessor(rawInfo.response, resource: resource)

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0))
            {
            let processedInfo =
                rawInfo.isNew
                    ? ResponseInfo(response: processor(), isNew: true)
                    : rawInfo

            dispatch_async(dispatch_get_main_queue())
                { afterTransformation(processedInfo) }
            }
        }

    private func broadcastResponse(newInfo: ResponseInfo)
        {
        dispatch_assert_main_queue()

        if shouldIgnoreResponse(newInfo.response)
            { return }

        debugLog(.NetworkDetails, ["Response after transformer pipeline:", newInfo.isNew ? " (new data)" : " (data unchanged)", newInfo.response.dump()])

        progressTracker.complete()

        responseCallbacks.notifyOfCompletion(newInfo)
        }

    private func shouldIgnoreResponse(newResponse: Response) -> Bool
        {
        guard let existingResponse = responseCallbacks.completedValue?.response else
            { return false }

        // We already received a response; don't broadcast another one.

        if !existingResponse.isCancellation
            {
            debugLog(.Network,
                [
                "WARNING: Received response for request that was already completed:", requestDescription,
                "This may indicate a bug in the NetworkingProvider you are using, or in Siesta.",
                "Please file a bug report: https://github.com/bustoutsolutions/siesta/issues/new",
                "\n    Previously received:", existingResponse,
                "\n    New response:", newResponse
                ])
            }
        else if !newResponse.isCancellation
            {
            // Sometimes the network layer sends a cancellation error. That’s not of interest if we already knew
            // we were cancelled. If we received any other response after cancellation, log that we ignored it.

            debugLog(.NetworkDetails,
                [
                "Received response, but request was already cancelled:", requestDescription,
                "\n    New response:", newResponse
                ])
            }

        return true
        }

    // MARK: Debug

    var debugDescription: String
        {
        return "Siesta.Request:"
            + String(ObjectIdentifier(self).uintValue, radix: 16)
            + "("
            + requestDescription
            + ")"
        }
    }
