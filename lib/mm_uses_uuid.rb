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
    key :_id, BsonUuid, :default => lambda { make_uuid }
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
    
    def make_uuid
      uuid = SecureRandom.uuid.gsub!('-', '')
      if single_collection_inherited? and not embeddable?
        lookup_class_name = collection_name.singularize.camelize
      else
        lookup_class_name = name
      end
      replacement_lsn = UuidModel.class_lsn_lookup[lookup_class_name] || 0x00
      uuid[-2..-1] = replacement_lsn.to_s(16).rjust(2,'0')
      BSON::Binary.new(uuid, BSON::Binary::SUBTYPE_UUID)
      
    rescue => e
      binding.pry
      raise e
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
    
    # def new(params = {})
      # passed_id = params.delete(:id) || params.delete(:_id) || params.delete('id') || params.delete('_id')
      # new_object = super(params)
      # if passed_id
        # if passed_id.is_a?(BSON::Binary) and passed_id.subtype == BSON::Binary::SUBTYPE_UUID
          # new_object.id = passed_id
        # else
          # raise ArgumentError, "if you pass an explicit :id parameter it must be a valid BSON::Binary::SUBTYPE_UUID"
        # end
      # else
        # new_object.find_new_uuid
      # end
      # new_object
    # end

    def uuid_lsn(lsn_integer)
      raise "lsn_integer must be from 0-255" unless (0..255).cover?(lsn_integer)
      UuidModel.add_lsn_mapping(lsn_integer, self.name)
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
    self.class.make_uuid
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
  
    def add_lsn_mapping(ind, class_name)
      class_name = class_name.to_s
      if current_class_name = @@lsn_class_lookup[ind]
        raise "cannont assign #{class_name} to #{ind} as #{current_class_name} is already assigned to that LSN"
      end
      @@lsn_class_lookup[ind] = class_name
      @@class_lsn_lookup = @@lsn_class_lookup.invert
    end
    
    def lsn_class_lookup
      @@lsn_class_lookup
    end
    
    def class_lsn_lookup
      @@class_lsn_lookup
    end
    
    def class_name_from_id(id, options = {})
      lsn = id.to_s[-2..-1].hex
      class_name = @@lsn_class_lookup[lsn]
      if class_name.nil? and options[:error_if_no_lsn_match]
        raise "expected to find a class name in @@lsn_class_lookup[#{lsn}] of the MongoMapper module but there was no entry. You need to set uuid_lsn in your class."
      end
      class_name
    end
    
    def find_by_id(id)
      find id
    end
    
    def find(*args)
      
      # raise "foo"
      
      options = args.last.is_a?(Hash) ? args.pop : {}
      fields  = *options[:fields]
      fields  = nil if fields.empty?
      batch_mode = args.first.is_a?(Array) || args.length > 1
      ids = args.flatten.uniq
      ids.map! {|id| BsonUuid.to_mongo(id)}
      
      ids_by_model = ids.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |id, hsh|
        model_name = class_name_from_id(id, options)
        hsh[model_name.constantize] << id if model_name
      end
      
      if defined? Celluloid
        
        #NOTE: because IdentityMap is in the current thread only...
        #we have to manage it ourselves if using Celluloid
        
        im_results = []
        
        unless fields
          ids_by_model.clone.each do |model, model_ids|
            model_ids.each do |model_id|
              doc = model.get_from_identity_map(model_id)
              if doc
                im_results << doc
                ids_by_model[model].delete model_id
              end
            end
            ids_by_model.delete(model) if ids_by_model[model].empty?
          end
        end
      
        future_db_results = ids_by_model.map do |model, model_ids|
          query = model.where(:id => model_ids)
          query = query.fields(fields) if fields
          Celluloid::Future.new { query.all }
        end
        
        db_results = future_db_results.map(&:value).flatten
        
        if fields
          db_results.each(&:remove_from_identity_map)
        else
          db_results.each(&:add_to_identity_map)
        end
        
        results = im_results + db_results
        
      else
        
        #NOTE: as this is in the current thread, IdentityMap management is normal
        
        results = ids_by_model.map do |model, model_ids|
          if fields
            model.where(:id => model_ids).fields(fields).all #models will be removed from the map
          else
            model.find model_ids #we use this so that we read and write to the identity map
          end
        end.flatten

      end
      
      batch_mode ? results : results.first
      
    # rescue => e
      # binding.pry
    end
    alias_method :find_with_fields, :find
    
    def find!(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      options.merge(:error_if_no_lsn_match => true)
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
