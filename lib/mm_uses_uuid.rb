require 'mongo_mapper'
require_relative "mm_uses_uuid/version"
require_relative "mm_uses_uuid/bson_binary_mixin"

module MmUsesUuid
  extend ActiveSupport::Concern

  included do
    key :_id, BsonUuid
  end

  class BsonUuid
    def self.to_mongo(value)
      case value
      when String
        BSON::Binary.new(value, BSON::Binary::SUBTYPE_UUID)
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
  
  module ClassMethods
    
    def find(*args)
      
      args.flatten!
      if args.size > 1
        args.map! {|id| BsonUuid.to_mongo(id)}
      else
        args = BsonUuid.to_mongo(args.first)
      end
      
      super(args)
    end
    
    def new(*args)
      new_object = super(*args)
      new_object.find_new_uuid
      new_object
    end

  end

  module InstanceMethods
    
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
        puts "CHECKING #{coll} collection for availability of #{variant} UUID: #{trial_id}"
        if coll.where(:_id => trial_id).fields(:_id).first.nil?
          @_id = trial_id
        end
      end while @_id.nil?

    end
    
    def make_uuid
        uuid = SecureRandom.uuid.gsub!('-', '')
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
end
