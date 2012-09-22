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

module MmUsesUuid
  extend ActiveSupport::Concern

  included do
    key :_id, BsonUuid
  end

  module ClassMethods
    
    def serialize_id(object)
      case object
      when MongoMapper::Document, MongoMapper::EmbeddedDocument
        object.id.to_s
      else
        object.to_s
      end       
    end
    
    def deserialize_id(id)
      BSON::Binary.new(id, BSON::Binary::SUBTYPE_UUID)
    end
    
    def find(*ids)
      batch_mode = ids.first.is_a?(Array) || ids.length > 1
      ids.flatten!
      ids = convert_ids_to_BSON(ids)
      results = super(ids)
      batch_mode ? results : results.first
    end
    
    def find!(*ids)
      batch_mode = ids.first.is_a?(Array) || ids.length > 1
      ids.flatten!
      ids = convert_ids_to_BSON(ids)
      results = super(ids)
      batch_mode ? results : results.first
    end
    
    def convert_ids_to_BSON(ids)
      ids.map {|id| BsonUuid.to_mongo(id)}
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
      raise "lsn_integer must be from 0-255" unless (0..255).cover?(lsn_integer)
      UuidModel.add_lsn_mapping(lsn_integer, self)
    end
    
  end

   
  def find_new_uuid(options = {})
    
    options = {force_safe: false}.merge(options)
      
    if not options[:ensure_unique_in]
      @_id = make_uuid
      #puts "assuming UUID #{@_id} is available"
      return
    else
      find_new_uuid_safely(options[:ensure_unique_in])
    end

  end
  
  def find_new_uuid_safely(coll)

    @_id = nil
    begin
      trial_id = make_uuid
      #puts "CHECKING #{coll} collection for availability of UUID: #{trial_id}"
      if coll.where(:_id => trial_id).fields(:_id).first.nil?
        @_id = trial_id
      end
    end while @_id.nil?

  end
  
  def make_uuid
    uuid = SecureRandom.uuid.gsub!('-', '')
    unless self.is_a?(MongoMapper::EmbeddedDocument)
      if self.class.single_collection_inherited?
        lookup_class = self.class.collection_name.singularize.camelize.constantize
      else
        lookup_class = self.class
      end
      replacement_lsn = UuidModel.class_lsn_lookup[lookup_class] || 0x00
      uuid[-2..-1] = replacement_lsn.to_s(16).rjust(2,'0')
    end
    
    BSON::Binary.new(uuid, BSON::Binary::SUBTYPE_UUID)
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

class UuidModel
  
  include MongoMapper::Document
  plugin  MmUsesUuid
  
  @@lsn_class_lookup ||= {}
  
  class << self
  
    def add_lsn_mapping(ind, klass)
      @@lsn_class_lookup[ind] = klass
      @@class_lsn_lookup = @@lsn_class_lookup.invert
    end
    
    def lsn_class_lookup
      @@lsn_class_lookup
    end
    
    def class_lsn_lookup
      @@class_lsn_lookup
    end
    
    def find(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      fields  = *options[:fields]
      batch_mode = args.first.is_a?(Array) || args.length > 1
      ids = args.flatten.uniq
      ids_by_class = ids.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |id, hsh|
        lsn = id.to_s[-2..-1].hex
        klass = @@lsn_class_lookup[lsn]
        if klass.nil?
          raise "expected to find a class in @@lsn_class_lookup[#{lsn}] of the MongoMapper module but there was no entry. You need to set uuid_lsn in your class."
        end
        hsh[klass] << id
      end
      
      if defined? Celluloid
      
        future_results = ids_by_class.map do |klass, ids|
          Celluloid::Future.new { klass.where(:id => convert_ids_to_BSON(ids)).fields(fields).all }
        end
        results = future_results.map(&:value).flatten
        
      else
        
        results = ids_by_class.map do |klass, ids|
          klass.where(:id => convert_ids_to_BSON(ids)).fields(fields).all
        end.flatten

      end
        
      batch_mode ? results : results.first
    end
    alias_method :find_with_fields, :find
    
    def find!(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      ids = args.flatten.uniq
      raise MongoMapper::DocumentNotFound, "Couldn't find without an ID" if ids.size == 0
      find(*ids, options).tap do |result|
        if result.nil? || ids.size != Array(result).size
          raise MongoMapper::DocumentNotFound, "Couldn't find all of the ids (#{ids.join(',')}). Found #{Array(result).size}, but was expecting #{ids.size}"
        end
      end
    end
    alias_method :find_with_fields!, :find!

  end

end
