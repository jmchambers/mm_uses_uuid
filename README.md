
mm_uses_uuid plugin
============

Models that use this plugin use a `BSON::Binary::SUBTYPE_UUID` for the model's id field rather than the default `BSON::ObjectId`.

Requirements
============

- Ruby 1.9
- MongoMapper 0.10.1 or greater

Installation
=======

Add this to your Gemfile if using Bundler: `gem 'mm_uses_uuid'`

Or install the gem from the command line: `gem install mm_uses_uuid`

Usage
=======

Use the MongoMapper `plugin` method to add MmUsesUuid to your model, for example:

```
class Group
  include MongoMapper::Document
  plugin  MmUsesUuid
  
  many :people, :class_name => 'Person'
end
```

The newly instantiated model will have a randomly generated UUID.

Ensuring truly unique UUIDs
---------------------------

If you want to make sure that the UUID hasn't already been used
you can generate a new one like this:

```
g = Group.new
g.find_new_uuid(:ensure_unique_in => Group)
```

This will generate random UUIDs until it finds one that isn't in the passed collection (`Group` in the example).
Obviously, the whole idea of random (type 4) UUIDs is that there is a tiny probability of generating duplicates.
For this reason, you should only consider using `:ensure_unique_in` if a duplicate UUID would be a disaster for you.

Encoding class in the LSN
-------------------------

It is possible to encode the class of an object in its UUID by forcing the least significant nibble (the rightmost hex character) of its UUIDs to be a particular value.
To do this, add the `uuid_lsn` method to you model and pass it a single hex character like this:

```
class Group
  include MongoMapper::Document
  plugin  MmUsesUuid
  
  many :people, :class_name => 'Person'
  
  uuid_lsn 0x0
end
```

Once this value is set you can use `UuidModel.find(...)` to find by id (or a list of ids) and it will automatically detect the class by inspecting
the last character of the UUIDs you pass. So for the example above, all UUIDs generated for new Group objects will end in '0'
and, if you pass a UUID ending in '0' to `UuidModel.find`, it will pass that request on to `Group.find()`. Clearly, this method only allows you
to target 16 collections at most as the last nibble can only have values of 0 to 15.

This method can be useful if you need to implement a polymorphic many-to-many association but you don't want to use [Single Collection Inheritance][1]
because the polymorphic values have significantly different behaviours and attributes. The following example shows how to do this:

```
class Person
  include MongoMapper::Document
  plugin  MmUsesUuid
  
  key :name
  key :age
  
  key  :interest_ids, Array
  many :interests, :in => :interest_ids, :class_name => 'UuidModel' #values can be a Group or a Person
  
  belongs_to :group
  
  uuid_lsn 0xf
end
```

Copyright (c) 2011 PeepAll Ltd, released under the MIT license


[1]: http://mongomapper.com/documentation/plugins/single-collection-inheritance.html
