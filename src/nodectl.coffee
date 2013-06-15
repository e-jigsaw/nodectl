# Compiler

coffee = require 'coffee-script'
stylus = require 'stylus'


# Variable

fs = require 'fs'
path = require 'path'
{print} = require 'util'
{spawn, exec} = require 'child_process'
cluster = require 'cluster'
crypto = require 'crypto'

shasum = (source) ->
  return crypto.createHash('sha1').update(source).digest 'hex'

mkdirp = require 'mkdirp'
uglify = require 'uglify-js'
sqwish = require 'sqwish'

PROJECT = path.resolve()

# Default Value

for dir, i in (path.resolve()).split '/'
  up = ''; up += '../' for j in Array(i)
  if fs.existsSync path.resolve up, 'package.json'
    packages = require path.resolve up, 'package.json'
    PROJECT = path.resolve up
    break

defaults = switch
  when fs.existsSync path.join PROJECT, '.nodectl.json'
    require path.join PROJECT, '.nodectl.json'
  else {}

noseinfo = require '../package.json'
packages or=
  name: 'unknown'
  version: 'unknown'
pidfiles = "../tmp/#{}.pid"

# Argument Parser
args = [].concat process.argv

action = 'start'
actions =
  main: defaults.main || packages.main || ''
  stop: no
  start: no
  clear: no
  reload: no
  status: no
  help: no
  version: no

options =
  port: defaults.port || packages.port || 3000
  env: defaults.env || packages.env || 'development'
  cluster: defaults.cluster || packages.cluster || require('os').cpus().length
  delay: defaults.cluster || packages.cluster || 250
  logpath: defaults.logpath || packages.logpath || null
  pidpath: defaults.pidpath || packages.pidpath || path.join (path.dirname process.mainModule.filename), '..', 'tmp'
  execmaster: defaults.execmaster || packages.execmaster || no
  nocolor: defaults.nocolor || packages.nocolor || no
  daemon: defaults.daemon || packages.daemon || no
  watch: defaults.watch || packages.watch || no
  assets: defaults.assets || packages.assets || null
  output: defaults.output || packages.output || null
  minify: defaults.minify || packages.minify || no

try
  args = [].concat process.argv
  args.shift()
  args.shift()
  while arg = args.shift()
    switch arg
      when 'stop'
        action = 'stop'
        actions.start = no
        actions.stop = yes
      when 'start'
        action = 'start'
        actions.start = yes
        actions.stop = no
      when 'restart'
        action = 'restart'
        actions.start = yes
        actions.stop = yes
      when 'force-clear', 'force_clear'
        action = 'force-clear'
        actions.start = no
        actions.stop = no
        actions.clear = yes
      when 'reload'
        action = 'reload'
        actions.reload = yes
      when 'status'
        action = 'status'
        actions.status = yes
      when '-p', '-port', '--port'
        options.port = parseInt args.shift(), 10
        throw (new Error "#{arg} [INT], port number") if isNaN options.port
      when '-e', '-env', '--env'
        options.env = args.shift()
      when '-c', '-cluster', '--cluster'
        options.cluster = parseInt args.shift(), 10
        throw (new Error "#{arg} [INT], number of fork children") if isNaN options.cluster
      when '-D', '-delay', '--delay'
        options.delay = parseInt args.shift(), 10
        throw (new Error "#{arg} [INT], reload delay time (ms)") if isNaN options.delay
      when '-l', '-logpath', '--logpath'
        options.logpath = args.shift()
      when '-P', '-pidpath', '--pidpath'
        options.pidpath = args.shift()
      when '-x', '-execmaster', '--execmaster'
        options.execmaster = args.shift()
      when '-n', '-nocolor', '--nocolor'
        options.nocolor = yes
      when '-d', '-daemon', '--daemon'
        options.daemon = yes
      when '-w', '-watch', '--watch'
        options.watch = yes
      when '-a', '--assets'
        assets = path.resolve args.shift()
        options.assets = assets if fs.existsSync assets
      when '-o', '--output'
        output = path.resolve args.shift()
        options.output = output if fs.existsSync output
      when '-m', '--minify'
        options.minify = yes
      when '-v', '-version', '--version'
        actions.version = yes
      when '-h', '-help', '--help'
        actions.help = yes
      else
        actions.main = arg

catch e
  console.error e.message

process.env.PORT = options.port
process.env.NODE_ENV = options.env

if action is 'start'
  actions.start = yes

unless options.nocolor
  origin = {}

  for method in ['log', 'info', 'warn', 'error']
    do (method) ->
      origin[method] = console[method]
      console[method] = ->
        print switch method
          when 'log' then '\x1b[37m'
          when 'info' then '\x1b[34m'
          when 'warn' then '\x1b[33m'
          when 'error' then '\x1b[31m'
        origin[method].apply @, arguments
        print '\x1b[0m'

if actions.help
  console.log """
    #{noseinfo.name} version #{noseinfo.version}

    Target:
      #{packages.name} version #{packages.version}

    Usage:
      #{noseinfo.name} [action] [options] <program>

    Action:
      start        execute <program> (default action)
      stop         stop daemonized <program>
      restart      restart <program> with daemonize mode
      force-clear  force clear pid
      reload       apply edited javascript
      status       check <program> running or not

    Options:
      -p, --port [3000]        pass listening port with `process.env.PORT`
      -e, --env [development]  pass environment with `process.env.NODE_ENV`
      -c, --cluster []         concurrent process with cpu threads default

      -d, --daemon             daemonize process
      -w, --watch              watch code changes, auto reload programs
      -D, --delay [250]        delay time for re-fork child workers
      -n, --nocolor            stop colorize console

      -P, --pidpath [(auto)]   directory for pid files
      -l, --logpath []         directory for log files
      -x, --execmaster []      execute script on master process

      -a, --assets []          directory for assets watch and compile (js, coffee, css, styl)
      -o, --output []          directory for output js/css
      -m, --minify             minify compiled assets

      -v, --version            show version and exit
      -h, --help               show this message and exit

    Defaults from : `.nodectl.json` or `package.json`
    """
  process.exit 1

if actions.version
  console.log "#{noseinfo.name} version #{noseinfo.version}"
  process.exit 1

unless fs.existsSync options.pidpath
  fs.mkdirSync path.join options.pidpath

pidfile = path.join "#{options.pidpath}", "#{packages.name}.pid"
widfile = path.join "#{options.pidpath}", "#{packages.name}.wid"

if options.logpath
  unless fs.existsSync options.logpath
    fs.mkdirSync path.join options.logpath

stream = no
if options.logpath
  stream =
    master: fs.createWriteStream (path.join "#{options.logpath}", "master.log"), flags: 'a'
    masterErr: fs.createWriteStream (path.join "#{options.logpath}", "master.error.log"), flags: 'a'
    worker: fs.createWriteStream (path.join "#{options.logpath}", "worker.log"), flags: 'a'
    workerErr: fs.createWriteStream (path.join "#{options.logpath}", "worker.error.log"), flags: 'a'
else
  options.logpath = null

logger = (control, isMaster = no) ->
  if stream
    stdout = control.stdout.write
    stderr = control.stderr.write
    if isMaster
      control.stdout.write = ->
        stdout.apply @, arguments
        stream.master.write (arguments[0].replace /\x1b.*?m/g, '')
      control.stderr.write = ->
        stderr.apply @, arguments
        stream.masterErr.write (arguments[0].replace /\x1b.*?m/g, '')
    else
      control.stdout.write = ->
        stdout.apply @, arguments
        stream.worker.write (arguments[0].replace /\x1b.*?m/g, '')
      control.stderr.write = ->
        stderr.apply @, arguments
        stream.workerErr.write (arguments[0].replace /\x1b.*?m/g, '')

reloadAllChilds = (delay = 0) ->
  console.info '>>> Reload all childs.'
  if fs.existsSync widfile
    for wid, i in (fs.readFileSync widfile, 'utf-8').split ' '
      do (wid, i) ->
        setTimeout ->
          try
            process.kill wid, 'SIGINT'
          catch e
            console.error e.message
        , delay * i
  else
    console.error 'widfile missing.'

if actions.stop
  if cluster.isMaster
    if fs.existsSync pidfile
      pid = parseInt (fs.readFileSync pidfile, 'utf-8'), 10
      try
        process.kill pid, 'SIGINT'
        console.log "#{packages.name} stopped."
        fs.unlinkSync pidfile if fs.existsSync pidfile
        fs.unlinkSync widfile if fs.existsSync widfile
      catch e
        console.error "kill #{pid} failed: no such process."
    else
      console.error "#{packages.name} not running, pidfile not exists."

if actions.clear
  console.warn "clear pidfile for #{packages.name}."
  if fs.existsSync pidfile
    pid = parseInt (fs.readFileSync pidfile, 'utf-8'), 10
    fs.unlinkSync pidfile if fs.existsSync pidfile
    fs.unlinkSync widfile if fs.existsSync widfile
    try
      process.kill pid, 'SIGINT'
      console.log "#{packages.name} stopped."
    catch e
      console.error "kill #{pid} failed: no such process."

if actions.reload
  reloadAllChilds options.delay

if actions.status
  if fs.existsSync pidfile
    console.log "#{packages.name} running."
  else
    console.log "#{packages.name} not running."

if actions.start
  unless fs.existsSync actions.main
    console.error "`#{actions.main}` is not action, or not exists."
    process.exit 1

  if cluster.isMaster
    if fs.existsSync pidfile
      console.error "#{packages.name} already running."
      process.exit 1

    console.log "#{packages.name} version #{packages.version}"
    console.log "  listening port  ... #{options.port}"
    console.log "  environment     ... #{options.env}"
    console.log "  concurrent      ... #{options.cluster}"
    console.log "  daemonize       ... #{options.daemon}"
    console.log "  watchmode       ... #{options.watch}"
    console.log "  colorlize       ... #{!options.nocolor}"
    console.log "  releaseDelay    ... #{options.delay}"
    console.log "  execmaster      ... #{options.execmaster}"
    console.log "  assets          ... #{options.assets}"
    console.log "  output          ... #{options.output}"
    console.log "  minify          ... #{options.minify}"
    console.log "  logpath         ... #{options.logpath}"
    console.log "  pidfile         ... #{pidfile}\n"

    workers = []

    cluster.on 'fork', (worker) ->
      console.log "> Process forked ##{worker.process.pid}"

    cluster.on 'listening', (worker) ->
      console.info ">> State listening ##{worker.process.pid}"

    cluster.on 'exit', (worker) ->
      console.error "<< State exit ##{worker.process.pid}"
      console.info "> Refork process"
      for wid, i in workers
        if wid is worker.process.pid
          workers.splice i, 1
          workers.push cluster.fork().process.pid
      fs.writeFileSync widfile, workers.join ' '

    for i in [0...options.cluster]
      workers.push cluster.fork().process.pid
    fs.writeFileSync widfile, workers.join ' '

    isFile = (file) -> return fs.statSync(file).isFile()
    isDir  = (dir) -> return fs.statSync(dir).isDirectory()
    isCode = (file) -> /\.(coffee|js|json)$/.test path.extname file

    if options.execmaster
      options.execmaster = path.join process.cwd(), options.execmaster
      if !fs.existsSync options.execmaster
        console.error "-x --execmaster '#{options.execmaster}' not exists"
        process.exit 1
      if !isFile options.execmaster
        console.error "-x --execmaster '#{options.execmaster}' not file"
        process.exit 1
      if !(isCode options.execmaster)
        console.error "-x --execmaster '#{options.execmaster}' not script"
        process.exit 1

    if options.daemon
      unless process.env.__daemon
        args = [].concat process.argv
        args.shift()
        args.shift()
        process.env.__daemon = yes
        child = spawn process.mainModule.filename, args,
          stdio: 'ignore'
          env: process.env
          cwd: process.cwd()
          detached: yes
        child.unref()
        process.exit()

    findsByExtPattern = (dir, pattern) ->
      files = []
      for src in fs.readdirSync dir
        dst = path.join dir, src
        if (dst isnt 'node_modules') and (isDir dst)
          files = files.concat findsByExtPattern dst, pattern
        else unless /^\./.test src
          files.push path.resolve dst if pattern.test dst
      return files

    if options.watch
      for watch in findsByExtPattern '.', /\.(js|coffee|json)$/
        do (watch) ->
          unless (new RegExp "^#{options.assets}").test watch
            try
              fs.watch watch, ->
                console.info ">> Script updated."
                reloadAllChilds options.delay
            catch e
              console.error "Watch script #{watch} failed"

    if options.assets and options.output
      for watch in findsByExtPattern options.assets, /\.(js|coffee|styl)$/
        do (watch) ->
          console.log watch
          try
            fs.watch watch, ->
              try
                startTime = new Date()
                code = ''
                dest = path.join options.output, watch.replace options.assets, ''
                unless fs.exists path.dirname dest
                  mkdirp.sync path.dirname dest
                if /\.(js|coffee)$/.test watch
                  dest = path.join (path.dirname dest), (path.basename dest, path.extname dest) + '.js'
                  code = switch path.extname watch
                    when '.coffee'
                      coffee.compile fs.readFileSync watch, 'utf-8'
                    else
                      fs.readFileSync watch, 'utf-8'
                  if options.minify
                    temp = path.join '/tmp', shasum (Date.now()).toString()
                    fs.writeFileSync temp, code
                    {code} = uglify.minify temp
                    fs.unlinkSync temp
                if /\.(css|styl)$/.test watch
                  dest = path.join (path.dirname dest), (path.basename dest, path.extname dest) + '.css'
                  code = switch path.extname watch
                    when '.styl'
                      (stylus fs.readFileSync watch, 'utf-8')
                        .set('paths', [(path.resolve 'node_modules'), (options.assets)])
                        .render()
                    else
                      fs.readFileSync watch, 'utf-8'
                  if options.minify
                    code = sqwish.minify code
                if code
                  fs.writeFileSync dest, code, 'utf-8'
                  console.info ">> #{path.basename dest} compiled. (#{new Date() - startTime}ms)"
              catch e
                console.error ">> Compile failure."
                console.error e.message
          catch e
            console.error ">> Watch asset #{watch} failed"

    if options.execmaster
      require options.execmaster

    fs.writeFileSync pidfile, process.pid

    process.stdout.pipe(process.stdin)

    process.on 'exit', ->
      fs.unlinkSync pidfile if fs.existsSync pidfile
      fs.unlinkSync widfile if fs.existsSync widfile
    process.on 'SIGINT', -> process.exit 0

    logger process, yes

  else
    require path.join process.cwd(), actions.main
    logger process, no
