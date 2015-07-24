{Minimatch} = require 'minimatch'
GitUtils = require 'git-utils'
path = require 'path'

# Public: {PathFilter} makes testing for path inclusion easy.
module.exports =
class PathFilter
  @MINIMATCH_OPTIONS: { matchBase: true, dot: true }

  @escapeRegExp: (str) ->
    str.replace(/([\/'*+?|()\[\]{}.\^$])/g, '\\$1')

  # Public: Construct a {PathFilter}
  #
  # * `rootPath` {String} top level directory to scan. eg. `/Users/ben/somedir`
  # * `options` {Object} options hash
  #   * `excludeVcsIgnores` {Boolean}; default false; true to exclude paths
  #      defined in a .gitignore. Uses git-utils to check ignred files.
  #   * `inclusions` {Array} of patterns to include. Uses minimatch with a couple
  #      additions: `['dirname']` and `['dirname/']` will match all paths in
  #      directory dirname.
  #   * `exclusions` {Array} of patterns to exclude. Same matcher as inclusions.
  #   * `includeHidden` {Boolean} default false; true includes hidden files
  constructor: (rootPath, options={}) ->
    {includeHidden, excludeVcsIgnores} = options
    {inclusions, exclusions, globalExclusions} = @sanitizePaths(options)

    @inclusions = @createMatchers(inclusions, true)
    @exclusions = @createMatchers(exclusions, false)
    @globalExclusions = @createMatchers(globalExclusions, false)

    @repo = GitUtils.open(rootPath) if excludeVcsIgnores

    @excludeHidden() if includeHidden != true

  ###
  Section: Testing For Acceptance
  ###

  # Public: Test if the `filepath` is accepted as a file based on the
  # constructing options.
  #
  # * `filepath` {String} path to a file. File should be a file and should exist
  #
  # Returns {Boolean} true if the file is accepted
  isFileAccepted: (filepath) ->
    @isDirectoryAccepted(filepath) and @isPathAccepted('file', filepath)

  # Public: Test if the `filepath` is accepted as a directory based on the
  # constructing options.
  #
  # * `filepath` {String} path to a directory. File should be a directory and should exist
  #
  # Returns {Boolean} true if the directory is accepted
  isDirectoryAccepted: (filepath) ->
    return false if @isPathExcluded('directory', filepath) is true

    # An matching explicit local inclusion will override the global exclusions
    # Other than this, the logic is the same between file and directory matching.
    return true if @inclusions['directory']?.length && @isPathIncluded('directory', filepath)

    @isPathIncluded('directory', filepath) &&
    !@isPathGloballyExcluded('directory', filepath)

  isPathAccepted: (fileOrDirectory, filepath) ->
    !@isPathExcluded(fileOrDirectory, filepath) &&
    @isPathIncluded(fileOrDirectory, filepath) &&
    !@isPathGloballyExcluded(fileOrDirectory, filepath)

  ###
  Section: Private Methods
  ###

  isPathIncluded: (fileOrDirectory, filepath) ->
    inclusions = @inclusions[fileOrDirectory]
    return true unless inclusions?.length

    index = inclusions.length
    while index--
      return true if inclusions[index].match(filepath)
    return false

  isPathExcluded: (fileOrDirectory, filepath) ->
    return true if @repo?.isIgnored(@repo.relativize(filepath))
    exclusions = @exclusions[fileOrDirectory]
    return false unless exclusions?.length

    index = exclusions.length
    while index--
      return true if (exclusions[index].match(filepath))
    return false

  isPathGloballyExcluded: (fileOrDirectory, filepath) ->
    return true if @repo?.isIgnored(@repo.relativize(filepath))

    exclusions = @globalExclusions[fileOrDirectory]
    index = exclusions.length
    while index--
      return true if (exclusions[index].match(filepath))
    return false

  sanitizePaths: (options) ->
    return options unless options.inclusions?.length
    inclusions = []
    for includedPath in options.inclusions
      if includedPath and includedPath[0] is '!'
        options.exclusions ?= []
        options.exclusions.push(includedPath.slice(1))
      else if includedPath
        inclusions.push(includedPath)
    options.inclusions = inclusions
    options

  excludeHidden: ->
    matcher = new Minimatch(".*", PathFilter.MINIMATCH_OPTIONS)
    @exclusions.file.push(matcher)
    @exclusions.directory.push(matcher)

  createMatchers: (patterns=[], deepMatch) ->
    addFileMatcher = (matchers, pattern) ->
      matchers.file.push(new Minimatch(pattern, PathFilter.MINIMATCH_OPTIONS))

    addDirectoryMatcher = (matchers, pattern, deepMatch) ->
      # It is important that we keep two permutations of directory patterns:
      #
      # * 'directory/anotherdir'
      # * 'directory/anotherdir/**'
      #
      # Minimatch will return false if we were to match 'directory/anotherdir'
      # against pattern 'directory/anotherdir/*'. And it will return false
      # matching 'directory/anotherdir/file.txt' against pattern
      # 'directory/anotherdir'.

      if pattern[pattern.length - 1] == path.sep
        pattern += '**'

      # When the user specifies to include a nested directory, we need to
      # specify matchers up to the nested directory
      #
      # * User specifies 'some/directory/anotherdir/**'
      # * We need to break it up into multiple matchers
      #   * 'some'
      #   * 'some/directory'
      #
      # Otherwise, we'll hit the 'some' directory, and if there is no matcher,
      # it'll fail and have no chance at hitting the
      # 'some/directory/anotherdir/**' matcher the user originally specified.
      if deepMatch
        paths = pattern.split(path.sep)
        lastIndex = paths.length - 2
        lastIndex-- if paths[paths.length - 1] in ['*', '**']

        if lastIndex >= 0
          deepPath = ''
          for i in [0..lastIndex]
            deepPath = path.join(deepPath, paths[i])
            addDirectoryMatcher(matchers, deepPath)

      directoryPattern = ///
        #{'\\'+path.sep}\*$|   # Matcher ends with a separator followed by *
        #{'\\'+path.sep}\*\*$  # Matcher ends with a separator followed by **
      ///
      matchIndex = pattern.search(directoryPattern)
      addDirectoryMatcher(matchers, pattern.slice(0, matchIndex)) if matchIndex > -1

      matchers.directory.push(new Minimatch(pattern, PathFilter.MINIMATCH_OPTIONS))

    pattern = null
    matchers =
      file: [],
      directory: []

    r = patterns.length
    while (r--)
      pattern = patterns[r].trim()
      continue if (pattern.length == 0 || pattern[0] == '#')

      endsWithSeparatorOrStar = ///
        #{'\\'+path.sep}$|   # Pattern ends in a separator
        #{'\\'+path.sep}\**$ # Pattern ends with a seperator followed by a *
      ///
      if (endsWithSeparatorOrStar.test(pattern))
        # Is a dir if it ends in a '/' or '/*'
        addDirectoryMatcher(matchers, pattern, deepMatch)
      else if (pattern.indexOf('.') < 1 && pattern.indexOf('*') < 0)
        # If no extension and no '*', assume it's a dir.
        # Also assumes hidden patterns like '.git' are directories.
        addDirectoryMatcher(matchers, pattern + path.sep + '**', deepMatch)
      else
        addFileMatcher(matchers, pattern)

    matchers
