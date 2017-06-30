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
        <img src="https://img.shields.io/badge/Swift-3.0-orange.svg?style=flat" alt="Swift 3.0">
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
.Package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer.git", majorVersion: 2)
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

The following will clone an empty starter project:
```swift
git clone https://github.com/PerfectlySoft/PerfectTemplate.git
cd PerfectTemplate
```
Verify the Package.swift file contains the dependency:
```swift
let package = Package(
 name: "PerfectTemplate",
 targets: [],
 dependencies: [
     .Package(url:"https://github.com/PerfectlySoft/Perfect-HTTPServer.git", majorVersion: 2)
    ]
)
```

The name in the Package object in your Package.swift file will be the executable name for your project.

Create the Xcode project:
```swift
swift package generate-xcodeproj
```

The Swift Package Manager will download the required dependencies into a Packages directory and build an appropriate Xcode Project file.

Open the generated PerfectTemplate.xcodeproj file in Xcode.

The project can now build in Xcode and start a server on localhost port 8181.

Important: When a dependancy has been added to the project, the Swift Package Manager must be invoked to generate a new Xcode project file. Be aware that any customizations that have been made to this file will be lost.

## Creating an HTTPServer and registering webroot

Open main.swift from the Sources directory and confirm the following code is in place:

verify import statements include 
```swift
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer
```
Create an instance of HTTPServer and add routes:
```swift
// Create HTTP server.
let server = HTTPServer()

// Register your own routes and handlers
var routes = Routes()
routes.add(method: .get, uri: "/", handler: {
		request, response in
		response.appendBody(string: "<html><title>Hello, world!</title><body>Hello, world!</body></html>")
		response.completed()
	}
)

// Add the routes to the server.
server.addRoutes(routes)
```

Verify server settings: 
```swift
// Set a listen port of 8181
server.serverPort = 8181

// Set a document root.
// This is optional. If you do not want to serve static content then do not set this.
// Setting the document root will automatically add a static file handler for the route /**
server.documentRoot = "./webroot"
```

Gather command line options and further configure the server.
Run the server with --help to see the list of supported arguments.
Command line arguments will supplant any of the values set above. 

The arguments.swift file provides handlers for command line arguments as well as the configureServer function. Call this to handle any CLI arguments before starting the server process.

```swift
configureServer(server)
```

This code block will launch the server. Remember that any command after server.start() will not be reached.

```swift
do {
	// Launch the HTTP server.
	try server.start()
    
} catch PerfectError.networkError(let err, let msg) {
	print("Network error thrown: \(err) \(msg)")
}
```

In Xcode, you will need to select the executable scheme before you launch the server. This selection will need to be redone each time you generate an Xcode project file from the command line. Set the working directory to be your Project directory by choosing Edit Scheme, select Run, and under Options, check use custom working directory, then choose the project root. Again, this will need to be updated anytime you regenerate your project file.

In Xcode choose run to build and run your server. Test by going to 0.0.0.0:8181 in your browser to see the Hello World message. The server will also serve any static files you place in the webroot directory.



=======
## Issues

We are transitioning to using JIRA for all bugs and support related issues, therefore the GitHub issues has been disabled.

If you find a mistake, bug, or any other helpful suggestion you'd like to make on the docs please head over to [http://jira.perfect.org:8080/servicedesk/customer/portal/1](http://jira.perfect.org:8080/servicedesk/customer/portal/1) and raise it.

A comprehensive list of open issues can be found at [http://jira.perfect.org:8080/projects/ISS/issues](http://jira.perfect.org:8080/projects/ISS/issues)

