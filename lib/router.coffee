_path = require 'path'
_fs = require 'fs'
_less = require 'less'
_data = require './data'
_coffee = require 'coffee-script'
_url = require 'url'
_handlebars = require 'handlebars'
_async = require 'async'
_mime = require 'mime'

_hookHost = require './plugin/host'
_hooks = require './plugin/hooks'
_common = require './common'
_template = require './compiler/template'
_script = require './compiler/script'
_css = require './compiler/css'
_compiler = require './compiler'

#如果文件存在，则直接响应这个文件
responseFileIfExists = (file, res)->
	#如果html文件存在，则直接输出
	if _fs.existsSync file
		res.sendfile file
		return true

#响应纯内容数据
responseContent = (content, mime, req, res, next)->
  data =
    content: content
    mime: mime
    response: res
    request: req
    next: next
    stop: false

  _hookHost.triggerHook _hooks.route.willResponse, data, (err)->
    return if  data.stop
    res.type data.mime if data.mime
    res.end data.content


#统一处理响应
response = (source, route, options, req, res, next)->
  #对于css/html/js，先检查文件是否存在，如果文件存在，则直接返回
  return if /\.(html|htm|js|css)^/i.test(source) and responseFileIfExists(source, res)

  #交给编译器
  _compiler.execute route.compiler, source, options, (err, content)->
    #编译发生错误
    return response500 req, res, next, JSON.stringify(err) if err
    #没有编译成功，可能是文件格式没有匹配或者其它原因
    return responseStatic(source, req, res, next) if content is false
    responseContent content, route.mime, req, res, next

###
#请求html文件
responseHTML = (file, pluginData, req, res, next)->
  #不存在这个文件，则读取模板
  hbsFile = file.replace(/\.(html)|(html)$/i, '.hbs')
  #没有这个模板文件，返回404错误
  if not _fs.existsSync hbsFile
    console.log "HTML或者hbs文件没找到->#{file}".red
    return next()

  content = _template.render hbsFile, pluginData
  responseContent content, _mime.lookup('html'), req, res, next

#请求css，如果是less则编译
responseCSS = (file, req, res, next)->
  #不存在这个css，则渲染less
  lessFile = _common.replaceExt file, '.less'
  #如果不存在这个文件，则交到下一个路由
  if not _fs.existsSync lessFile
    console.log "CSS或Less无法找到->#{file}".red
    return next()

  _css.render lessFile, (err, css)->
    #编译发生错误
    return response500 req, res, next, JSON.stringify(err) if err
    responseContent css, _mime.lookup('css'), req, res, next

#响应js
responseJS = (file, req, res, next)->
  #如果没有找到，则考虑编译coffee
  coffeeFile = _common.replaceExt file, '.coffee'
  #如果不存在这个文件，则交到下一个路由
  if not _fs.existsSync coffeeFile
    console.log "Coffee或JS无法找到->#{file}".red
    return next()

  content =  _script.compile coffeeFile
  responseContent content, _mime.lookup('js'), req, res, next
###

#响应文件夹列表
responseDirectory = (path, req, res, next)->
  #兼容旧版的template目录
  if _common.config.compatibleModel
    dir = _path.join _common.getTemplateDir(), path
  else
    dir = _path.join _common.options.workbench, path

  return next() if not _fs.existsSync dir
  return next() if not _fs.statSync(dir).isDirectory()

  files = []
  content = null
  _fs.readdirSync(dir).forEach (filename)->
    item =
      filename: filename
      url: path + filename

    #只有silky项目，才会将hbs的扩展名改为html
    item.url = item.url.replace('.hbs', '.html') if _common.isSilkyProject()

    fullPath = _path.join dir, filename
    stat = _fs.statSync fullPath

    #如果是文件夹，在后台加上/
    item.url += '/?dir=true' if stat.isDirectory()
    files.push item

  queue = []
  #触发hook
  queue.push(
    (done)->
      data =
        files: files
        response: res
        request: req
        next: next
        directory: dir
        stop: false

      _hookHost.triggerHook _hooks.route.willPrepareDirectory, data, (err)->
        files = data.files
        done data.stop
  )

  #根据模板响应数据
  queue.push(
    (done)->
      tempfile = _path.join __dirname, './client/file_viewer.hbs'
      templateFn = _handlebars.compile _common.readFile(tempfile)
      data = files: files
      content = templateFn data
      done null
  )

  #触发hook
  queue.push(
    (done)->
      data =
        content: content
        response: res
        request: req
        next: next
        directory: dir

      _hookHost.triggerHook _hooks.route.didPrepareDirectory, data, (err)->
        content = data.content
        done null
  )

  _async.waterfall queue, (err)->
    return err if err
    res.end content

#请求其它静态资源，直接输入出
responseStatic = (realpath, req, res, next)->
  #查找文件是否存在
  return next() if not _fs.existsSync realpath
  res.sendfile realpath

#找不到
response404 = (req, res, next)->
	res.statusCode = 404
	res.end('404 Not Found')

#服务器错误
response500 = (req, res, next, message)->
	res.statusCode = 500
	res.end(message || '500 Error')

#获路由的物理路径
getRouteRealPath = (route)->
  #html且兼容旧版的template目录，则使用template的目录，新版本不需要template目录
  rootDir = if _common.config.compatibleModel and route.type is 'html'
    _common.getTemplateDir()
  else
    _common.options.workbench

  #物理文件的路径
  route.realpath = _path.join rootDir, route.url
  route


#处理用户自定义的路由
routeRewrite = (origin)->
  route =
    url: origin
    rule: null
    type: 'other'

  for rule in _common.config.routers
    continue if not rule.path.test(origin)
    route.url = origin.replace rule.path, rule.to
    route.rule = rule
    break if not rule.next

  console.log "#{origin} -> #{route.url}".green if route.url isnt origin

  #根据url判断类型
  route.type = _common.detectFileType(route.url)
  #探测出mime的类型
  route.mime = _mime.lookup(route.url)
  #默认的编译器名称
  route.compiler = _common.config.compiler[route.type] || route.type
  #获取真实的物理路径
  getRouteRealPath route

module.exports = (app)->
  #silky的文件引用
  app.get "/__/:file", (req, res, next)->
    file = _path.join(__dirname, 'client', req.params.file)
    res.sendfile file

  #匹配所有
  app.get "*", (req, res, next)->
    url = _url.parse(req.url)
    route = routeRewrite url.pathname
    #强制指定为目录
    isDir = Boolean(req.query.dir)

    data =
      request: req
      response: res
      next: next
      stop: false
      route: route
      pluginData: null

    #路由处理前的hook
    _hookHost.triggerHook _hooks.route.didRequest, data, (err)->
      #阻止路由的响应
      return if data.stop

      realpath = data.route.realpath

      #响应目录
      return responseDirectory(realpath, req, res, next) if isDir or data.route.type is 'dir'

      #非silky项目强制返回静态文件，规则要求直接返回静态文件
      if not _common.isSilkyProject() or data.route.rule?.static
        return responseStatic(realpath, req, res, next)

      options =
        pluginData: data.pluginData

      response realpath, data.route, options, req, res, next