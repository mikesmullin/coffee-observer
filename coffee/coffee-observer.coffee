_             = require 'underscore'
async         = require 'async2'
path          = require 'path'
path.xplat    = (b,s)->path.join.apply null,if s then [b].concat s.split '/' else b.split '/' # makes *nix paths cross-platform compatible
growl         = require 'growl'
gaze          = require 'gaze'
child_process = require 'child_process'

module.exports = class CoffeeObserver
  constructor: ->
    @_titles      = {}
    @_color_index = 0
    @colors       = [ '\u001b[33m', '\u001b[34m', '\u001b[35m', '\u001b[36m', '\u001b[31m', '\u001b[32m', '\u001b[1m\u001b[33m', '\u001b[1m\u001b[34m', '\u001b[1m\u001b[35m', '\u001b[1m\u001b[36m', '\u001b[1m\u001b[31m', '\u001b[1m\u001b[32m' ]
    @node_child   = null

  notify: (title, msg, image, err, show) ->
    @_titles[title] = @_color_index++ if typeof @_titles[title] is 'undefined'
    msg = msg.stack if err and typeof msg is 'object' and typeof msg.stack isnt 'undefined'
    if show
      # growl is easy to flood since notifications display for a few seconds each
      _.throttle (->
        growl msg, image: path.xplat(__dirname, "/../images/#{image}.png"), title: title
      ) 3*1000
    msg = (''+msg).replace(/[\r\n]+$/, '')
    prefix = "#{@colors[@_titles[title]]}#{title}:\u001b[0m "
    console.log "#{prefix}#{msg.replace(/\n/g, "\n#{prefix}")}"
    "#{title}: #{msg}"

  child_process_loop: (collection, title, cwd, cmd, args, env) ->
    last_start = new Date()
    child = child_process.spawn cmd, args, cwd: cwd, env: env
    child.stdout.on 'data', (stdout) =>
      @notify title, ''+stdout, 'pending', false, false
    child.stderr.on 'data', (stderr) =>
      _.throttle (=> @notify title, ''+stderr, 'failure', true, true), 10*1000 # too many errors can stack up quickly and flood growl until notifications seem to never end (each notification displays avg 3 sec)
    child.on 'exit', (code) =>
      uptime = (new Date()-last_start)
      @notify title, "exit with code #{code or 0} (uptime: #{uptime/1000}sec). will restart...", 'pending', false, false
      if uptime < 2*1000
        @notify title, 'waiting 3sec to prevent flapping due to short uptime...', 'pending', false, false
        async.delay 3*1000, =>
          @child_process_loop collection, title, cwd, cmd, args, env
      else
        @child_process_loop collection, title, cwd, cmd, args, env
    @notify title, 'spawned new instance', 'success', false, false
    collection[title] = child
    return child

  watch: ->
    a = arguments
    cb = a[a.length-1]
    if a.length is 3
      globs = [ in: [''], out: '' ]
      [title, suffix] = a
    else if a.length is 4
      [title, globs, suffix] = a
    for k, glob of globs
      glob.in = [ glob.in ] if typeof glob.in is 'string'
      for kk of glob.in
        ((glob) =>
          @notify 'gaze', "watching #{glob.in+glob.suffix}", 'pending', false, false
          gaze path.join(process.cwd(), glob.in+glob.suffix), (err, watcher) =>
            @notify 'gaze', err, 'failure', true, false if err
            ` this`.on 'changed', (file) ->
              rel_in = path.relative path.join(process.cwd(), glob.in), file
              glob.out ||= rel_in
              cb
                title: title
                infile: path.relative process.cwd(), file
                outfile: path.join glob.out, rel_in
                inpath: glob.in
                outpath: glob.out
        )(in: glob.in[kk] and path.xplat(glob.in[kk]), out: glob.out and path.xplat(glob.out), suffix: glob.suffix or suffix)
