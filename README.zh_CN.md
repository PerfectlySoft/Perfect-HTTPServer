# Perfect-HTTPServer 服务器[English](README.md)

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

Perfect软件框架：HTTP 1.1 服务器

本代码资源库包括了一个 HTTP 1.1 服务器，并包含了一些 HTTP 2.0 的基础支持。

如果您在使用 Perfect 开发 Swift Web服务器应用，则请将下列依存关系增加到您的 Package.swift 程序中：

``` swift
.Package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer.git", majorVersion: 2, minor: 0)
```

如果您刚刚开始使用 Perfect，请不妨先看一下官网主页 [Perfect](https://github.com/PerfectlySoft/Perfect)。

另外，PerfectTemplate是一个非常好的 HTTP 服务器模板项目，请查看这里：[PerfectTemplate](https://github.com/PerfectlySoft/PerfectTemplate)。

## 快速上手

请使用下列命令快速开始项目：

``` swift
git clone https://github.com/PerfectlySoft/PerfectTemplate.git
cd PerfectTemplate
```
然后请检查 Package.swift 中的依存关系：

``` swift
let package = Package(
 name: "PerfectTemplate",
 targets: [],
 dependencies: [
     .Package(url:"https://github.com/PerfectlySoft/Perfect-HTTPServer.git", majorVersion: 2, minor: 0)
    ]
)
```

Package.swift 文件中 package 对象的名字属性决定了最终项目的可执行目标。

创建 Xcode 项目：
``` swift
swift package generate-xcodeproj
```

SPM 软件包管理器会下载所有依存关系并创建为一个 Xcode 工程文件。

创建完成之后，您可以用 Xcode 打开这个名为 PerfectTemplate.xcodeproj 的工程文件。

打开之后即可编译并运行服务器，端口为 8181.

注意：如果您修改了Package.swift文件，必须重新运行``` swift package generate-xcodeproj ```命令，否则可能无法在Xcode中编译；而之前在Xcode中修改的项目配置都会被覆盖。

## 创建 HTTP 服务器并注册 webroot 根目录

打开 main.swift 并进行如下修改：

注意 ``` import ``` 语句，用于引用函数库

``` swift
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer
```

创建 HTTP 实例并增加路由：

``` swift
// 创建 HTTP 服务器
let server = HTTPServer()

// 注册路由并登记路由处理句柄
var routes = Routes()
routes.add(method: .get, uri: "/", handler: {
		request, response in
		response.appendBody(string: "<html><head><meta http-equiv='content-type' content='text/html;charset=utf-8'><title>你好，世界！</title></head><body>你好，世界！</body></html>")
		response.completed()
	}
)

// 将路由信息写入服务器
server.addRoutes(routes)
```

检查服务器配置：
``` swift
// 设置监听端口为8181
server.serverPort = 8181

// 设置文档根目录
// 这是可选的，如果您有静态文件要使用，请按照下列步骤编程：
// 静态文件设置完成后会将所有默认路由通配符 /** 都指向静态文件 
server.documentRoot = "./webroot"
```

从命令行和配置文件中配置服务器
从服务器运行 --help 选项就可以看到受支持的配置清单。
您可以根据需要自行决定配置的内容。

配置文件 arguments.swift 和命令行的作用是一样的。在真正启动服务器之前，请调用下面的代码。

``` swift
configureServer(server)
```

下列操作会阻塞服务器进程。请注意 ``` server.start() ```之后的任何程序都是无法执行的。
``` swift
do {
	// 启动 HTTP 服务器
	try server.start()
    
} catch PerfectError.networkError(let err, let msg) {
	print("网络异常： \(err) \(msg)")
}
```

在 Xcode 中，请在运行服务器之前选择可执行文件的运行方式（executable scheme），而且这个选择操作在每次您从命令行生成 Xcode 项目时都必须执行。选择运行方式之后，还需要选择工作目录，并将工作目录设置为项目根目录，否则服务器无法正确调用上面的文档根目录。请注意每次从命令行生成 Xcode 项目后，这些操作都需要重新执行一遍。

上述设置完成之后就可以编译并运行服务器了。用浏览器测试 ```http://0.0.0.0:8181``` 应该可以看到结果。服务器还支持您的静态文件用作页面。



=======
## 问题汇报

我们现在正在转移至 JIRA 工作流处理系统，因此 github 上的问题汇报功能就被关闭了。

如果您有任何意见或建议，请在我们的JIRA管理平台上报告 [http://jira.perfect.org:8080/servicedesk/customer/portal/1](http://jira.perfect.org:8080/servicedesk/customer/portal/1)。

目前本项目详细的问题清单请参考 [http://jira.perfect.org:8080/projects/ISS/issues](http://jira.perfect.org:8080/projects/ISS/issues)

