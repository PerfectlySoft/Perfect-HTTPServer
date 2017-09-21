# Perfect-HTTPServer [简体中文](README.zh_CN.MD)

<p align="center">
    <a href="http://perfect.org/get-involved.html" target="_blank">
        <img src="http://perfect.org/assets/github/perfect_github_2_0_0.jpg" alt="Get Involed with Perfect!" width="854" />
    </a>
</p>

<p align="center">
    <a href="https://github.com/PerfectlySoft/Perfect" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_1_Star.jpg" alt="Star Perfect On Github" />
    </a>  
    <a href="http://stackoverflow.com/questions/tagged/perfect" target="_blank">
        <img src="http://www.perfect.org/github/perfect_gh_button_2_SO.jpg" alt="Stack Overflow" />
    </a>  
    <a href="https://twitter.com/perfectlysoft" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_3_twit.jpg" alt="Follow Perfect on Twitter" />
    </a>  
    <a href="http://perfect.ly" target="_blank">
        <img src="http://www.perfect.org/github/Perfect_GH_button_4_slack.jpg" alt="Join the Perfect Slack" />
    </a>
</p>

<p align="center">
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Swift-4.0-orange.svg?style=flat" alt="Swift 4.0">
    </a>
    <a href="https://developer.apple.com/swift/" target="_blank">
        <img src="https://img.shields.io/badge/Platforms-OS%20X%20%7C%20Linux%20-lightgray.svg?style=flat" alt="Platforms OS X | Linux">
    </a>
    <a href="http://perfect.org/licensing.html" target="_blank">
        <img src="https://img.shields.io/badge/License-Apache-lightgrey.svg?style=flat" alt="License Apache">
    </a>
    <a href="http://twitter.com/PerfectlySoft" target="_blank">
        <img src="https://img.shields.io/badge/Twitter-@PerfectlySoft-blue.svg?style=flat" alt="PerfectlySoft Twitter">
    </a>
    <a href="http://perfect.ly" target="_blank">
        <img src="http://perfect.ly/badge.svg" alt="Slack Status">
    </a>
</p>

HTTP Server for Perfect

This repository contains the main HTTP 1.1 &amp; HTTP/2 server.

If you are using this server for your Perfect Server-Side Swift project then this will be the main dependency for your project.

```swift
.Package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer.git", majorVersion: 3)
```

If you are starting out with Perfect look at the main [Perfect](https://github.com/PerfectlySoft/Perfect) repository for details.

If you are beginning a new project with Perfect look at the [PerfectTemplate](https://github.com/PerfectlySoft/PerfectTemplate) project for starter instructions.

When building on Linux, OpenSSL 1.0.2+ is required for this package. On Ubuntu 14 or some Debian distributions you will need to update your OpenSSL before this package will build.

### HTTP/2

As of version 2.2.6, experimental HTTP/2 server support is available but is disabled by default. To enable HTTP/2, add "alpnSupport" to your server's TLSConfiguration struct:

```swift
let securePort = 8181
let tls = TLSConfiguration(certPath: "my.cert.pem", 
						alpnSupport: [.http2, .http11])

try HTTPServer.launch(
	.secureServer(tls,
	              name: "servername",
	              port: securePort,
	              routes: secureRoutes))
```

This will enable HTTP/2 to be used over secure connections if the client supports it. If the client does not support HTTP/2 then the server will use HTTP 1.x. HTTP/2 support is only offered over secure connections. Setting the global `http2Debug` variable to true will have the HTTP/2 server print much debugging information to the console while in use.

Please contact us if you experience any problems or incompatibilities while experimenting with HTTP/2 support.

## QuickStart

Add the dependency to your Package.swift

`.Package(url:"https://github.com/PerfectlySoft/Perfect-HTTPServer.git", majorVersion: 3)`

In your app, launch one or more servers.
```
// start a single server serving static files
try HTTPServer.launch(name: "localhost", port: 8080, documentRoot: "/path/to/webroot")
 
// start two servers. have one serve static files and the other handle API requests
let apiRoutes = Route(method: .get, uri: "/foo/bar", handler: {
        req, resp in
        //do stuff
    })
try HTTPServer.launch(
    .server(name: "localhost", port: 8080, documentRoot:  "/path/to/webroot"),
    .server(name: "localhost", port: 8181, routes: [apiRoutes]))
 
// start a single server which handles API and static files
try HTTPServer.launch(name: "localhost", port: 8080, routes: [
    Route(method: .get, uri: "/foo/bar", handler: {
        req, resp in
        //do stuff
    }),
    Route(method: .get, uri: "/foo/bar", handler:
        HTTPHandler.staticFiles(documentRoot: "/path/to/webroot"))
    ])
 
let apiRoutes = Route(method: .get, uri: "/foo/bar", handler: {
        req, resp in
        //do stuff
    })
// start a secure server
try HTTPServer.launch(.secureServer(TLSConfiguration(certPath: "/path/to/cert"), name: "localhost", port: 8080, routes: [apiRoutes]))
```

## Documentation

For further information, please visit [perfect.org](http://www.perfect.org/docs/HTTPServer.html).

## Issues

We are transitioning to using JIRA for all bugs and support related issues, therefore the GitHub issues has been disabled.

If you find a mistake, bug, or any other helpful suggestion you'd like to make on the docs please head over to [http://jira.perfect.org:8080/servicedesk/customer/portal/1](http://jira.perfect.org:8080/servicedesk/customer/portal/1) and raise it.

A comprehensive list of open issues can be found at [http://jira.perfect.org:8080/projects/ISS/issues](http://jira.perfect.org:8080/projects/ISS/issues)

