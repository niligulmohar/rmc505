
######################################################################

class SparseArray
  attr_accessor :elements, :submaps
  attr_reader :parent
  def initialize(parent = nil, offset = 0)
    @parent = parent
    @offset = offset
    @elements = []
    @submaps = []
    yield self if block_given?
  end
  def submap_objects
    @submaps.collect{ |r, o| o }
  end
  def [](index)
    if (index-@offset) < @elements.length
      return @elements[index-@offset]
    else
      @submaps.each do |r, o|
        if r.member?(index)
          return o[index]
        end
      end
      unmapped_element(index)
    end
  end
  def []=(index, value)
    if (index-@offset) < @elements.length
      return @elements[index-@offset].set(value)
    else
      @submaps.each do |r, o|
        if r.member?(index)
          return o[index] = value
        end
      end
      unmapped_element(index)
    end
  end
  def unmapped_element(index)
    fail "Address #{index} is unmapped"
  end
  def end
    (@submaps.collect{ |r, o| r.last } + [@offset + @elements.length]).max
  end
  def length
    self.end - @offset
  end
  def offset(o = 0, *args, &block)
    add_submap_of_class(self.class, o, *args, &block)
  end
  def start
    @offset
  end
  def start_and_length
    [start, length]
  end
  def add(element)
    element.offset = @offset + @elements.length
    @elements.push(element)
    check_overlap!
  end
  def add_submap_of_class(cls, offset = 0, *args)
    submap = cls.new(self, offset + @offset, *args)
    yield submap if block_given?
    @submaps.push([(offset ... offset+submap.length), submap])
    check_overlap!
  end
  def check_overlap!
    if !@submaps.empty? && !@elements.empty?
      fail if @elements.length > @submaps.map{ |r, o| r.first }.min
    end
  end
  def map(new_class = nil, &element_block)
    cls = new_class || self.class
    result = cls.new(@parent, @offset)
    result.elements = @elements.map(&element_block)
    result.submaps = @submaps.map do |range, submap|
      [range, submap.map(new_class, &element_block)]
    end
    return result
  end
  def each_element_group
    yield [@offset, @elements] if @elements.length > 0
    submap_objects.each do |s|
      s.each_element_group{ |o, elts| yield [o + @offset, elts] }
    end
  end
  def each_contiguous_element_group(start, length)
    accumulated = nil
    each_element_group do |offset, elements|
      start_offset = [0, start-offset].max
      end_offset = [0, (start+length)-offset].max
      append = elements[start_offset...end_offset]
      if append.length > 0
        if accumulated
          if accumulated.first + accumulated.last.length == offset + start_offset
            accumulated[1] += append
          else
            yield accumulated
            accumulated = [start_offset, append]
          end
        else
          accumulated = [start_offset, append]
        end
      end
    end
    yield accumulated if accumulated
  end
end

class ByteParameter
  attr_reader :name, :range, :choices, :default
  attr_accessor :parent, :offset
  def initialize(name, range, choices = nil, default = nil)
    super()
    @name = name
    @range = range
    @choices = choices
    @default = default || range.first
  end
  def dump(indentataion, value)
    $logger.debug("#{'  '*indentataion}%8x | %2x | %s (%s)" % [@offset,
                                                               value,
                                                               @name,
                                                               @range])
  end
end

module Observable
  alias_method :old_notify_observers, :notify_observers
  def notify_observers(*args)
    # Observers may be Qt widgets that have been manually disposed.
    # Notifying them will cause segmentation faults.
    @observer_peers.reject!{ |peer| peer.disposed? } if @observer_peers
    old_notify_observers(*args)
  end
end

class ParameterStorage
  include Observable
  attr_reader :parameter, :value
  def initialize(parameter)
    fail unless parameter.kind_of?(ByteParameter)
    @parameter = parameter
    @value = @parameter.default
  end
  def set(value)
    return if value == @value
    unless parameter.range.member?(value)
      dump
      $logger.error("Parameter #{parameter.name} value #{value} out of range")
    end
    @value = value
    dump
    changed
    notify_observers()
  end
  def dump(indentataion = 0)
    @parameter.dump(indentataion, @value)
  end
end

class ParameterData < SparseArray
  include Observable
  attr_accessor :map_parent
  def dump(indentation = 0)
    if @map_parent and @map_parent.name
      $logger.debug("#{'  '*indentation}#{@map_parent.name}")
    end
    @elements.each do |elt|
      elt.dump(indentation)
    end
    @submaps.each do |r, o|
      $logger.debug("#{'  '*(indentation+1)}(%8x...%8x)" % [r.first, r.last])
      o.dump(indentation + 1)
    end
  end
  def set_byte(offset, value)
    self[offset].set(value)
  end
  def entry_name
    map = @map_parent
    return '?' if map.nil?
    while map.list_entry.nil?
      map = map.parent
      return '?' if map.nil?
    end
    map.name
  end
  def name
    if @map_parent
      @map_parent.name
    else
      nil
    end
  end
  def <=>(other)
    [start, name] <=> [other.start, other.name]
  end
  def update_elements_and_notify
    yield @elements
    changed
    notify_observers
  end
end

class ParameterMap < SparseArray
  attr_reader :name
  attr_accessor :parameter_set_class, :list_entry, :page_entry
  attr_accessor :midi_channel, :midi_note, :delay

  def initialize(parent = nil, offset = 0, name = nil, &block)
    super(parent, offset, &block)
    @name = name
  end
  def map(cls)
    result = super
    result.map_parent = self
    return result
  end
  def new_data
    map(ParameterData) do |parameter|
      ParameterStorage.new(parameter)
    end
  end
  def special_widget?
    false
  end

  def param(*args)
    add(ByteParameter.new(*args))
  end
end

######################################################################

class DeviceClass
  class << self
    def [](name)
      @@classes[name]
    end
    def connection(sysex, port)
      @@classes.values.each do |cls|
        if sysex.identity_response?
          match = cls.identity_response_match?(sysex) and channel = sysex.sysex_channel
        else
          if cls.respond_to?(:sysex_match_channel)
            channel = cls.sysex_match_channel(sysex)
            match = !!channel
          else
            match = false
          end
        end
        if match
          return cls.new(channel, port)
        end
      end
      return nil
    end
  end

  attr_reader :name, :connection_methods
  attr_accessor :family_code, :model_number, :version_number, :icon
  attr_writer :priority
  def initialize(name)
    @@classes ||= {}
    @@classes[name] = self
    @name = name
    @connection_methods = []
    yield self
  end
  def priority
    @priority || 2
  end
  def new(sysex_channel, port)
    DeviceConnection.new(self, sysex_channel, port)
  end
    def log_format(sysex_channel, format, *args)
    ("%s(%02x) " + format) % ([name, sysex_channel] + args)
  end
  def identity_response_match?(identity_response, quiet = false)
    m, f, model, v = manufacturer_id.chr, family_code, model_number, version_number
    # $logger.debug("Comparing#{sysex_event.variable_data.hexdump}")
    # $logger.debug("       to" + "\xf0\x7e\0\x06\x02#{m}#{f}#{model}#{v}\xf7".hexdump)
    if identity_response.variable_data =~ /^\xf0\x7e.\x06\x02#{m}#{f}#{model}....\xf7$/
      unless quiet
        channel = identity_response.sysex_channel
        $logger.info(log_format(channel,
                                "--> Identity response from %s",
                                identity_response.source_ids))
        version = identity_response.variable_data[10..13]
        unless /#{v}/ =~ version
          $logger.warn(log_format(channel,
                                  "The device reports it is of version#{version.hexdump}, which is untested."))
        end
      end
      return true
    else
      return false
    end
  end
  def parameter_map(&block)
    if block_given?
      @parameter_map_block = block
    else
      unless @parameter_map
        @parameter_map = ParameterMap.new(&@parameter_map_block)
      end
      @parameter_map
    end
  end
end

class DeviceConnection
  attr_reader :device_class, :parameter_data
  def initialize(device_class, sysex_channel, port)
    @device_class = device_class
    extend(*@device_class.connection_methods)
    @sysex_channel = sysex_channel
    @port = port
    if device_class.parameter_map
      @parameter_data = device_class.parameter_map.new_data
      # @parameter_data.dump if @device_class.name =~ /Juno/
    end
  end
  def log_format(format, *args)
    ("%s(%02x) " + format) % ([@device_class.name, @sysex_channel] + args)
  end
  def send_sysex(data)
    $logger.debug(log_format("<-- %s", data.hexdump))
    @port.event_output! do |event|
      event.direct!
      event.set_sysex(data)
    end
  end
  def send_read_data_request(start, length)
    send_sysex(read_data_request(start, length))
  end
  def send_write_data_request(start, length)
    $logger.debug(log_format("<-- auto send parameters"))
    @parameter_data.each_contiguous_element_group(start, length) do |s, elts|
      send_sysex(write_data_request(s, elts.collect{ |elt| elt.value.chr }.join))
    end
  end

  def name
    # "#{@device_class.name} (0x%02x) #{@port.ids}" % @sysex_channel
    @device_class.name
  end

  def sysex_match?(sysex)
    if sysex.identity_response?
      identity_response_match?(sysex)
    else
      respond_to?(:specific_sysex_match?) and specific_sysex_match?(sysex)
    end
  end

  def identity_response_match?(identity_response)
    if @device_class.identity_response_match?(identity_response, true) &&
        identity_response.sysex_channel == @sysex_channel
    then
      $logger.info(log_format("--> Duplicate identity response from %s",
                              identity_response.source_ids))
      return true
    else
      return false
    end
  end
  def recieve_sysex(sysex_event)
    if read_data_response?(sysex_event.variable_data)
      recieve_data(*parse_read_data_response(sysex_event.variable_data))
      $logger.debug(log_format("--> Recieved ~%d bytes of parameters",
                               sysex_event.variable_data.length - 11))
    elsif not sysex_event.identity_response?
      $logger.warn(log_format("--> Unrecognized sysex:"))
      $logger.debug(log_format("-->#{sysex_event.variable_data.hexdump}"))
    end
  end
  def recieve_data(start, data)
    data.split('').each_with_index do |byte, index|
      @parameter_data[start+index] = byte[0]
    end
  end
end

######################################################################

module RandomAccessParameters
  def auto_read_data_request(*args)
    send_read_data_request(*args)
  end
  def auto_write_data_request(*args)
    send_write_data_request(*args)
  end
end

module PushedParameters
  def auto_read_data_request(*args)
  end
  def auto_write_data_request(*args)
    send_write_data_request(*args)
  end
end

module BulkParameters
  def auto_read_data_request(*args)
  end
  def auto_write_data_request(*args)
  end
end

######################################################################

Dir.glob('devices/*.rb').each do |filename|
  require filename[0..-4]
end
