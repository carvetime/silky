module.exports =
  plugin:
    #执行某个产品，一般用于插件被执行一次
    run: 'plugin:run'
  #路由的hook
  route:
    #路由找不到文件的时候会调用
    notFound: 'route:notFound'
    #启动路由的时候调用
    initial: 'route:initial'
    #已经收到了http请求
    didRequest: 'route:didRequest'
    #将要准备目录的时候，用于获取目录
    willPrepareDirectory: 'route:willPrepareDirectory'
    #目录已经准备好
    didPrepareDirectory: 'route:didPrepareDirectory'
#    willCompile: 'route:willCompile'      #将要编译less/coffee/hbs
#    didCompile: 'route:didCompile'        #完成编译less/coffee/hbs
    #所有数据已经处理好，将要响应数据
    willResponse: 'route:willResponse'    #将要响应
  #构建时的hook
  build:
    initial: 'build:initial'
    willCompress: 'build:willCompress'
    didCompress: 'build:didCompress'
    willBuild: 'build:willBuild'
    didBuild: 'build:didBuild'
    willCompile: 'build:willCompile'
    didCompile: 'build:didCompile'
    willProcess: 'build:willProcess'   #预处理文件或者文件夹，复制或者编译(仅限于coffee/less/handlebars)
    didProcess: 'build:didProcess'     #预处理结束
    willMake: 'build:willMake'
    didMake: 'build:didMake'

#https://github.com/wvv8oo/wvv8oo-blog.git