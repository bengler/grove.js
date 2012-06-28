_ = require('underscore') unless _?
$ = require('jquery') unless $?
pebblecore = require('pebblecore')
Backbone = require('backbone_pebbles')
QueryParams = require('queryparams-coffee').QueryParams

services = new pebblecore.service.ServiceSet
  grove: 1

Uid = pebblecore.uid.Uid

isArray = (obj) -> Object::toString.call(obj) == '[object Array]';

exports.config = {realm: null, appPath: null}

exports.setRealm = (realm) ->
  exports.config.realm = realm
  exports.config.appPath = "#{realm}.resolve"

# Calculates the Uid of the parent object for an object with the provided uid.
# E.g. "post.message:a.b.5$9" --> "*:a.b$5"
exports.uidOfParent = (uid) ->
  [klass, path, oid] = Uid.raw_parse(uid)
  labels = path.split('.')
  oid = labels.pop()
  path = labels.join('.')
  "*:#{path}$#{oid}"

# Calculates the path for children of this object by sticking the oid in the path:
# E.g. "post.activity:a.b$5" --> "a.b.5"
exports.pathOfChildren = (uid) ->
  [klass, path, oid] = Uid.raw_parse(uid)
  return null unless oid? # Unknown unless oid is set
  "#{path}.#{oid}"

# Calculates a Grove superpath for all provided paths if possible. This requires
# that all paths are of equal length, that they are either all or none are terminated with a
# wildcard '*', and that they vary only on one single depth. When a superpath is impossible
# null is returned.
# So these are okay:
# ['a.b.c', 'a.c.c', 'a.d.c'] (becomes: "a.b|c|d.c")
# ['a.b.c.*', 'a.c.c.*', 'a.d.c.*'] (becomes: "a.b|c|d.c.*")
# While this is not okay because it varies on more than one level:
# ['a.b', 'c.d']
# This is not okay because paths varies in length:
# ['a.b.c', 'a.b']
exports.generateSuperPath = (paths) ->
  return null if paths.length == 0
  return paths[0] if paths.length == 1
  paths = _.map paths, (path) ->
    path.split('.')
  # Check that all paths are of same length
  length = paths[0].length
  lengths_equal = _.all paths, (path) ->
    path.length == length
  return null unless lengths_equal
  # Start building superpath
  result = []
  variable_level = null
  # Iterate through all depth levels from left to right
  for i in [0...length]
    # Use an object as a hash
    set = {}
    # Set a key for each label used in a path on this level
    _.each paths, (path) ->
      set[path[i]] = 1
    # Extract the labels
    labels = _.keys(set)
    # Check if this is the level with multiple keys
    if labels.length > 1
      # Fail if this is the second level with multiple keys
      return null if variable_level?
      # Remember that this is the variable level
      variable_level = i
    result.push(labels.join('|'))
  result.join('.')


# Used to provide access to the document of a GrovePost
# while triggering events the way normal attributes would.
class DocumentAccessor
  constructor: (post) ->
    @post = post
  set: (key, value, options) ->
    document = @post.get('document')
    document[key] = value
    unless options? && options.silent
      @post.trigger("change")
      @post.trigger("change:document")
      @post.trigger("change:document.#{key}")
  get: (key) ->
    @post.get('document')[key]


# Common base model for all Grove posts. Keeps a map of all specific
# post models. Add a special model for a Grove post klass by giving it
# a 'klass' property and adding it with GrovePost.registerModel.
class exports.GrovePost extends Backbone.Model
  idAttribute: "uid"
  namespace: "post"
  klass: "post"
  initialize: ->
    @document = new DocumentAccessor(@)
    # Ensures the default klass is the klass for this model
    if @get("uid")
      [_klass, _path, _oid] = Uid.raw_parse @get("uid")
      unless _klass?
        uid = "#{@klass}:#{_path}"
        uid += "$#{_oid}" if _oid?
        @set("uid", uid)
  url: ->
    services.grove.service_url("/posts/#{@id}")
  uid: ->
    Uid.fromString(@id)
  childPath: ->
    exports.pathOfChildren(@id)
  parentUid: ->
    exports.uidOfParent(@id)
  newChild: (klass, attributes) ->
    modelClass = exports.GrovePost.klassMap[klass] || exports.GrovePost
    attributes = _.extend(_.clone(attributes), {uid: "#{klass}:#{@childPath()}"})
    new modelClass(attributes)
  tag: (tags) ->
    @set('tags', _.union(@get('tags') || [], _.flatten(arguments)))
    @
  untag: (tags) ->
    @set('tags', _.without(@get('tags') || [], _.flatten(arguments)...))
    @
  addPath: (path) ->
    services.grove.post(@url()+"/paths/#{path}").then (post) ->
      @set(@parse(post))
  removePath: (path) ->
    services.grove.delete(@url()+"/paths/#{path}").then (post) ->
      @set(@parse(post))
  setOccurrence: (event, at) ->
    services.grove.put(@url()+"/occurrences/#{event}", {at}).then (post) ->
      @set(@parse(post))
  hasTag: (tag) ->
    tags = _.flatten(arguments)
    _.size(_.intersection(@get('tags') || [], tags)) == _.size(tags)
  isNew: ->
    !@get("uid").match(/\$\d+$/)

_.extend exports.GrovePost,
  klassMap: {}
  registerModel: (model) ->
    @klassMap[model::klass] = model

  instantiate: (record) ->
    klass = Uid.fromString(record.uid).klass
    modelClass = @klassMap[klass] || exports.GrovePost
    new modelClass(record)


# A chainable api to configure the filtering of GroveCollections
class exports.GroveFilter
  constructor: (settings) ->
    @reset(settings || {})
  reset: (settings) ->
    @settings = _.clone(settings)
  clone: ->
    new exports.GroveFilter(@settings)
  path: (path) ->
    @settings.path = path
    @
  oid: (oid) ->
    @settings.oid = oid
    @
  klass: (klass) ->
    @settings.klass = klass
    @
  childrenOf: (post) ->
    paths = _.map _.flatten(arguments), (post) ->
      post.childPath()
    superpath = exports.generateSuperPath(paths)
    throw "Unable to create superpath for [#{paths.join(', ')}]" unless superpath?
    @path(superpath).oid("*").klass("*")
    @
  limit: (count) ->
    @settings.limit = count
    @
  offset: (index) ->
    @settings.offset = index
    @
  tags: (array) ->
    @settings.tags = array
    @
  url: (action) ->
    params = _.clone(@settings)
    # Extract path and oid and build the id part of the url
    _klass = params.klass || '*'
    _path = params.path || '*'
    _oid = params.oid || '*'
    delete params.path
    delete params.oid
    _id = "#{_klass}:#{_path}$#{_oid}"
    # Convert certain arrays to comma separated lists
    _.each ['klass', 'tags'], (field) ->
      if isArray(params[field])
        params[field] = params[field].join(',')
    _query = QueryParams.encode(params)
    url = "/posts/#{_id}"
    url += "/#{action}" if action?
    url += "?#{_query}"
    services.grove.service_url(url)


# Polymorphic collection that knows how to load a filtered collection of
# GrovePosts and instantiate the correct model class for each post.
class exports.GroveCollection extends Backbone.Collection
  namespace: "posts"
  initialize: (models, options) ->
    @filter = options?.filter || new exports.GroveFilter()
  url: ->
    @filter.url()
  parse: (response) ->
    _.map response.posts, (record) ->
      exports.GrovePost.instantiate(record.post)

@resolvecore = core unless exports?