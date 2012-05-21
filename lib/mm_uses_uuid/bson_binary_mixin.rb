require 'bson/byte_buffer'

module BSON

  class Binary < ByteBuffer

    def inspect
      string_render = self.to_s
      if string_render.empty?
        "<BSON::Binary:#{object_id}>"
      else
        if string_render.length > 32
          "<BSON::Binary:'#{string_render[0..8]}...'}'>"
        else
          "<BSON::Binary:'#{string_render}'>"
        end
        
      end
    end
    
    def eql?(value)
      self.to_s == value.to_s
    end

  end
  
end