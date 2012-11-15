_ = require('underscore')
should = require('should')
grove = require('../index')

describe 'GrovePost', ->
  it "can infer its url", ->
    post = new grove.GrovePost({uid: "post:path$1"})
    post.url().should.equal("/posts/post:path$1")

  it "can calculate path for children", ->
    post = new grove.GrovePost({uid: "post:path$1"})
    post.childPath().should.equal("path.1")

  it "can calculate child path for wilcard paths", ->
    post = new grove.GrovePost({uid: ":*$1"})
    post.childPath().should.equal("*.1")

  it "has a neat document accessor that fires events", ->
    model = new grove.GrovePost({uid: "post:path$1", document:{a:"a", b:"b"}})
    doc = model.document
    doc.get('a').should.equal('a')
    changed_event_triggered = false
    scoped_changed_event_triggered = false
    model.on "change", ->
      changed_event_triggered = true
    model.on "change:document.c", ->
      scoped_changed_event_triggered = true
    doc.set('c', 'something')
    changed_event_triggered.should.be.true
    scoped_changed_event_triggered.should.be.true

  it "gets the correct klass automatically if it is not specified", ->
    model = new grove.GrovePost({uid: ":a.b.c"})
    model.get("uid").should.equal("post:a.b.c")
    model = new grove.GrovePost({uid: "post.special:a.b.c"})
    model.get("uid").should.equal("post.special:a.b.c")

  it "knows its url", ->
    model = new grove.GrovePost({uid: "post:a.b.c$1"})
    model.url().should.equal("/posts/post:a.b.c$1")

  it "can calculate its child path", ->
    model = new grove.GrovePost({uid: "post:a.b.c$1"})
    model.childPath().should.equal("a.b.c.1")

  it "can calculate its parent uid", ->
    model = new grove.GrovePost({uid: "post:a.b.c.1$2"})
    model.parentUid().should.equal("*:a.b.c$1")

  it "can create a new child post", ->
    model = new grove.GrovePost({uid: "post:a.b.c.1$2"})
    child = model.newChild('post', {key:'value'})
    child.id.should.equal("post:a.b.c.1.2")

  it "can tag and untag", ->
    model = new grove.GrovePost({uid: "post:a.b.c.1$2"})
    model.tag("tag")
    model.hasTag("something").should.equal(false)
    model.hasTag("tag").should.equal(true)
    model.tag("something")
    model.hasTag("something").should.equal(true)
    model.get("tags").length.should.equal(2)
    model.untag("tag")
    model.hasTag("tag").should.equal(false)

  it "knows that posts with partial uids are considered new", ->
    model = new grove.GrovePost({uid: "post:a.b.c.1"})
    model.isNew().should.equal(true)
    model = new grove.GrovePost({uid: "post:a.b.c.1$4"})
    model.isNew().should.equal(false)

describe "GroveCollectionFilter", ->
  it "can create a query string based on a chained configuration", ->
    filter = (new grove.GroveFilter()).path("a.b.*").tags(['red', 'blue']).limit(10).offset(20)
    filter.url().should.equal("/posts/*:a.b.*$*?tags=red%2Cblue&limit=10&offset=20")
  it "accepts a custom action to append to the url", ->
    filter = (new grove.GroveFilter()).path("a.b.*").tags(['red', 'blue']).limit(10).offset(20)
    filter.url("count").should.equal("/posts/*:a.b.*$*/count?tags=red%2Cblue&limit=10&offset=20")
  it "can generate a filter for children of specific posts", ->
    posts = [new grove.GrovePost({uid: "post:a.b$1"}), new grove.GrovePost({uid: "post:a.b$2"})]
    (new grove.GroveFilter()).childrenOf(posts).url().should.equal('/posts/*:a.b.1|2$*?klass=*')


describe "generateSuperPath", ->
  it "Does not touch a single, simple path", ->
    grove.generateSuperPath(["a.b.c"]).should.equal('a.b.c')
  it "Creates a simple superpath", ->
    grove.generateSuperPath(['a.b.c', 'a.d.c']).should.equal("a.b|d.c")
  it "Creates a simple superpath with wildcard", ->
    grove.generateSuperPath(['a.b.c.*', 'a.d.c.*']).should.equal("a.b|d.c.*")
  it "Fails when the source paths varies in length", ->
    should.not.exist(grove.generateSuperPath(['a.b.c', 'a.d.c.e']))
  it "Fails when the source paths varies at multiple depths", ->
    should.not.exist(grove.generateSuperPath(['a.b.c', 'b.e.c']))
