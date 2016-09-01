import PackageDescription

let urls = ["https://github.com/PerfectlySoft/Perfect-HTTP.git"]

let package = Package(
	name: "PerfectHTTPServer",
	targets: [
		Target(name: "CHTTPParser", dependencies: []),
		Target(name: "PerfectHTTPServer", dependencies: ["CHTTPParser"])
	],
	dependencies: urls.map { .Package(url: $0, versions: Version(0,0,0)..<Version(10,0,0)) },
	exclude: []
)
