
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

The newly instantiated model will have a randomly generated UUID. If you want to make sure that the UUID hasn't already been used
you can generate a new one like this:

```
g = Group.new
g.find_new_uuid(:ensure_unique_in => Group)
```

This will generate random UUIDs until it finds one that isn't in the passed collection (`Group` in the example).
Obviously, the whole idea of random (type 4) UUIDs is that there is a tiny probability of generating duplicates.
For this reason, you should only consider using `:ensure_unique_in` if a duplicate UUID would be a disaster for you.

Copyright (c) 2011 PeepAll Ltd, released under the MIT license
