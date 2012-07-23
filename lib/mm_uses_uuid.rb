require 'mongo_mapper'
require_relative "mm_uses_uuid/version"
require_relative "mm_uses_uuid/bson_binary_mixin"

class BsonUuid
  def self.to_mongo(value)
    case value
    when String
      BSON::Binary.new(value.gsub('-', ''), BSON::Binary::SUBTYPE_UUID)
    when BSON::Binary, NilClass
      value
    else
      raise "BsonUuid cannot be of type #{value.class}. String, BSON::Binary and NilClass are the only permitted types"
    end 
  end
  
  def self.from_mongo(value)
    value
  end
end

class MongoMapper::Plugins::Associations::InArrayProxy

  def find_target
    return [] if ids.blank?
    if klass == UuidModel
      out = *UuidModel.find(*criteria[:_id])
    else
      all
    end
  end
  
end

class UuidModel
  
  include MongoMapper::Document
  
  @@lsn_class_lookup ||= {}
  
  def self.add_lsn_mapping(ind, klass)
    @@lsn_class_lookup[ind] = klass
    @@class_lsn_lookup = @@lsn_class_lookup.invert
  end
  
  def self.lsn_class_lookup
    @@lsn_class_lookup
  end
  
  def self.class_lsn_lookup
    @@class_lsn_lookup
  end
  
  def self.find(*ids)
    ids = ids.flatten.uniq
    ids_by_class = ids.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |id, hsh|
      lsn = id.to_s[-1].hex
      klass = @@lsn_class_lookup[lsn]
      if klass.nil?
        raise "expected to find a class in @@lsn_class_lookup[#{lsn}] of the MongoMapper module but there was no entry. You need to set uuid_lsn in your class."
      end
      hsh[klass] << id
    end
    result = ids_by_class.map {|klass, ids| klass.find(ids)} .flatten
    ids.length == 1 ? result.first : result
  end
  
  def self.find!(*ids)
    ids = ids.flatten.uniq
    raise MongoMapper::DocumentNotFound, "Couldn't find without an ID" if ids.size == 0
    find(*ids).tap do |result|
      if result.nil? || ids.size != Array(result).size
        raise MongoMapper::DocumentNotFound, "Couldn't find all of the ids (#{ids.join(',')}). Found #{Array(result).size}, but was expecting #{ids.size}"
      end
    end
  end

end

module MmUsesUuid
  extend ActiveSupport::Concern

  included do
    key :_id, BsonUuid
  end

  module ClassMethods
    
    def find(*args)
      args = convert_ids_to_BSON(args)
      super(args)
    end
    
    def find!(*args)
      args = convert_ids_to_BSON(args)
      super(args)
    end
    
    def convert_ids_to_BSON(args)
      args.flatten!
      if args.size > 1
        args.map! {|id| BsonUuid.to_mongo(id)}
      else
        args = BsonUuid.to_mongo(args.first)
      end
      args
    end
    
    def new(params = {})
      passed_id = params.delete(:id) || params.delete(:_id) || params.delete('id') || params.delete('_id')
      new_object = super(params)
      if passed_id.is_a?(BSON::Binary) and passed_id.subtype == BSON::Binary::SUBTYPE_UUID
        new_object.id = passed_id
      else
        new_object.find_new_uuid
      end
      new_object
    end

    def uuid_lsn(lsn_integer)
      UuidModel.add_lsn_mapping(lsn_integer, self)
    end
    
  end

   
  def find_new_uuid(options = {})
    
    options = {force_safe: false}.merge(options)
      
    if not options[:ensure_unique_in]
      @_id, variant = make_uuid
      #puts "assuming #{variant} UUID #{@_id} is available"
      return
    else
      find_new_uuid_safely(options[:ensure_unique_in])
    end

  end
  
  def find_new_uuid_safely(coll)

    @_id = nil
    begin
      trial_id, variant = make_uuid
      #puts "CHECKING #{coll} collection for availability of #{variant} UUID: #{trial_id}"
      if coll.where(:_id => trial_id).fields(:_id).first.nil?
        @_id = trial_id
      end
    end while @_id.nil?

  end
  
  def make_uuid
    uuid = SecureRandom.uuid.gsub!('-', '')
    if self.class.single_collection_inherited?
      lookup_class = self.class.collection_name.singularize.camelize.constantize
    else
      lookup_class = self.class
    end
    if replacement_lsn = UuidModel.class_lsn_lookup[lookup_class]
      uuid[-1] = replacement_lsn.to_s(16)
    end
    bson_encoded_uuid = BSON::Binary.new(uuid, BSON::Binary::SUBTYPE_UUID)
    return bson_encoded_uuid, 'random'
  end
  
  def id_to_s!
    @_id = @_id.to_s
    self
  end
  
  def id_to_s
    copy = self.clone
    copy.instance_variable_set '@_id',  @_id.to_s
    copy
  end
  
end
