module YamahaSysex
  def manufacturer_id() 0x43 end
end

DeviceClass.new('Yamaha MU50') do |c|
  class << c
    include YamahaSysex
    def family_code() "\x00\x41" end
    def model_number() "\x46\x01" end
    def version_number() "\x00\x00\x00\x01" end
  end
end
