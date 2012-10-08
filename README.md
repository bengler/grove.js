# Grove.js

Core javascript library for Pebbles-applications using Grove

## Getting started

Install node and npm

    $ sudo port install node
    $ sudo port install npm

Install module dependencies

    $ npm install

Run tests

    $ node_modules/.bin/mocha

## Usage

... something something ...

## Adding new grove models

Registering your models with GrovePost will let it automatically instantiate the correct
models for each item when you load collections.

E.g.:

    class Issue extends grovecore.GrovePost
      klass: "post.issue"
      initialize: (attributes) ->
        @tag("unresolved")
      newMessage: (attributes) ->
        @newChild("post.message", attributes)
      newLogEntry: (attributes) ->
        @newChild("post.log_entry", attributes)
      setResolved: ->
        @untag("unresolved")
        @save()

    grovecore.GrovePost.registerModel(core.Issue)

