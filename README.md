# Perfect-HTTPServer

HTTP 1.1 Server for Perfect

[![GitHub version](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-HTTPServer.svg)](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-HTTPServer)

This repository contains the main HTTP 1.1 server as well as the beginnings of the HTTP 2.0 support for the project.

If you are using this server for your Perfect Server-Side Swift project then this will be the main dependency for your project.

```swift
.Package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer.git", versions: Version(0,0,0)..<Version(10,0,0)
```

If you are starting out with Perfect look at the main [Perfect](https://github.com/PerfectlySoft/Perfect) repository for details.

If you are beginning a new project with Perfect look at the [PerfectTemplate](https://github.com/PerfectlySoft/PerfectTemplate) project for starter instructions.


## QuickStart

The following will clone an empty starter project:
```
git clone https://github.com/PerfectlySoft/PerfectTemplate.git
cd PerfectTemplate
```
Add to the Package.swift file the dependency:
```
let package = Package(
 name: "PerfectTemplate",
 targets: [],
 dependencies: [
     .Package(url:"https://github.com/PerfectlySoft/Perfect-HTTPServer.git", versions: Version(0,0,0)..<Version(10,0,0))
    ]
)
```
Create the Xcode project:
```
swift package generate-xcodeproj
```
Open the generated PerfectTemplate.xcodeproj file in Xcode.

The project will now build in Xcode and start a server on localhost port 8181.

Important: When a dependancy has been added to the project, the Swift Package Manager must be invoked to generate a new Xcode project file. Be aware that any customizations that have been made to this file will be lost.

## Creating an HTTPServer and registering webroot

Open main.swift from the Sources directory and edit according to the following instructions:

Update import statements to include 
```
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer
```
Create an instance of HTTPServer and add routes:
```
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
```
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
```
configureServer(server)
```
Launch the server. Remember that any command after server.start() will not be reached.
```
do {
	// Launch the HTTP server.
	try server.start()
    
} catch PerfectError.networkError(let err, let msg) {
	print("Network error thrown: \(err) \(msg)")
}
```
