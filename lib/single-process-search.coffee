PathSearcher = require './path-searcher'
PathScanner = require './path-scanner'

MAX_CONCURRENT_SEARCH = 20

###
Single Process
###

search = (regex, scanner, searcher, doneCallback) ->
  finishedScanning = false
  pathCount = 0
  pathsSearching = 0
  pathsToSearch = []

  searchPath = (filePath) ->
    pathsSearching++
    searcher.searchPath regex, filePath, ->
      pathCount--
      pathsSearching--
      checkIfFinished()

  searchNextPath = ->
    if pathsSearching < MAX_CONCURRENT_SEARCH and pathsToSearch.length
      searchPath(pathsToSearch.pop())

  maybeSearchPath = (filePath) =>
    pathCount++
    if pathsSearching < MAX_CONCURRENT_SEARCH
      searchPath(filePath)
    else
      pathsToSearch.push(filePath)

  onFinishedScanning = ->
    finishedScanning = true
    checkIfFinished()

  checkIfFinished = ->
    searchNextPath()
    finish() if finishedScanning and pathCount == 0

  finish = ->
    scanner.removeListener 'path-found', maybeSearchPath
    scanner.removeListener 'finished-scanning', onFinishedScanning
    doneCallback()

  scanner.on 'path-found', maybeSearchPath
  scanner.on 'finished-scanning', onFinishedScanning
  scanner.scan()

searchMain = (options) ->
  searcher = new PathSearcher()
  scanner = new PathScanner(options.pathToScan, options)
  console.time 'Single Process Search'

  count = 0
  resultCount = 0
  pathCount = 0

  scanner.on 'path-found', (path) ->
    pathCount++

  searcher.on 'results-found', (results) ->
    count++
    console.log results.path if options.verbose

    for match in results.matches
      resultCount++
      if options.verbose
        console.log '  ', match.lineNumber + ":", match.matchText, 'at', match.range

  search new RegExp(options.search, 'gi'), scanner, searcher, ->
    console.timeEnd 'Single Process Search'
    console.log "#{resultCount} matches in #{count} files. Searched #{pathCount} files"

scanMain = (options) ->
  scanner = new PathScanner(options.pathToScan, options)
  console.time 'Single Process Scan'

  count = 0
  scanner.on 'path-found', (path) ->
    count++
    console.log path if options.verbose

  scanner.on 'finished-scanning', ->
    console.timeEnd 'Single Process Scan'
    console.log "Found #{count} paths"

  scanner.scan()

module.exports = {scanMain, searchMain, search}