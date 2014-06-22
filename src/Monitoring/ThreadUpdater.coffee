ThreadUpdater =
  init: ->
    return if g.VIEW isnt 'thread' or !Conf['Thread Updater']

    if Conf['Updater and Stats in Header']
      @dialog = sc = $.el 'span',
        innerHTML: "[<span id=update-status></span><span id=update-timer title='Update now'></span>]\u00A0"
        id:        'updater'
      $.ready ->
        Header.addShortcut sc
    else
      @dialog = sc = UI.dialog 'updater', 'bottom: 0px; left: 0px;',
        "<div class=move><span id=update-status></span><span id=update-timer title='Update now'></span></div>"
      $.addClass doc, 'float'
      $.ready ->
        $.addClass doc, 'float'
        $.add d.body, sc

    @checkPostCount = 0

    @timer  = $ '#update-timer', sc
    @status = $ '#update-status', sc
    @isUpdating = Conf['Auto Update']

    $.on @timer,  'click', @update
    $.on @status, 'click', @update

    subEntries = []
    for name, conf of Config.updater.checkbox
      checked = if Conf[name] then 'checked' else ''
      el = $.el 'label',
        title:    "#{conf[1]}"
        innerHTML: "<input name='#{name}' type=checkbox #{checked}> #{name}"
      input = el.firstElementChild
      $.on input, 'change', $.cb.checked
      if input.name is 'Scroll BG'
        $.on input, 'change', @cb.scrollBG
        @cb.scrollBG()
      else if input.name is 'Auto Update'
        $.on input, 'change', @cb.update
      subEntries.push el: el

    @settings = $.el 'span',
      innerHTML: '<a href=javascript:;>Interval</a>'

    $.on @settings, 'click', @intervalShortcut

    subEntries.push el: @settings

    Header.menu.addEntry @entry =
      el: $.el 'span',
        textContent: 'Updater'
      order: 110
      subEntries: subEntries

    Thread.callbacks.push
      name: 'Thread Updater'
      cb:   @node

  disconnect: ->
    return if g.VIEW isnt 'thread' or !Conf['Thread Updater']
    $.off @timer,  'click', @update
    $.off @status, 'click', @update

    clearTimeout @timeoutID if @timeoutID

    for entry in @entry.subEntries
      {el} = entry
      input = el.firstElementChild
      $.off input, 'change', $.cb.checked
      $.off input, 'change', @cb.scrollBG
      $.off input, 'change', @cb.update

    $.off @settings, 'click',         @intervalShortcut
    $.off window, 'online offline',   @cb.online
    $.off d,      'QRPostSuccessful', @cb.checkpost
    $.off d,      'visibilitychange', @cb.visibility

    @set 'timer', null
    @set 'status', 'Offline'

    $.event 'rmMenuEntry', @entry

    if Conf['Updater and Stats in Header']
      Header.rmShortcut @dialog
    else
      $.rmClass doc, 'float'
      $.rm @dialog

    delete @[name] for name in ['checkPostCount', 'timer', 'status', 'isUpdating', 'entry', 'dialog', 'thread', 'root', 'lastPost', 'outdateCount', 'online', 'seconds', 'timeoutID']

    Thread.callbacks.disconnect 'Thread Updater'

  node: ->
    ThreadUpdater.thread   = @
    ThreadUpdater.root     = @OP.nodes.root.parentNode
    ThreadUpdater.lastPost = +@posts.keys[@posts.keys.length - 1]

    ThreadUpdater.cb.interval.call $.el 'input',
      value: Conf['Interval']
      name:  'Interval'

    $.on window, 'online offline',   ThreadUpdater.cb.online
    $.on d,      'QRPostSuccessful', ThreadUpdater.cb.checkpost
    $.on d,      'visibilitychange', ThreadUpdater.cb.visibility

    ThreadUpdater.cb.online()
    Rice.nodes ThreadUpdater.dialog

  ###
  http://freesound.org/people/pierrecartoons1979/sounds/90112/
  cc-by-nc-3.0
  ###
  beep: 'data:audio/wav;base64,<%= grunt.file.read("src/General/audio/beep.wav", {encoding: "base64"}) %>'

  cb:
    online: ->
      if ThreadUpdater.online = navigator.onLine
        ThreadUpdater.outdateCount = 0
        ThreadUpdater.setInterval()
        ThreadUpdater.set 'status', null, null
        return
      ThreadUpdater.set 'timer', null
      ThreadUpdater.set 'status', 'Offline', 'warning'
    post: (e) ->
      return unless ThreadUpdater.isUpdating and e.detail.threadID is ThreadUpdater.thread.ID
      ThreadUpdater.outdateCount = 0
      setTimeout ThreadUpdater.update, 1000 if ThreadUpdater.seconds > 2
    checkpost: (e) ->
      unless ThreadUpdater.checkPostCount
        return unless e.detail.threadID is ThreadUpdater.thread.ID
        ThreadUpdater.seconds = 0
        ThreadUpdater.outdateCount = 0
        ThreadUpdater.set 'timer', '...'
      unless g.DEAD or ThreadUpdater.foundPost or ThreadUpdater.checkPostCount >= 5
        return setTimeout ThreadUpdater.update, ++ThreadUpdater.checkPostCount * $.SECOND
      ThreadUpdater.setInterval()
      ThreadUpdater.checkPostCount = 0
      delete ThreadUpdater.foundPost
      delete ThreadUpdater.postID
    visibility: ->
      return if d.hidden
      # Reset the counter when we focus this tab.
      ThreadUpdater.outdateCount = 0
      if ThreadUpdater.seconds > ThreadUpdater.interval
        ThreadUpdater.setInterval()
    scrollBG: ->
      ThreadUpdater.scrollBG = if Conf['Scroll BG']
        -> true
      else
        -> not d.hidden
    interval: (e) ->
      val = parseInt @value, 10
      if val < 1 then val = 1
      ThreadUpdater.interval = @value = val
      $.cb.value.call @ if e
    load: (e) ->
      {req} = ThreadUpdater
      switch req.status
        when 200
          g.DEAD = false
          ThreadUpdater.parse req.response.posts
          ThreadUpdater.setInterval()
        when 404
          g.DEAD = true
          ThreadUpdater.set 'timer', null
          ThreadUpdater.set 'status', '404', 'warning'
          clearTimeout ThreadUpdater.timeoutID
          ThreadUpdater.thread.kill()
          $.event 'ThreadUpdate',
            404: true
            threadID: ThreadUpdater.thread.fullID
        else
          ThreadUpdater.outdateCount++
          ThreadUpdater.setInterval()
          [text, klass] = if req.status is 304
            [null, null]
          else
            ["#{req.statusText} (#{req.status})", 'warning']
          ThreadUpdater.set 'status', text, klass

      if ThreadUpdater.postID
        ThreadUpdater.cb.checkpost()

  setInterval: ->
    i   = ThreadUpdater.interval + 1

    if Conf['Optional Increase']
      # Lower the max refresh rate limit on visible tabs.
      cur   = ThreadUpdater.outdateCount or 1
      limit = if d.hidden then 7 else 10
      j     = if cur <= limit then cur else limit

      # 1 second to 100, 30 to 300.
      cur = (Math.floor(i * 0.1) or 1) * j * j
      ThreadUpdater.seconds =
        if cur > i
          if cur <= 300
            cur
          else
            300
        else
          i
    else
      ThreadUpdater.seconds = i

    ThreadUpdater.set 'timer', ThreadUpdater.seconds
    ThreadUpdater.count true

  intervalShortcut: ->
    Settings.open 'Advanced'
    settings = $.id 'fourchanx-settings'
    $('input[name=Interval]', settings).focus()

  set: (name, text, klass) ->
    el = ThreadUpdater[name]
    if node = el.firstChild
      # Prevent the creation of a new DOM Node
      # by setting the text node's data.
      node.data = text
    else
      el.textContent = text
    el.className = klass if klass isnt undefined

  count: (start) ->
    clearTimeout ThreadUpdater.timeoutID
    ThreadUpdater.timeout() if start and ThreadUpdater.isUpdating and navigator.onLine

  timeout: ->
    ThreadUpdater.timeoutID = setTimeout ThreadUpdater.timeout, 1000
    unless n = --ThreadUpdater.seconds
      ThreadUpdater.update()
    else if n <= -60
      ThreadUpdater.set 'status', 'Retrying', null
      ThreadUpdater.update()
    else if n > 0
      ThreadUpdater.set 'timer', n

  update: ->
    return unless navigator.onLine
    ThreadUpdater.count()
    if Conf['Auto Update']
      ThreadUpdater.set 'timer', '...'
    else
      ThreadUpdater.set 'timer', 'Update'
    ThreadUpdater.req?.abort()
    url = "//a.4cdn.org/#{ThreadUpdater.thread.board}/thread/#{ThreadUpdater.thread}.json"
    ThreadUpdater.req = $.ajax url,
      onabort:   ThreadUpdater.cb.load
      onloadend: ThreadUpdater.cb.load
      ontimeout: ThreadUpdater.cb.load
      timeout:   $.MINUTE
    ,
      whenModified: true

  updateThreadStatus: (type, status) ->
    return unless hasChanged = ThreadUpdater.thread["is#{type}"] isnt status
    ThreadUpdater.thread.setStatus type, status
    change = if type is 'Sticky'
      if status
        'now a sticky'
      else
        'not a sticky anymore'
    else
      if status
        'now closed'
      else
        'not closed anymore'
    new Notice 'info', "The thread is #{change}.", 30

  parse: (postObjects) ->
    OP = postObjects[0]
    Build.spoilerRange[ThreadUpdater.thread.board] = OP.custom_spoiler

    ThreadUpdater.updateThreadStatus 'Sticky', !!OP.sticky
    ThreadUpdater.updateThreadStatus 'Closed', !!OP.closed
    ThreadUpdater.thread.postLimit = !!OP.bumplimit
    ThreadUpdater.thread.fileLimit = !!OP.imagelimit

    posts = [] # post objects
    index = [] # existing posts
    files = [] # existing files
    count = 0  # new posts count
    # Build the index, create posts.
    for postObject in postObjects
      num = postObject.no
      index.push num
      files.push num if postObject.fsize
      continue if num <= ThreadUpdater.lastPost
      # Insert new posts, not older ones.
      count++
      node = Build.postFromObject postObject, ThreadUpdater.thread.board.ID
      posts.push new Post node, ThreadUpdater.thread, ThreadUpdater.thread.board

    # Check for deleted posts/files.
    ThreadUpdater.thread.posts.forEach (post) ->
      # XXX tmp fix for 4chan's racing condition
      # giving us false-positive dead posts.
      # continue if post.isDead
      ID = +post.ID

      unless ID in index
        post.kill()
      else if post.isDead
        post.resurrect()
      else if post.file and !post.file.isDead and ID not in files
        post.kill true

      # Fetching your own posts after posting
      if ThreadUpdater.postID and ThreadUpdater.postID is ID
        ThreadUpdater.foundPost = true

    sendEvent = ->
      $.event 'ThreadUpdate',
        404: false
        threadID: ThreadUpdater.thread.fullID
        newPosts: posts.map (post) -> post.fullID
        postCount: OP.replies + 1
        fileCount: OP.images + (!!ThreadUpdater.thread.OP.file and !ThreadUpdater.thread.OP.file.isDead)

    unless count
      ThreadUpdater.set 'status', null, null
      ThreadUpdater.outdateCount++
      sendEvent()
      return

    ThreadUpdater.set 'status', "+#{count}", 'new'
    ThreadUpdater.outdateCount = 0
    if Conf['Beep'] and d.hidden and Unread.posts and !Unread.posts.length
      unless ThreadUpdater.audio
        ThreadUpdater.audio = $.el 'audio', src: ThreadUpdater.beep
      ThreadUpdater.audio.play()

    ThreadUpdater.lastPost = posts[count - 1].ID
    Post.callbacks.execute posts

    scroll = Conf['Auto Scroll'] and ThreadUpdater.scrollBG() and Header.getBottomOf(ThreadUpdater.root) > -75

    for post in posts
      {root} = post.nodes
      if post.cb
        unless post.cb()
          $.add ThreadUpdater.root, root
      else
        $.add ThreadUpdater.root, root

    sendEvent()
    if scroll
      if Conf['Bottom Scroll']
        window.scrollTo 0, d.body.clientHeight
      else
        Header.scrollTo posts[0].nodes.root
